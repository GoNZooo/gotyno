const std = @import("std");

const types = @import("./types.zig");
pub const typescript = @import("./typescript.zig");
pub const purescript = @import("./purescript.zig");
pub const haskell = @import("./haskell.zig");

pub fn main() anyerror!void {
    const typescript_struct_output = typescript.typedefinitionToString(types.BasicStruct);
    const typescript_union_output = typescript.typedefinitionToString(types.BasicUnion);
    std.debug.warn(
        "TypeScript:\n{}\n{}\n",
        .{ typescript_struct_output, typescript_union_output },
    );

    const purescript_struct_output = purescript.typedefinitionToString(types.BasicStruct);
    const purescript_union_output = purescript.typedefinitionToString(types.BasicUnion);
    std.debug.warn(
        "\nPureScript:\n{}\n{}\n",
        .{ purescript_struct_output, purescript_union_output },
    );

    const haskell_struct_output = haskell.typedefinitionToString(types.BasicStruct);
    const haskell_union_output = haskell.typedefinitionToString(types.BasicUnion);
    std.debug.warn(
        "\nHaskell:\n{}\n{}\n",
        .{ haskell_struct_output, haskell_union_output },
    );
}
