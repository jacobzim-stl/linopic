const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linopic = b.addModule("linopic", .{
        .root_source_file = b.path("src/linopic.zig"),
        .target = target,
        .optimize = optimize,
    });
    linopic.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
    linopic.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
    linopic.linkSystemLibrary("raylib", .{});

    const exe = b.addExecutable(.{
        .name = "example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "linopic", .module = linopic }},
        }),
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run example");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    const unit_tests = b.addTest(.{ .root_module = linopic });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
