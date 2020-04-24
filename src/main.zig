const std = @import("std");
pub const typescript = @import("./typescript.zig");

pub fn main() anyerror!void {
    const basic_struct_output = typescript.typeToString(typescript.BasicStruct);
    std.debug.warn("{}\n", .{basic_struct_output});
}
