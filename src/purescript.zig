const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const meta = std.meta;

const types = @import("./types.zig");

pub fn typeDeclarationToString(
    comptime t: var,
    comptime name: []const u8,
    comptime generic_parameters: u32,
) []const u8 {
    const type_of_t = @typeInfo(@TypeOf(t));

    return switch (type_of_t) {
        .Fn => genericToString(t, name, generic_parameters),
        .Type => typedefinitionToString(t),
        else => @compileLog(type_of_t),
    };
}

const T1 = struct {};
const T2 = struct {};
const T3 = struct {};
const T4 = struct {};
const T5 = struct {};
const T6 = struct {};

pub fn genericToString(
    comptime t: var,
    comptime name: []const u8,
    comptime generic_parameters: u8,
) []const u8 {
    return switch (generic_parameters) {
        0 => @compileError("not generic: 0 parameters"),
        1 => output: {
            const applied_type = t(T1);
            switch (@typeInfo(applied_type)) {
                .Struct => |d| {
                    const field1 = d.fields[0];
                    comptime var output: []const u8 = "newtype " ++
                        name ++ " a\n  = " ++ name ++ "\n  { " ++ field1.name ++ " ::" ++
                        purescriptifyType(field1.field_type, 0, 1) ++ "\n";
                    inline for (d.fields[1..]) |field, i| {
                        const field_output = purescriptifyType(field.field_type, 0, 1);
                        output = output ++ "  , " ++ field.name ++ " ::" ++ field_output ++ "\n";
                    }
                    output = output ++ "  }";

                    break :output output;
                },
                .Union => |d| {
                    const field1 = d.fields[0];
                    comptime const field1_output = purescriptifyType(field1.field_type, 0, 1);
                    comptime var type_output: []const u8 = "data " ++ name ++ " a\n  = " ++
                        field1.name ++ field1_output;
                    inline for (d.fields[1..]) |field| {
                        comptime const field_output = purescriptifyType(field.field_type, 0, 1);
                        type_output = type_output ++ "\n  | " ++ field.name ++
                            field_output;
                    }
                    break :output type_output;
                },
                else => @compileLog(t),
            }
        },
        2 => output: {
            const applied_type = t(T1, T2);
            switch (@typeInfo(applied_type)) {
                .Struct => |d| {
                    const field1 = d.fields[0];
                    comptime const field1_output = purescriptifyType(field1.field_type, 0, 1);
                    comptime var output: []const u8 = "newtype " ++
                        name ++ " a b\n  = " ++ name ++ "\n  { " ++ field1.name ++ " ::" ++
                        field1_output ++ "\n";
                    inline for (d.fields[1..]) |field, i| {
                        comptime const field_output = purescriptifyType(field.field_type, 0, 1);
                        output = output ++ "  , " ++ field.name ++ " ::" ++ field_output ++ "\n";
                    }
                    output = output ++ "  }";

                    break :output output;
                },
                .Union => |d| {
                    const field1 = d.fields[0];
                    comptime const field1_output = purescriptifyType(field1.field_type, 0, 1);
                    comptime var type_output: []const u8 = "data " ++ name ++ " a b\n  = " ++
                        field1.name ++ field1_output;
                    inline for (d.fields[1..]) |field| {
                        comptime const field_output = purescriptifyType(field.field_type, 0, 1);
                        type_output = type_output ++ "\n  | " ++ field.name ++
                            field_output;
                    }
                    break :output type_output;
                },
                else => @compileLog(t),
            }
        },
        3 => output: {
            const applied_type = t(T1, T2, T3);
            switch (@typeInfo(applied_type)) {
                .Struct => |d| {
                    const field1 = d.fields[0];
                    comptime const field1_output = purescriptifyType(field1.field_type, 0, 1);
                    comptime var output: []const u8 = "newtype " ++
                        name ++ " a b c\n  = " ++ name ++ "\n  { " ++ field1.name ++ " ::" ++
                        field1_output ++ "\n";
                    inline for (d.fields[1..]) |field, i| {
                        comptime const field_output = purescriptifyType(field.field_type, 0, 1);
                        output = output ++ "  , " ++ field.name ++ " ::" ++ field_output ++ "\n";
                    }
                    output = output ++ "  }";

                    break :output output;
                },
                .Union => |d| {
                    const field1 = d.fields[0];
                    comptime const field1_output = purescriptifyType(field1.field_type, 0, 1);
                    comptime var type_output: []const u8 = "data " ++ name ++ " a b c\n  = " ++
                        field1.name ++ field1_output;
                    inline for (d.fields[1..]) |field| {
                        comptime const field_output = purescriptifyType(field.field_type, 0, 1);
                        type_output = type_output ++ "\n  | " ++ field.name ++
                            field_output;
                    }
                    break :output type_output;
                },
                else => @compileLog(t),
            }
        },
        4 => output: {
            const applied_type = t(T1, T2, T3, T4);
            switch (@typeInfo(applied_type)) {
                .Struct => |d| {
                    const field1 = d.fields[0];
                    comptime const field1_output = purescriptifyType(field1.field_type, 0, 1);
                    comptime var output: []const u8 = "newtype " ++
                        name ++ " a b c d\n  = " ++ name ++ "\n  { " ++ field1.name ++ " ::" ++
                        field1_output ++ "\n";
                    inline for (d.fields[1..]) |field, i| {
                        comptime const field_output = purescriptifyType(field.field_type, 0, 1);
                        output = output ++ "  , " ++ field.name ++ " ::" ++ field_output ++ "\n";
                    }
                    output = output ++ "  }";

                    break :output output;
                },
                .Union => |d| {
                    const field1 = d.fields[0];
                    comptime const field1_output = purescriptifyType(field1.field_type, 0, 1);
                    comptime var type_output: []const u8 = "data " ++ name ++ " a b c d\n  = " ++
                        field1.name ++ field1_output;
                    inline for (d.fields[1..]) |field| {
                        comptime const field_output = purescriptifyType(field.field_type, 0, 1);
                        type_output = type_output ++ "\n  | " ++ field.name ++
                            field_output;
                    }
                    break :output type_output;
                },
                else => @compileLog(t),
            }
        },
        5 => output: {
            const applied_type = t(T1, T2, T3, T4, T5);
            switch (@typeInfo(applied_type)) {
                .Struct => |d| {
                    const field1 = d.fields[0];
                    comptime const field1_output = purescriptifyType(field1.field_type, 0, 1);
                    comptime var output: []const u8 = "newtype " ++
                        name ++ " a b c d e\n  = " ++ name ++ "\n  { " ++ field1.name ++ " ::" ++
                        field1_output ++ "\n";
                    inline for (d.fields[1..]) |field, i| {
                        comptime const field_output = purescriptifyType(field.field_type, 0, 1);
                        output = output ++ "  , " ++ field.name ++ " ::" ++ field_output ++ "\n";
                    }
                    output = output ++ "  }";

                    break :output output;
                },
                .Union => |d| {
                    const field1 = d.fields[0];
                    comptime const field1_output = purescriptifyType(field1.field_type, 0, 1);
                    comptime var type_output: []const u8 = "data " ++ name ++ " a b c d e\n  = " ++
                        field1.name ++ field1_output;
                    inline for (d.fields[1..]) |field| {
                        comptime const field_output = purescriptifyType(field.field_type, 0, 1);
                        type_output = type_output ++ "\n  | " ++ field.name ++
                            field_output;
                    }
                    break :output type_output;
                },
                else => @compileLog(t),
            }
        },
        6 => output: {
            const applied_type = t(T1, T2, T3, T4, T5, T6);
            switch (@typeInfo(applied_type)) {
                .Struct => |d| {
                    const field1 = d.fields[0];
                    comptime const field1_output = purescriptifyType(field1.field_type, 0, 1);
                    comptime var output: []const u8 = "newtype " ++
                        name ++ " a b c d e f\n  = " ++ name ++ "\n  { " ++ field1.name ++ " ::" ++
                        field1_output ++ "\n";
                    inline for (d.fields[1..]) |field, i| {
                        comptime const field_output = purescriptifyType(field.field_type, 0, 1);
                        output = output ++ "  , " ++ field.name ++ " ::" ++ field_output ++ "\n";
                    }
                    output = output ++ "  }";

                    break :output output;
                },
                .Union => |d| {
                    const field1 = d.fields[0];
                    comptime const field1_output = purescriptifyType(field1.field_type, 0, 1);
                    comptime var type_output: []const u8 = "data " ++ name ++ " a b c d e f\n  = " ++
                        field1.name ++ field1_output;
                    inline for (d.fields[1..]) |field| {
                        comptime const field_output = purescriptifyType(field.field_type, 0, 1);
                        type_output = type_output ++ "\n  | " ++ field.name ++
                            field_output;
                    }
                    break :output type_output;
                },
                else => @compileLog(t),
            }
        },
        else => @compileError("unsupported amount of generic parameters"),
    };
}

pub fn typedefinitionToString(comptime t: type) []const u8 {
    const type_info = @typeInfo(t);
    return switch (type_info) {
        .Struct => |d| output: {
            const type_name = @typeName(t);
            const field1 = d.fields[0];
            comptime var type_output: []const u8 = "newtype " ++
                type_name ++ "\n  = " ++ type_name ++ "\n  { " ++ field1.name ++ " ::" ++
                purescriptifyType(field1.field_type, 0, 1) ++ "\n";
            inline for (d.fields[1..]) |field, i| {
                type_output =
                    type_output ++
                    "  , " ++ field.name ++ " ::" ++ purescriptifyType(field.field_type, 0, 1) ++
                    "\n";
            }
            type_output = type_output ++ "  }";

            break :output type_output;
        },
        .Union => |d| output: {
            const name = @typeName(t);
            const field1 = d.fields[0];
            comptime var type_output: []const u8 = "data " ++ name ++ "\n  = " ++
                field1.name ++ purescriptifyType(field1.field_type, 1, 1);
            inline for (d.fields[1..]) |field| {
                type_output = type_output ++ "\n  | " ++ field.name ++
                    purescriptifyType(field.field_type, 1, 1);
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

fn purescriptifyType(
    comptime t: type,
    comptime nesting: u32,
    comptime spaces: u32,
) []const u8 {
    return switch (@typeInfo(t)) {
        .Int => [_]u8{' '} ** spaces ++ "Int",
        .Float => [_]u8{' '} ** spaces ++ "Number",
        .Bool => [_]u8{' '} ** spaces ++ "Boolean",
        .Pointer => |p| switch (p.child) {
            u8 => [_]u8{' '} ** spaces ++ "String",
            else => output: {
                const open = if (nesting > 0) "(" else "";
                const close = if (nesting > 0) ")" else "";
                break :output [_]u8{' '} ** spaces ++ open ++ "Array" ++
                    purescriptifyType(p.child, nesting + 1, 1) ++ close;
            },
        },
        .Struct => [_]u8{' '} ** spaces ++ structName(t),
        .Void => "",
        .Type => |d| [_]u8{' '} ** spaces ++ switch (d) {
            else => "wut",
        },
        else => |x| @compileLog(x),
    };
}

fn structName(comptime t: type) []const u8 {
    return switch (t) {
        T1 => "a",
        T2 => "b",
        T3 => "c",
        T4 => "d",
        T5 => "e",
        T6 => "f",
        else => @typeName(t),
    };
}

test "outputs basic newtype record type for zig struct" {
    const type_output = typeDeclarationToString(types.BasicStruct, "BasicStruct", 0);
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
    const type_output = typeDeclarationToString(types.BasicUnion, "BasicUnion", 0);
    const expected =
        \\data BasicUnion
        \\  = Struct BasicStruct
        \\  | Coordinates Point
        \\  | NoPayload
    ;
    testing.expectEqualSlices(u8, type_output, expected);
}

test "outputs basic newtype record for generic struct" {
    const type_output = typeDeclarationToString(types.GenericStruct, "GenericStruct", 2);
    const expected =
        \\newtype GenericStruct a b
        \\  = GenericStruct
        \\  { v1 :: a
        \\  , v2 :: b
        \\  , v3 :: a
        \\  , non_generic_value :: Int
        \\  }
    ;
    testing.expectEqualSlices(u8, type_output, expected);
}

test "outputs basic union type for Maybe" {
    const type_output = typeDeclarationToString(types.Maybe, "Maybe", 1);
    const expected =
        \\data Maybe a
        \\  = Nothing
        \\  | Just a
    ;
    testing.expectEqualSlices(u8, type_output, expected);
}

test "outputs basic union type for Either" {
    const type_output = typeDeclarationToString(types.Either, "Either", 2);
    const expected =
        \\data Either a b
        \\  = Left a
        \\  | Right b
    ;
    testing.expectEqualSlices(u8, type_output, expected);
}

test "outputs basic newtype record for structure generic over 3 parameters" {
    const type_output = typeDeclarationToString(types.GenericThree, "GenericThree", 3);
    const expected =
        \\newtype GenericThree a b c
        \\  = GenericThree
        \\  { v1 :: b
        \\  , v2 :: a
        \\  , v3 :: c
        \\  , v4 :: b
        \\  , v5 :: c
        \\  , v6 :: a
        \\  , dead_weight :: Boolean
        \\  }
    ;
    testing.expectEqualSlices(u8, type_output, expected);
}

test "outputs basic newtype record for structure generic over 4 parameters" {
    const type_output = typeDeclarationToString(types.GenericFour, "GenericFour", 4);
    const expected =
        \\newtype GenericFour a b c d
        \\  = GenericFour
        \\  { v1 :: b
        \\  , v2 :: a
        \\  , v3 :: c
        \\  , v4 :: b
        \\  , v5 :: c
        \\  , v6 :: d
        \\  , dead_weight :: Boolean
        \\  }
    ;
    testing.expectEqualSlices(u8, type_output, expected);
}

test "outputs basic newtype record for structure generic over 5 parameters" {
    const type_output = typeDeclarationToString(types.GenericFive, "GenericFive", 5);
    const expected =
        \\newtype GenericFive a b c d e
        \\  = GenericFive
        \\  { v1 :: b
        \\  , v2 :: a
        \\  , v3 :: c
        \\  , v4 :: b
        \\  , v5 :: e
        \\  , v6 :: d
        \\  , dead_weight :: Boolean
        \\  }
    ;
    testing.expectEqualSlices(u8, type_output, expected);
}

test "outputs basic newtype record for structure generic over 6 parameters" {
    const type_output = typeDeclarationToString(types.GenericSix, "GenericSix", 6);
    const expected =
        \\newtype GenericSix a b c d e f
        \\  = GenericSix
        \\  { v1 :: b
        \\  , v2 :: a
        \\  , v3 :: c
        \\  , v4 :: f
        \\  , v5 :: e
        \\  , v6 :: d
        \\  , dead_weight :: Boolean
        \\  }
    ;
    testing.expectEqualSlices(u8, type_output, expected);
}
