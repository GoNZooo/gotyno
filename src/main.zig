const std = @import("std");

const typescript = @import("./typescript.zig");

pub fn main() anyerror!void {
    std.debug.print("Main output\n", .{});
}
