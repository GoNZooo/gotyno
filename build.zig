const std = @import("std");
const Builder = std.build.Builder;
const Mode = std.builtin.Mode;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});
    const exe = b.addExecutable("gotyno", "src/main.zig");
    exe.setBuildMode(mode);
    exe.setTarget(target);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run tests");
    var tests = b.addTest("src/freeform.zig");
    tests.setBuildMode(mode);
    test_step.dependOn(&tests.step);
}
