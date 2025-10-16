const std = @import("std");
const zcc = @import("compile_commands");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create a static library with include/path
    const lib = b.addLibrary(.{ .name = "foo", .linkage = .dynamic, .root_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
    }) });

    lib.addIncludePath(b.path("include"));
    lib.addCSourceFiles(.{
        .files = &.{"src/Foo.C"},
        .flags = &.{
            "-std=c++17",
            "-g",
            "-Wall",
            "-Wextra",
        },
    });
    lib.linkLibCpp();
    lib.installHeadersDirectory(b.path("include"), "libfoo", .{});
    b.installArtifact(lib);
}
