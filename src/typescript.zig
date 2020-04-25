const std = @import("std");
const debug = std.debug;
const testing = std.testing;

const types = @import("./types.zig");

pub fn typedefinitionToString(comptime t: type) []const u8 {
    const type_info = @typeInfo(t);
    return switch (type_info) {
        .Struct => |d| output: {
            const type_name = @typeName(t);
            comptime var type_output: []const u8 = "interface " ++ type_name ++ " {\n" ++
                "  type: \"" ++ type_name ++ "\";\n";
            inline for (d.fields) |field, i| {
                type_output =
                    type_output ++
                    "  " ++ field.name ++ ": " ++ typescriptifyType(field.field_type) ++
                    ";\n";
            }
            type_output = type_output ++ "}";

            break :output type_output;
        },
        .Type => |d| @compileError("unknown type"),
        .Void => |d| @compileError("unknown type"),
        .Bool => |d| @compileError("unknown type"),
        .Enum => |d| @compileError("unknown type"),
        .EnumLiteral => |d| @compileError("unknown type"),
        .Frame => |d| @compileError("unknown type"),
        .AnyFrame => |d| @compileError("unknown type"),
        .Vector => |d| @compileError("unknown type"),
        .Opaque => |d| @compileError("unknown type"),
        .Fn => |d| @compileError("unknown type"),
        .BoundFn => |d| @compileError("unknown type"),
        .ErrorSet => |d| @compileError("unknown type"),
        .ErrorUnion => |d| @compileError("unknown type"),
        .Union => |d| @compileError("unknown type"),
        .Optional => |d| @compileError("unknown type"),
        .Null => |d| @compileError("unknown type"),
        .Undefined => |d| @compileError("unknown type"),
        .ComptimeInt => |d| @compileError("unknown type"),
        .ComptimeFloat => |d| @compileError("unknown type"),
        .Float => |d| @compileError("unknown type"),
        .Int => |d| @compileError("unknown type"),
        .Pointer => |d| @compileError("unknown type"),
        .Array => |d| @compileError("unknown type"),
        .NoReturn => |d| @compileError("unknown type"),
    };
}

fn typescriptifyType(comptime t: type) []const u8 {
    return switch (@typeInfo(t)) {
        .Int, .Float => "number",
        .Bool => "boolean",
        .Pointer => |p| switch (p.child) {
            u8 => "string",
            else => "Array<" ++ typescriptifyType(p.child) ++ ">",
        },
        .Struct => @typeName(t),
        else => |x| @compileLog(x),
    };
}

test "outputs basic interface type for zig struct" {
    const type_output = typedefinitionToString(types.BasicStruct);
    const expected =
        \\interface BasicStruct {
        \\  type: "BasicStruct";
        \\  u: number;
        \\  i: number;
        \\  f: number;
        \\  s: string;
        \\  bools: Array<boolean>;
        \\  hobbies: Array<string>;
        \\  lotto_numbers: Array<Array<number>>;
        \\  points: Array<Point>;
        \\}
    ;
    testing.expectEqualSlices(u8, type_output, expected);
}
