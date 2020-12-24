const std = @import("std");
const heap = std.heap;
const testing = std.testing;

pub const TestingAllocator = heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 20 });

pub fn testPanic(comptime format: []const u8, arguments: anytype) noreturn {
    std.debug.print(format, arguments);

    @panic("test failure");
}

pub fn expectNoLeaks(allocator: *TestingAllocator) void {
    testing.expect(!allocator.detectLeaks());
}
