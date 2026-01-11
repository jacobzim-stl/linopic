const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const grid = b.addModule("grid", .{
        .root_source_file = b.path("src/grid.zig"),
        .target = target,
        .optimize = optimize,
    });

    const linopic = b.addModule("linopic", .{
        .root_source_file = b.path("src/linopic.zig"),
        .target = target,
        .optimize = optimize,
    });
    linopic.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
    linopic.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
    linopic.linkSystemLibrary("raylib", .{});

    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "linopic", .module = linopic }},
    });
    exe_module.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
    exe_module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
    exe_module.linkSystemLibrary("raylib", .{});
    const exe = b.addExecutable(.{ .name = "example", .root_module = exe_module });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run example");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    const editor_module = b.createModule(.{
        .root_source_file = b.path("src/editor.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "linopic", .module = linopic }},
    });
    editor_module.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
    editor_module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
    editor_module.linkSystemLibrary("raylib", .{});
    const editor = b.addExecutable(.{ .name = "editor", .root_module = editor_module });
    b.installArtifact(editor);

    const editor_step = b.step("editor", "Run editor");
    const editor_cmd = b.addRunArtifact(editor);
    editor_step.dependOn(&editor_cmd.step);
    editor_cmd.step.dependOn(b.getInstallStep());

    const unit_tests = b.addTest(.{ .root_module = grid });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
