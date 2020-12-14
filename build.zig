const std = @import("std");
const Builder = std.build.Builder;
const Mode = std.builtin.Mode;

const test_files = [_][]const u8{
    "typescript",
};

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});
    const exe = b.addExecutable("gotyno", "src/main.zig");
    exe.setBuildMode(mode);
    exe.setTarget(target);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    addTests(b, mode);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

fn addTests(b: *Builder, mode: Mode) void {
    const test_step = b.step("test", "Test the app");

    inline for (test_files) |f| {
        var tests = b.addTest("src/" ++ f ++ ".zig");
        tests.setBuildMode(mode);
        test_step.dependOn(&tests.step);
    }
}
