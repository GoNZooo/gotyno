const std = @import("std");
pub const typescript = @import("./typescript/dump.zig");

pub fn main() anyerror!void {
    _ = typescript.typeToString(typescript.BasicStruct);
    std.debug.warn("All your base are belong to us.\n", .{});
}
