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
        .file = b.path("libfoo/src/Foo.cpp"),
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
        .file = b.path("libbar/src/Bar.cpp"),
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

    if (bar) {
        exe.root_module.addCMacro("BAR", "");
        exe.linkLibrary(libbar);
    }
    if (foo) {
        exe.root_module.addCMacro("FOO", "");
        exe.linkLibrary(libfoo);
    }
    exe.addIncludePath(b.path("include")); // Only include, not include/path
    exe.addCSourceFile(.{
        .file = b.path("main.cpp"),
        .flags = &.{
            "-std=c++17",
            "-g",
        },
    });

    exe.linkLibCpp();
    b.installArtifact(libfoo);
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
