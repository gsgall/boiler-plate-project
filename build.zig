const std = @import("std");
const zcc = @import("compile_commands");

//pub fn build(b: *std.Build) void {
//    const target = b.standardTargetOptions(.{});
//    const optimize = b.standardOptimizeOption(.{});
// const exe = b.addExecutable(.{ .name = "main", .root_module = b.createModule(.{
//        .target = target,
//        .optimize = optimize,
//    }) });
//    // Add all C++ source files
//    exe.addCSourceFiles(.{
//        .files = &.{
//            "main.C",
//            "src/File1.C",
//        },
//        .flags = &.{ "-std=c++17", "-Wall", "-Wextra", "-gen-cdb-fragment-path", ".cache/cdb" },
//    });
//
//    // Add include directory
//    exe.addIncludePath(b.path("include"));
//    exe.addIncludePath(b.path("include/boiler-plate-project"));
//    // Link C++ standard library
//    exe.linkLibCpp();
//    // Install the executable
//    b.installArtifact(exe);
//    var targets = std.ArrayListUnmanaged(*std.Build.Step.Compile){};
//    targets.append(b.allocator, exe) catch @panic("OOM");
//    _ = zcc.createStep(b, "cdb", targets.toOwnedSlice(b.allocator) catch @panic("OOM"));
//}

//pub fn build(b: *std.Build) void {
//    const target = b.standardTargetOptions(.{});
//    const optimize = b.standardOptimizeOption(.{});
//    const lib = b.addLibrary(.{ .name = "test", .linkage = .dynamic, .root_module = b.createModule(.{
//        .target = target,
//        .optimize = optimize,
//    }) });
//
//    lib.addCSourceFiles(.{
//        .files = &.{"src/File1.C"},
//        .flags = &.{ "-std=c++17", "-Wall", "-Wextra" },
//    });
//
//    lib.addIncludePath(b.path("include/boiler-plate-project"));
//
//    lib.linkLibCpp();
//    lib.installHeadersDirectory(b.path("include"), "", .{});
//
//    b.installArtifact(lib);
//}

//pub fn build(b: *std.Build) void {
//    const target = b.standardTargetOptions(.{});
//    const optimize = b.standardOptimizeOption(.{});
//
//    const exe = b.addExecutable(.{ .name = "main", .root_module = b.createModule(.{
//        .target = target,
//        .optimize = optimize,
//    }) });
//    // Add all C++ source files
//    exe.addCSourceFiles(.{
//        .files = &.{
//            "main.C",
//        },
//        .flags = &.{ "-std=c++17", "-Wall", "-Wextra" },
//    });
//
//    exe.addLibraryPath(b.path("zig-out/lib"));
//    exe.linkSystemLibrary("test");
//
//    exe.addIncludePath(b.path("zig-out/include"));
//    exe.linkLibCpp();
//
//    b.installArtifact(exe);
//    var targets = std.ArrayListUnmanaged(*std.Build.Step.Compile){};
//    targets.append(b.allocator, exe) catch @panic("OOM");
//    _ = zcc.createStep(b, "cdb", targets.toOwnedSlice(b.allocator) catch @panic("OOM"));
//}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{ .name = "main", .root_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
    }) });

    // Collect all C source files
    var src_dir = try std.fs.cwd().openDir("src", .{ .iterate = true });
    defer src_dir.close();

    var c_files = std.ArrayList([]const u8){};
    defer c_files.deinit(b.allocator);

    var iter = src_dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".C")) {
            const path = try std.fs.path.join(b.allocator, &.{ "src", entry.name });
            try c_files.append(b.allocator, path);
        }
    }
    try c_files.append(b.allocator, "main.C");
    // Add all C++ source files
    exe.addCSourceFiles(.{
        .files = c_files.items,
        .flags = &.{
            "-std=c++17",
            "-g",
            "-Wall",
            "-Wextra",
        },
    });

    // Add include directory
    exe.addIncludePath(b.path("include"));
    exe.addIncludePath(b.path("include/boiler-plate-project"));
    // Link C++ standard library
    exe.linkLibCpp();
    // Install the executable

    const install_exe = b.addInstallArtifact(exe, .{ .dest_dir = .{ .override = .prefix } });

    b.getInstallStep().dependOn(&install_exe.step);
    var targets = std.ArrayListUnmanaged(*std.Build.Step.Compile){};
    targets.append(b.allocator, exe) catch @panic("OOM");
    _ = zcc.createStep(b, "cdb", targets.toOwnedSlice(b.allocator) catch @panic("OOM"));
}
