const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const linkage = b.option(std.builtin.LinkMode, "linkage", "static or dynamic linkage") orelse .static;
    const foo = b.option(bool, "foo", "whether or not to include and build foo") orelse true;
    const bar = b.option(bool, "bar", "whether or not to include and build bar") orelse true;

    const libfoo = b.addLibrary(.{ .name = "libfoo", .linkage = linkage, .root_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
    }) });

    libfoo.addIncludePath(b.path("libfoo/include"));
    libfoo.addCSourceFile(.{
        .file = b.path("libfoo/src/Foo.C"),
        .flags = &.{
            "-std=c++17",
            "-g",
        },
    });
    libfoo.linkLibCpp();
    libfoo.installHeadersDirectory(b.path("libfoo/include"), "libfoo", .{});

    const libbar = b.addLibrary(.{ .name = "libfoo", .linkage = linkage, .root_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
    }) });

    libbar.addIncludePath(b.path("libbar/include"));
    libbar.addCSourceFile(.{
        .file = b.path("libbar/src/Bar.C"),
        .flags = &.{
            "-std=c++17",
            "-g",
        },
    });
    libbar.linkLibCpp();
    libbar.installHeadersDirectory(b.path("libbar/include"), "libbar", .{});

    const exe = b.addExecutable(.{ .name = "main", .root_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
    }) });

    if (foo) {
        exe.linkLibrary(libfoo);
        exe.root_module.addCMacro("FOO", "");
    }
    if (bar) {
        exe.linkLibrary(libbar);
        exe.root_module.addCMacro("BAR", "");
    }
    exe.addIncludePath(b.path("include")); // Only include, not include/path
    exe.addCSourceFile(.{
        .file = b.path("main.C"),
        .flags = &.{
            "-std=c++17",
            "-g",
        },
    });

    exe.linkLibCpp();
    b.installArtifact(libfoo);
    b.installArtifact(exe);
}
