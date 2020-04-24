const std = @import("std");

const types = @import("./types.zig");
pub const typescript = @import("./typescript.zig");
pub const purescript = @import("./purescript.zig");

pub fn main() anyerror!void {
    const typescript_struct_output = typescript.typeToString(types.BasicStruct);
    std.debug.warn("{}\n", .{typescript_struct_output});

    const purescript_struct_output = purescript.typeToString(types.BasicStruct);
    std.debug.warn("{}\n", .{purescript_struct_output});
}
