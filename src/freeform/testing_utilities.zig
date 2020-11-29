const std = @import("std");

pub fn testPanic(comptime format: []const u8, arguments: anytype) noreturn {
    std.debug.print(format, arguments);

    @panic("test failure");
}
