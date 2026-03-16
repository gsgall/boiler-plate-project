//! Build libc++/libc++abi/libunwind as dynamic libraries from Zig's source.
//!
//! Note that this is just an attempt to address the issue mentioned in Zig's
//! issue #24831 to make it possible to build a C++ project and its
//! dependencies with Zig where the main executable requires to link against
//! multiple shared libraries.
//!
//! There might be some configurations not being handled properly for other OS.
//!
//! Note
//! ====
//! - Currently libunwind must be statically linked.
//! - Exception in libc++abi is enabled by default.
//! - Part of the flags for building libc++ (see `addCxxArgs()`) also have to
//!   be added to any module which needs to link against libc++. This behavior
//!   is the same as how Zig deal with the linkage request for libc++ (see [1]).
//!   This is because Zig adds the flags via `-D` instead of relying on
//!   `__config_site` when building libc++ in order to adjust configuration for
//!   different use case.
//!
//! Sources
//! =======
//! This file is mainly a port of the following build scripts:
//! - https://github.com/ziglang/zig/blob/0.15.1/libs/libcxx.zig
//! - https://github.com/ziglang/zig/blob/0.15.1/libs/libunwind.zig
//!
//! Links
//! =====
//! [1]: https://github.com/ziglang/zig/blob/0.15.1/src/Compilation.zig#L6966-L6978
const std = @import("std");

const libcxxabi_files = [_][]const u8{
    "abort_message.cpp",
    "cxa_aux_runtime.cpp",
    "cxa_default_handlers.cpp",
    "cxa_demangle.cpp",
    "cxa_exception.cpp",
    "cxa_exception_storage.cpp",
    "cxa_guard.cpp",
    "cxa_handlers.cpp",
    // TODO: this file should not be added when exception is enabled, but why
    // it's added here? (we didn't find any code to exclude it, might need to
    // figure out whether Zig does this intentionally or not)
    // "cxa_noexception.cpp",
    "cxa_personality.cpp",
    "cxa_thread_atexit.cpp",
    "cxa_vector.cpp",
    "cxa_virtual.cpp",
    "fallback_malloc.cpp",
    "private_typeinfo.cpp",
    "stdlib_exception.cpp",
    "stdlib_new_delete.cpp",
    "stdlib_stdexcept.cpp",
    "stdlib_typeinfo.cpp",
};

const libcxx_base_files = [_][]const u8{
    "algorithm.cpp",
    "any.cpp",
    "bind.cpp",
    "call_once.cpp",
    "charconv.cpp",
    "chrono.cpp",
    "error_category.cpp",
    "exception.cpp",
    "expected.cpp",
    "filesystem/directory_entry.cpp",
    "filesystem/directory_iterator.cpp",
    "filesystem/filesystem_clock.cpp",
    "filesystem/filesystem_error.cpp",
    // omit int128_builtins.cpp because it provides __muloti4 which is already provided
    // by compiler_rt and crashes on Windows x86_64: https://github.com/ziglang/zig/issues/10719
    //"filesystem/int128_builtins.cpp",
    "filesystem/operations.cpp",
    "filesystem/path.cpp",
    "fstream.cpp",
    "functional.cpp",
    "hash.cpp",
    "ios.cpp",
    "ios.instantiations.cpp",
    "iostream.cpp",
    "locale.cpp",
    "memory.cpp",
    "memory_resource.cpp",
    "new.cpp",
    "new_handler.cpp",
    "new_helpers.cpp",
    "optional.cpp",
    "ostream.cpp",
    "print.cpp",
    //"pstl/libdispatch.cpp",
    "random.cpp",
    "random_shuffle.cpp",
    "regex.cpp",
    "ryu/d2fixed.cpp",
    "ryu/d2s.cpp",
    "ryu/f2s.cpp",
    "stdexcept.cpp",
    "string.cpp",
    "strstream.cpp",
    "support/ibm/mbsnrtowcs.cpp",
    "support/ibm/wcsnrtombs.cpp",
    "support/ibm/xlocale_zos.cpp",
    "support/win32/locale_win32.cpp",
    "support/win32/support.cpp",
    "system_error.cpp",
    "typeinfo.cpp",
    "valarray.cpp",
    "variant.cpp",
    "vector.cpp",
    "verbose_abort.cpp",
};

const libcxx_thread_files = [_][]const u8{
    "atomic.cpp",
    "barrier.cpp",
    "condition_variable.cpp",
    "condition_variable_destructor.cpp",
    "future.cpp",
    "mutex.cpp",
    "mutex_destructor.cpp",
    "shared_mutex.cpp",
    "support/win32/thread_win32.cpp",
    "thread.cpp",
};

const libunwind_files = [_][]const u8{
    "libunwind.cpp",
    "Unwind-EHABI.cpp",
    "Unwind-seh.cpp",
    "UnwindLevel1.c",
    "UnwindLevel1-gcc-ext.c",
    "Unwind-sjlj.c",
    "Unwind-wasm.c",
    "UnwindRegistersRestore.S",
    "UnwindRegistersSave.S",
    "Unwind_AIXExtras.cpp",
    "gcc_personality_v0.c",
};

const LibunwindSrcType = enum { c, cpp, asm_with_cpp };

/// A simple wrapper for managed `std.ArraryList` since `std.array_list.Managed()`
/// is deprecated after Zig 0.15.
pub const FlagList = struct {
    list: std.ArrayList(ElType),
    arena: std.mem.Allocator,

    const ElType = []const u8;

    pub fn init(arena: std.mem.Allocator) @This() {
        return .{ .list = .empty, .arena = arena };
    }

    pub fn deinit(self: *@This()) void {
        self.list.deinit(self.arena);
    }

    pub fn append(self: *@This(), item: ElType) !void {
        try self.list.append(self.arena, item);
    }

    pub fn appendSlice(self: *@This(), items: []const ElType) !void {
        try self.list.appendSlice(self.arena, items);
    }
};

pub const LibCxxBuildConfig = struct {
    zig_lib_dir: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
    pic: bool,
    any_non_single_threaded: bool,
};

pub const LibCxxDeps = struct {
    libcxx: ?*std.Build.Step.Compile,
    libcxxabi: ?*std.Build.Step.Compile,
    libunwind: ?*std.Build.Step.Compile,
    flags: []const []const u8,

    /// Link libcxx and libcxxabi. But we actually need to add include dirs as
    /// well, see also how Zig handled it:
    /// https://github.com/ziglang/zig/blob/0.15.1/src/Compilation.zig#L6966-L6978
    pub fn linkLibCxx(self: @This(), mod: *std.Build.Module) void {
        const linkDir = struct {
            fn func(m: @TypeOf(mod), include_dirs: []std.Build.Module.IncludeDir) void {
                for (include_dirs) |inc_dir| switch (inc_dir) {
                    .path => |lp| {
                        m.addIncludePath(lp);
                    },
                    .config_header_step => |ch| {
                        m.addIncludePath(ch.getOutputDir());
                    },
                    else => {},
                };
            }
        }.func;

        if (self.libcxx) |lib| {
            mod.linkLibrary(lib);
            linkDir(mod, lib.root_module.include_dirs.items);
        }
        if (self.libcxxabi) |lib| {
            mod.linkLibrary(lib);
            linkDir(mod, lib.root_module.include_dirs.items);
        }
        if (self.libunwind) |lib| {
            mod.linkLibrary(lib);
        }
    }

    pub fn dupeFlags(self: @This(), arena: std.mem.Allocator) !FlagList {
        var cloned = FlagList.init(arena);
        for (self.flags) |flag| {
            try cloned.append(flag);
        }
        return cloned;
    }
};

pub fn getZigLibDir(arena: std.mem.Allocator) ![]const u8 {
    const result = try std.process.Child.run(.{
        .allocator = arena,
        .argv = &.{ "zig", "env" },
    });

    const duped = try arena.dupeZ(u8, result.stdout);
    defer arena.free(duped);

    const ZigEnv = struct {
        lib_dir: []const u8,
    };

    const zig_env = try std.zon.parse.fromSlice(ZigEnv, arena, duped, null, .{
        .ignore_unknown_fields = true,
        .free_on_error = true,
    });
    return try arena.dupe(u8, zig_env.lib_dir);
}

pub fn buildLazyPath(arena: std.mem.Allocator, paths: []const []const u8) !std.Build.LazyPath {
    return .{ .cwd_relative = try std.fs.path.resolve(arena, paths) };
}

/// A helper function to setup the bulid graph for libcxx/libcxxabi/libunwind.
pub fn buildLibCxxAndOthers(
    b: *std.Build,
    cfg: LibCxxBuildConfig,
    build_libcxxabi: bool,
    build_libunwind: bool,
) !LibCxxDeps {
    const arena = b.allocator;

    const OptionalCompile = ?*std.Build.Step.Compile;
    const libunwind: OptionalCompile = if (build_libunwind) try buildLibUnwind(b, cfg) else null;
    const libcxxabi: OptionalCompile = if (build_libcxxabi) try buildLibCxxAbi(b, cfg) else null;

    const libcxx = try buildLibCxx(b, cfg);

    if (libunwind) |comp| {
        if (libcxxabi) |comp_cxxabi| {
            comp_cxxabi.step.dependOn(&comp.step);
            comp_cxxabi.linkLibrary(comp);
        }

        libcxx.step.dependOn(&comp.step);
        libcxx.linkLibrary(comp);
    }

    if (libcxxabi) |comp| {
        libcxx.step.dependOn(&comp.step);
        libcxx.linkLibrary(comp);
    }

    var flags = FlagList.init(arena);
    try addCxxArgs(arena, cfg, &flags);

    return .{
        .libcxx = libcxx,
        .libcxxabi = libcxxabi,
        .libunwind = libunwind,
        .flags = flags.list.items,
    };
}

pub fn buildLibCxx(
    b: *std.Build,
    cfg: LibCxxBuildConfig,
) !*std.Build.Step.Compile {
    const arena = b.allocator;
    const target = cfg.target.result;

    const root_mod = b.createModule(.{
        .target = cfg.target,
        .optimize = cfg.optimize,
        .pic = cfg.pic,
        // TODO: we follow the same configs done in `libcxx.zig` here, so the actual libc to use
        // will be determined by Zig's builder. Not sure whether it would affect our case.
        // https://github.com/ziglang/zig/blob/0.15.1/src/libs/libcxx.zig#L143
        .link_libc = true,
        .link_libcpp = false,
    });

    const cxx_src = try buildLazyPath(arena, &.{ cfg.zig_lib_dir, "libcxx", "src" });
    const cxx_include = try buildLazyPath(arena, &.{ cfg.zig_lib_dir, "libcxx", "include" });
    const cxxabi_include = try buildLazyPath(arena, &.{ cfg.zig_lib_dir, "libcxxabi", "include" });
    const cxx_src_include = try buildLazyPath(arena, &.{ cfg.zig_lib_dir, "libcxx", "src" });

    const cxx_libc_include = try buildLazyPath(arena, &.{ cfg.zig_lib_dir, "libcxx", "libc" });

    // Prepare flags
    var cflags = FlagList.init(arena);

    try addCxxArgs(arena, cfg, &cflags);

    try cflags.append("-DNDEBUG");
    try cflags.append("-DLIBC_NAMESPACE=__llvm_libc_common_utils");
    try cflags.append("-D_LIBCPP_BUILDING_LIBRARY");

    // NOTE: this flag is also required to make exception handling available, see:
    // https://github.com/ziglang/zig/blob/0.15.1/lib/libcxx/src/exception.cpp
    try cflags.append("-DLIBCXX_BUILDING_LIBCXXABI");

    try cflags.append("-D_LIBCPP_HAS_NO_PRAGMA_SYSTEM_HEADER");

    // TODO: support threads?
    // https://github.com/llvm/llvm-project/blob/llvmorg-20.1.8/libcxx/CMakeLists.txt#L294-L306
    // try cflags.append("-D_LIBCPP_HAS_THREADS");
    // try cflags.append("-D_LIBCPP_HAS_THREADS_PTHREAD");
    // try cflags.append("-D_LIBCPP_HAS_MONOTONIC_CLOCK");

    if (target.os.tag == .wasi) {
        try cflags.append("-fno-exceptions");
    }

    try cflags.append("-fvisibility=hidden");
    try cflags.append("-fvisibility-inlines-hidden");

    if (target.os.tag == .zos) {
        try cflags.append("-fno-aligned-allocation");
    } else {
        try cflags.append("-faligned-allocation");
    }

    try cflags.append("-nostdinc++");
    try cflags.append("-std=c++23");
    try cflags.append("-Wno-user-defined-literals");
    try cflags.append("-Wno-covered-switch-default");
    try cflags.append("-Wno-suggest-override");

    // Prepare source files
    const libcxx_files = if (cfg.any_non_single_threaded)
        &(libcxx_base_files ++ libcxx_thread_files)
    else
        &libcxx_base_files;

    var c_source_files = std.array_list.Managed([]const u8).init(arena);

    for (libcxx_files) |f| {
        if (std.mem.startsWith(u8, f, "filesystem/") and target.os.tag == .wasi)
            continue;
        if (std.mem.startsWith(u8, f, "support/win32/") and target.os.tag != .windows)
            continue;
        if (std.mem.startsWith(u8, f, "support/ibm/") and target.os.tag != .zos)
            continue;

        try c_source_files.append(f);
    }

    root_mod.addIncludePath(cxx_include);
    root_mod.addIncludePath(cxxabi_include);
    root_mod.addIncludePath(cxx_src_include);
    root_mod.addIncludePath(cxx_libc_include);

    root_mod.addCSourceFiles(.{
        .root = cxx_src,
        .files = c_source_files.items,
        .flags = cflags.list.items,
        .language = .cpp,
    });

    const lib = b.addLibrary(.{
        .name = "c++",
        .root_module = root_mod,
        .linkage = cfg.linkage,
        .version = .{ .major = 1, .minor = 0, .patch = 0 },
    });

    return lib;
}

pub fn buildLibCxxAbi(
    b: *std.Build,
    cfg: LibCxxBuildConfig,
) !*std.Build.Step.Compile {
    const arena = b.allocator;
    const target = cfg.target.result;

    const unwind_tables: std.builtin.UnwindTables =
        if (target.os.tag == .wasi or (target.cpu.arch == .x86 and target.os.tag == .windows)) .none else .async;

    const root_mod = b.createModule(.{
        .target = cfg.target,
        .optimize = cfg.optimize,
        .pic = cfg.pic,
        // TODO: see also the same thing mentioned in `buildLibCxx()` above.
        .link_libc = true,
        .link_libcpp = false,
        .unwind_tables = unwind_tables,
    });

    const cxxabi_src = try buildLazyPath(arena, &.{ cfg.zig_lib_dir, "libcxxabi", "src" });
    const cxxabi_include = try buildLazyPath(arena, &.{ cfg.zig_lib_dir, "libcxxabi", "include" });
    const cxx_include = try buildLazyPath(arena, &.{ cfg.zig_lib_dir, "libcxx", "include" });
    const cxx_src_include = try buildLazyPath(arena, &.{ cfg.zig_lib_dir, "libcxx", "src" });

    // Prepare flags
    var cflags = FlagList.init(arena);

    try addCxxArgs(arena, cfg, &cflags);

    try cflags.append("-DNDEBUG");
    try cflags.append("-D_LIBCXXABI_BUILDING_LIBRARY");
    if (!cfg.any_non_single_threaded) {
        try cflags.append("-D_LIBCXXABI_HAS_NO_THREADS");
    }
    if (target.abi.isGnu()) {
        if (target.os.tag != .linux or !(target.os.versionRange().gnuLibCVersion().?.order(.{ .major = 2, .minor = 18, .patch = 0 }) == .lt))
            try cflags.append("-DHAVE___CXA_THREAD_ATEXIT_IMPL");
    } else if (target.os.tag == .macos) {
        try cflags.append("-DHAVE___CXA_THREAD_ATEXIT_IMPL");
    }

    try cflags.append("-D_LIBCPP_ABI_VERSION=1");
    try cflags.append("-D_LIBCPP_ABI_NAMESPACE=__1");

    // TODO: make this configurable?
    try cflags.append("-DLIBCXXABI_ENABLE_EXCEPTIONS");

    if (target.os.tag == .wasi) {
        try cflags.append("-fno-exceptions");
    }

    try cflags.append("-fvisibility=hidden");
    try cflags.append("-fvisibility-inlines-hidden");

    try cflags.append("-nostdinc++");
    try cflags.append("-fstrict-aliasing");
    try cflags.append("-std=c++23");
    try cflags.append("-Wno-user-defined-literals");
    try cflags.append("-Wno-covered-switch-default");
    try cflags.append("-Wno-suggest-override");

    // Prepare source files
    var c_source_files = std.array_list.Managed([]const u8).init(arena);

    for (libcxxabi_files) |f| {
        if (!cfg.any_non_single_threaded and std.mem.startsWith(u8, f, "cxa_thread_atexit.cpp"))
            continue;
        if (target.os.tag == .wasi and
            (std.mem.eql(u8, f, "cxa_exception.cpp") or std.mem.eql(u8, f, "cxa_personality.cpp")))
            continue;

        try c_source_files.append(f);
    }

    root_mod.addIncludePath(cxxabi_include);
    root_mod.addIncludePath(cxx_include);
    root_mod.addIncludePath(cxx_src_include);

    root_mod.addCSourceFiles(.{
        .root = cxxabi_src,
        .files = c_source_files.items,
        .flags = cflags.list.items,
        .language = .cpp,
    });

    const lib = b.addLibrary(.{
        .name = "c++abi",
        .root_module = root_mod,
        .linkage = cfg.linkage,
        .version = .{ .major = 1, .minor = 0, .patch = 0 },
    });
    // Allow undefined symbols to be resolved at runtime from libSystem on macOS
    if (target.os.tag == .macos) {
        lib.linker_allow_shlib_undefined = true;
    }

    return lib;
}

pub fn buildLibUnwind(
    b: *std.Build,
    cfg: LibCxxBuildConfig,
) !*std.Build.Step.Compile {
    const arena = b.allocator;
    const target = cfg.target.result;

    const unwind_tables: std.builtin.UnwindTables =
        if (target.os.tag == .wasi or (target.cpu.arch == .x86 and target.os.tag == .windows)) .none else .async;

    const root_mod = b.createModule(.{
        .target = cfg.target,
        .optimize = cfg.optimize,
        .pic = cfg.pic,
        .link_libc = true,
        .link_libcpp = false,
        .unwind_tables = unwind_tables,
    });

    const unwind_src = try buildLazyPath(arena, &.{ cfg.zig_lib_dir, "libunwind", "src" });
    const unwind_inc = try buildLazyPath(arena, &.{ cfg.zig_lib_dir, "libunwind", "include" });

    var c_source_files = std.array_list.Managed([]const u8).init(arena);
    var cpp_source_files = std.array_list.Managed([]const u8).init(arena);
    var asm_source_files = std.array_list.Managed([]const u8).init(arena);

    for (libunwind_files) |f| {
        if (std.mem.endsWith(u8, f, ".c")) {
            try c_source_files.append(f);
        } else if (std.mem.endsWith(u8, f, ".cpp")) {
            try cpp_source_files.append(f);
        } else if (std.mem.endsWith(u8, f, ".S")) {
            try asm_source_files.append(f);
        } else unreachable;
    }

    var cflags = FlagList.init(arena);
    var cppflags = FlagList.init(arena);
    var asmflags = FlagList.init(arena);

    try addUnwindArgs(arena, cfg, .c, &cflags);
    try addUnwindArgs(arena, cfg, .cpp, &cppflags);
    try addUnwindArgs(arena, cfg, .asm_with_cpp, &asmflags);

    root_mod.addCSourceFiles(.{
        .root = unwind_src,
        .files = c_source_files.items,
        .flags = cflags.list.items,
        .language = .c,
    });

    root_mod.addCSourceFiles(.{
        .root = unwind_src,
        .files = cpp_source_files.items,
        .flags = cppflags.list.items,
        .language = .cpp,
    });

    // XXX: don't add "*.S" file via `addCSourceFiles()`, otherwise, clang will
    // complain with:
    // > error: cannot specify -o when generating multiple output files
    for (asm_source_files.items) |f| {
        root_mod.addCSourceFile(.{
            .file = try buildLazyPath(arena, &.{ cfg.zig_lib_dir, "libunwind", "src", f }),
            .flags = asmflags.list.items,
            .language = .assembly_with_preprocessor,
        });
    }

    root_mod.addIncludePath(unwind_inc);

    const lib = b.addLibrary(.{
        .name = "unwind",
        .root_module = root_mod,
        // XXX: currently libunwind must be static linked
        .linkage = .static,
        .version = .{ .major = 1, .minor = 0, .patch = 0 },
    });

    return lib;
}

/// Add required flags to build libcxx. Note that some flags are commented out
/// because we are trying to build it as a shared library.
pub fn addCxxArgs(
    arena: std.mem.Allocator,
    cfg: LibCxxBuildConfig,
    cflags: *FlagList,
) error{OutOfMemory}!void {
    const target = cfg.target;
    const optimize_mode = cfg.optimize;

    const abi_version: u2 = if (target.result.os.tag == .emscripten) 2 else 1;
    try cflags.append(try std.fmt.allocPrint(arena, "-D_LIBCPP_ABI_VERSION={d}", .{
        abi_version,
    }));
    try cflags.append(try std.fmt.allocPrint(arena, "-D_LIBCPP_ABI_NAMESPACE=__{d}", .{
        abi_version,
    }));
    try cflags.append(try std.fmt.allocPrint(arena, "-D_LIBCPP_HAS_{s}THREADS", .{
        if (!cfg.any_non_single_threaded) "NO_" else "",
    }));
    try cflags.append("-D_LIBCPP_HAS_MONOTONIC_CLOCK");
    try cflags.append("-D_LIBCPP_HAS_TERMINAL");
    try cflags.append(try std.fmt.allocPrint(arena, "-D_LIBCPP_HAS_{s}MUSL_LIBC", .{
        if (!target.result.abi.isMusl()) "NO_" else "",
    }));

    // For linking libcxxabi statically into libcxx, so we don't need this one.
    // - https://github.com/llvm/llvm-project/blob/llvmorg-20.1.8/libcxx/CMakeLists.txt#L823-L827
    // try cflags.append("-D_LIBCXXABI_DISABLE_VISIBILITY_ANNOTATIONS");

    // For bulding libcxx as a static library, so we don't need this one.
    // - https://releases.llvm.org/20.1.0/projects/libcxx/docs/UserDocumentation.html
    // - https://github.com/llvm/llvm-project/blob/llvmorg-20.1.8/libcxx/CMakeLists.txt#L815-L821
    // try cflags.append("-D_LIBCPP_DISABLE_VISIBILITY_ANNOTATIONS");

    // https://github.com/llvm/llvm-project/blob/llvmorg-20.1.8/libcxx/CMakeLists.txt#L126-L132
    try cflags.append("-D_LIBCPP_HAS_NO_VENDOR_AVAILABILITY_ANNOTATIONS");

    try cflags.append(try std.fmt.allocPrint(arena, "-D_LIBCPP_HAS_{s}FILESYSTEM", .{
        if (target.result.os.tag == .wasi) "NO_" else "",
    }));
    try cflags.append("-D_LIBCPP_HAS_RANDOM_DEVICE");
    try cflags.append("-D_LIBCPP_HAS_LOCALIZATION");
    try cflags.append("-D_LIBCPP_HAS_UNICODE");
    try cflags.append("-D_LIBCPP_HAS_WIDE_CHARACTERS");
    try cflags.append("-D_LIBCPP_HAS_NO_STD_MODULES");
    if (target.result.os.tag == .linux) {
        try cflags.append("-D_LIBCPP_HAS_TIME_ZONE_DATABASE");
    }
    // See libcxx/include/__algorithm/pstl_backends/cpu_backends/backend.h
    // for potentially enabling some fancy features here, which would
    // require corresponding changes in libcxx.zig, as well as
    // Compilation.addCCArgs. This option makes it use serial backend which
    // is simple and works everywhere.
    try cflags.append("-D_LIBCPP_PSTL_BACKEND_SERIAL");
    try cflags.append(switch (optimize_mode) {
        .Debug => "-D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_DEBUG",
        .ReleaseFast, .ReleaseSmall => "-D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_NONE",
        .ReleaseSafe => "-D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_FAST",
    });
    if (target.result.isGnuLibC()) {
        // glibc 2.16 introduced aligned_alloc
        if (target.result.os.versionRange().gnuLibCVersion().?.order(.{ .major = 2, .minor = 16, .patch = 0 }) == .lt) {
            try cflags.append("-D_LIBCPP_HAS_NO_LIBRARY_ALIGNED_ALLOCATION");
        }
    }
    try cflags.append("-D_LIBCPP_ENABLE_CXX17_REMOVED_UNEXPECTED_FUNCTIONS");
}

pub fn addUnwindArgs(
    arena: std.mem.Allocator,
    cfg: LibCxxBuildConfig,
    src_type: LibunwindSrcType,
    flags: *FlagList,
) error{OutOfMemory}!void {
    _ = arena;
    const target = cfg.target.result;

    switch (src_type) {
        .c => {
            try flags.append("-std=c99");
            try flags.append("-fexceptions");
        },
        .cpp => {
            try flags.append("-fno-exceptions");
            try flags.append("-fno-rtti");
        },
        .asm_with_cpp => {},
    }

    try flags.append("-D_LIBUNWIND_HIDE_SYMBOLS");
    try flags.append("-Wa,--noexecstack");
    try flags.append("-fvisibility=hidden");
    try flags.append("-fvisibility-inlines-hidden");
    try flags.append("-fvisibility-global-new-delete=force-hidden");

    try flags.append("-D_LIBUNWIND_IS_NATIVE_ONLY");

    if (cfg.optimize == .Debug) {
        try flags.append("-D_DEBUG");
    }
    if (!cfg.any_non_single_threaded) {
        try flags.append("-D_LIBUNWIND_HAS_NO_THREADS");
    }
    if (target.cpu.arch.isArm() and target.abi.float() == .hard) {
        try flags.append("-DCOMPILER_RT_ARMHF_TARGET");
    }
    try flags.append("-Wno-bitwise-conditional-parentheses");
    try flags.append("-Wno-visibility");
    try flags.append("-Wno-incompatible-pointer-types");

    if (target.os.tag == .windows) {
        try flags.append("-Wno-dll-attribute-on-redeclaration");
    }
}
