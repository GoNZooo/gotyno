const std = @import("std");
const debug = std.debug;
const testing = std.testing;

const types = @import("./types.zig");

pub fn typedefinitionToString(comptime t: type) []const u8 {
    const type_info = @typeInfo(t);
    return switch (type_info) {
        .Struct => |d| output: {
            const type_name = @typeName(t);
            const field1 = d.fields[0];
            comptime var type_output: []const u8 = "newtype " ++
                type_name ++ "\n  = " ++ type_name ++ "\n  { " ++ field1.name ++ " :: " ++
                purescriptifyType(field1.field_type, 0) ++ "\n";
            inline for (d.fields[1..]) |field, i| {
                type_output =
                    type_output ++
                    "  , " ++ field.name ++ " :: " ++ purescriptifyType(field.field_type, 0) ++
                    "\n";
            }
            type_output = type_output ++ "  }";

            break :output type_output;
        },
        .Union => |d| output: {
            const name = @typeName(t);
            const field1 = d.fields[0];
            comptime var type_output: []const u8 = "data " ++ name ++ "\n  = " ++
                field1.name ++ " " ++ purescriptifyType(field1.field_type, 1);
            inline for (d.fields[1..]) |field| {
                type_output = type_output ++ "\n  | " ++ field.name ++ " " ++
                    purescriptifyType(field.field_type, 1);
            }
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

fn purescriptifyType(comptime t: type, comptime nesting: u32) []const u8 {
    return switch (@typeInfo(t)) {
        .Int => "Int",
        .Float => "Number",
        .Bool => "Boolean",
        .Pointer => |p| switch (p.child) {
            u8 => "String",
            else => output: {
                const open = if (nesting > 0) "(" else "";
                const close = if (nesting > 0) ")" else "";
                break :output open ++ "Array " ++ purescriptifyType(p.child, nesting + 1) ++ close;
            },
        },
        .Struct => @typeName(t),
        else => |x| @compileLog(x),
    };
}

test "outputs basic newtype record type for zig struct" {
    const type_output = typedefinitionToString(types.BasicStruct);
    const expected =
        \\newtype BasicStruct
        \\  = BasicStruct
        \\  { u :: Int
        \\  , i :: Int
        \\  , f :: Number
        \\  , s :: String
        \\  , bools :: Array Boolean
        \\  , hobbies :: Array String
        \\  , lotto_numbers :: Array (Array Int)
        \\  , points :: Array Point
        \\  }
    ;
    testing.expectEqualSlices(u8, type_output, expected);
}

test "outputs basic sum type for zig tagged union" {
    const type_output = typedefinitionToString(types.BasicUnion);
    const expected =
        \\data BasicUnion
        \\  = Struct BasicStruct
        \\  | Coordinates Point
    ;
    testing.expectEqualSlices(u8, type_output, expected);
}
