const std = @import("std");
const bu = @import("./build_utils.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .aarch64,
            .os_tag = .macos,
            .os_version_min = .{ .semver = .{ .major = 13, .minor = 0, .patch = 0 } },
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    const zig_lib_dir = b.option(
        []const u8,
        "zig_lib_dir",
        "Zig's \"lib\" directory, usually locates at $ZIG_EXE/../lib",
    ) orelse try bu.getZigLibDir(b.allocator);

    std.fs.cwd().access(zig_lib_dir, .{ .mode = .read_only }) catch |e| switch (e) {
        error.FileNotFound => {
            std.debug.print("zig_lib_dir does not exist at: {s}\n", .{zig_lib_dir});
            return e;
        },
        inline else => {
            std.debug.print("unexpected error\n", .{});
            return e;
        },
    };

    const cxx_cfg = bu.LibCxxBuildConfig{
        .target = target,
        .optimize = optimize,
        .pic = true,
        .linkage = .dynamic,
        .zig_lib_dir = zig_lib_dir,
        .any_non_single_threaded = true,
    };

    // Set the last 2 arguments to `true` to build both libc++abi and libunwind
    const cxx_deps = try bu.buildLibCxxAndOthers(b, cxx_cfg, true, false);

    // If you have additional flags to add, do this instead:
    var flags = try cxx_deps.dupeFlags(b.allocator);
    try flags.appendSlice(&.{ "-std=c++17", "-g" });

    const libbar_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .pic = true,
    });

    libbar_mod.addCSourceFiles(.{
        .root = b.path("libbar/src"),
        .files = &.{"Bar.cpp"},
        .flags = flags.list.items,
        .language = .cpp,
    });
    libbar_mod.addIncludePath(b.path("libbar/include"));
    cxx_deps.linkLibCxx(libbar_mod);

    const libbar = b.addLibrary(.{
        .name = "libbar",
        .root_module = libbar_mod,
        .linkage = .dynamic,
    });

    libbar.installHeadersDirectory(b.path("libbar/include"), "libbar", .{});

    const libfoo_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .pic = true,
    });

    libfoo_mod.addCSourceFiles(.{
        .root = b.path("libfoo/src"),
        .files = &.{"Foo.cpp"},
        .flags = flags.list.items,
        .language = .cpp,
    });
    libfoo_mod.addIncludePath(b.path("libfoo/include"));
    cxx_deps.linkLibCxx(libfoo_mod);

    const libfoo = b.addLibrary(.{
        .name = "libfoo",
        .root_module = libfoo_mod,
        .linkage = .dynamic,
    });

    libfoo.installHeadersDirectory(b.path("libfoo/include"), "libfoo", .{});

    const root_mod = b.addModule("main", .{
        .target = target,
        .optimize = optimize,
        .pic = true,
    });

    root_mod.addCSourceFiles(.{
        .root = b.path("./"),
        .files = &.{"main.cpp"},
        .flags = flags.list.items,
        .language = .cpp,
    });

    cxx_deps.linkLibCxx(root_mod);
    root_mod.linkLibrary(libbar);
    root_mod.linkLibrary(libfoo);

    const exe = b.addExecutable(.{ .name = "main", .root_module = root_mod, .linkage = .dynamic });
    exe.addIncludePath(b.path("include")); // Only include, not include/path

    b.installArtifact(libfoo);
    b.installArtifact(libbar);
    b.installArtifact(exe);

    // Create the run step
    const run_cmd = b.addRunArtifact(exe);

    // This allows the run step to inherit stdio, so you can see output
    run_cmd.step.dependOn(b.getInstallStep());

    // Forward command line arguments to the executable
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Create a named run step
    const run_step = b.step("run", "Run the main executable");
    run_step.dependOn(&run_cmd.step);
}
