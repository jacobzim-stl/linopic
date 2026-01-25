const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const raylib = b.dependency("raylib", .{ .target = target, .optimize = optimize }).artifact("raylib");

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
    linopic.linkLibrary(raylib);

    // Examples
    inline for (.{
        .{ "demo", "run", "Run demo" },
        .{ "editor", "editor", "Run editor" },
        .{ "synth", "run-synth", "Run synth" },
    }) |example| {
        const name, const step_name, const desc = example;
        const exe = addExample(b, name, target, optimize, linopic, raylib);
        const run = b.step(step_name, desc);
        run.dependOn(&b.addRunArtifact(exe).step);
    }

    // Tests
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = grid })).step);
}

fn addExample(
    b: *std.Build,
    comptime name: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    linopic: *std.Build.Module,
    raylib: *std.Build.Step.Compile,
) *std.Build.Step.Compile {
    const mod = b.createModule(.{
        .root_source_file = b.path("examples/" ++ name ++ ".zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "linopic", .module = linopic }},
    });
    mod.linkLibrary(raylib);
    const exe = b.addExecutable(.{ .name = name, .root_module = mod });
    b.installArtifact(exe);
    return exe;
}
