const std = @import("std");
const Builder = std.build.Builder;
const Mode = std.builtin.Mode;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "gotyno",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run tests");
    var tests = b.addTest(.{
        .root_source_file = .{ .path = "src/freeform.zig" },
        .target = target,
        .optimize = optimize,
    });
    test_step.dependOn(&tests.step);
}
