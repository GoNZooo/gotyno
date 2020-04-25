const std = @import("std");

const types = @import("./types.zig");
pub const typescript = @import("./typescript.zig");
pub const purescript = @import("./purescript.zig");
pub const haskell = @import("./haskell.zig");

pub fn main() anyerror!void {
    const typescript_struct_output = typescript.typedefinitionToString(types.BasicStruct);
    std.debug.warn("TypeScript:\n{}\n", .{typescript_struct_output});

    const purescript_struct_output = purescript.typedefinitionToString(types.BasicStruct);
    std.debug.warn("\nPureScript:\n{}\n", .{purescript_struct_output});

    const haskell_struct_output = haskell.typedefinitionToString(types.BasicStruct);
    std.debug.warn("\nHaskell:\n{}\n", .{haskell_struct_output});
}
