const std = @import("std");
const debug = std.debug;
const fmt = std.fmt;
const heap = std.heap;
const mem = std.mem;
const testing = std.testing;

const freeform = @import("./freeform.zig");
const type_examples = @import("./freeform/type_examples.zig");

const PlainStructure = freeform.parser.PlainStructure;
const GenericStructure = freeform.parser.GenericStructure;
const Field = freeform.parser.Field;
const ExpectError = freeform.tokenizer.ExpectError;

const TestingAllocator = heap.GeneralPurposeAllocator(.{});

pub fn outputPlainStructure(
    allocator: *mem.Allocator,
    plain_structure: PlainStructure,
) ![]const u8 {
    const name = plain_structure.name;

    const fields_output = try outputStructureFields(allocator, plain_structure.fields);

    const output_format =
        \\type {} = {c}
        \\{}
        \\{c};
    ;

    return try fmt.allocPrint(allocator, output_format, .{ name, '{', fields_output, '}' });
}

pub fn outputGenericStructure(
    allocator: *mem.Allocator,
    generic_structure: GenericStructure,
) ![]const u8 {
    const name = generic_structure.name;

    const fields_output = try outputStructureFields(allocator, generic_structure.fields);

    const output_format =
        \\type {}{} = {c}
        \\{}
        \\{c};
    ;

    return try fmt.allocPrint(
        allocator,
        output_format,
        .{ name, outputOpenNames(allocator, generic_structure.open_names), '{', fields_output, '}' },
    );
}

fn outputStructureFields(allocator: *mem.Allocator, fields: []Field) ![]const u8 {
    var fields_output: []const u8 = "";

    for (fields) |field, i| {
        const type_output = switch (field.@"type") {
            .empty => debug.panic("Empty is not a valid struct field type.\n", .{}),

            .string => |s| try fmt.allocPrint(allocator, "\"{}\"", .{s}),
            .name => |n| try fmt.allocPrint(allocator, "{}", .{translateName(n)}),

            .array => |a| output: {
                const embedded_type = switch (a.@"type".*) {
                    .name => |n| translateName(n),
                    .applied_name => |applied_name| try outputOpenNames(
                        allocator,
                        applied_name.open_names,
                    ),
                    else => debug.panic("Invalid embedded type for array: {}\n", .{a.@"type"}),
                };

                break :output try fmt.allocPrint(allocator, "{}[]", .{embedded_type});
            },

            .slice => |s| output: {
                const embedded_type = switch (s.@"type".*) {
                    .name => |n| translateName(n),
                    .applied_name => |applied_name| try outputOpenNames(
                        allocator,
                        applied_name.open_names,
                    ),
                    else => debug.panic("Invalid embedded type for slice: {}\n", .{s.@"type"}),
                };

                break :output try fmt.allocPrint(allocator, "{}[]", .{embedded_type});
            },

            .pointer => |p| output: {
                const embedded_type = switch (p.@"type".*) {
                    .name => |n| translateName(n),
                    .applied_name => |applied_name| try outputOpenNames(
                        allocator,
                        applied_name.open_names,
                    ),
                    else => debug.panic("Invalid embedded type for pointer: {}\n", .{p.@"type"}),
                };

                break :output try fmt.allocPrint(allocator, "{}", .{embedded_type});
            },

            .applied_name => |applied_name| {
                debug.panic("applied_name", .{});
            },
        };
        const line = if (i == (fields.len - 1))
            try fmt.allocPrint(allocator, "    {}: {};", .{ field.name, type_output })
        else
            try fmt.allocPrint(allocator, "    {}: {};\n", .{ field.name, type_output });

        fields_output = try mem.concat(allocator, u8, &[_][]const u8{ fields_output, line });
    }

    return fields_output;
}

fn outputOpenNames(allocator: *mem.Allocator, names: []const []const u8) ![]const u8 {
    var translated_names = try allocator.alloc([]const u8, names.len);

    for (names) |name, i| {
        translated_names[i] = translateName(name);
    }

    return try fmt.allocPrint(
        allocator,
        "<{}>",
        .{try mem.join(allocator, ", ", translated_names)},
    );
}

fn translateName(name: []const u8) []const u8 {
    return if (mem.eql(u8, name, "String"))
        "string"
    else if (isNumberType(name))
        "number"
    else if (mem.eql(u8, name, "Boolean"))
        "boolean"
    else
        name;
}

fn isNumberType(name: []const u8) bool {
    return isStringEqualToOneOf(name, &[_][]const u8{
        "U8",
        "U16",
        "U32",
        "U64",
        "U128",
        "I8",
        "I16",
        "I32",
        "I64",
        "I128",
        "F32",
        "F64",
        "F128",
    });
}

fn isStringEqualToOneOf(value: []const u8, compared_values: []const []const u8) bool {
    for (compared_values) |compared_value| {
        if (mem.eql(u8, value, compared_value)) return true;
    }

    return false;
}

test "Outputs `Person` struct correctly" {
    var allocator = TestingAllocator{};

    const expected_output =
        \\type Person = {
        \\    type: "Person";
        \\    name: string;
        \\    age: number;
        \\    efficiency: number;
        \\    on_vacation: boolean;
        \\    hobbies: string[];
        \\    last_fifteen_comments: string[];
        \\    recruiter: Person;
        \\};
    ;

    var expect_error: ExpectError = undefined;

    const output = try outputPlainStructure(
        &allocator.allocator,
        (try freeform.parser.parse(
            &allocator.allocator,
            &allocator.allocator,
            type_examples.person_structure,
            &expect_error,
        )).success.definitions[0].structure.plain,
    );

    testing.expectEqualStrings(output, expected_output);
}

test "Outputs `Node` struct correctly" {
    var allocator = TestingAllocator{};

    const expected_output =
        \\type Node<T> = {
        \\    type: "Node";
        \\    data: T;
        \\};
    ;

    var expect_error: ExpectError = undefined;

    const output = try outputGenericStructure(
        &allocator.allocator,
        (try freeform.parser.parse(
            &allocator.allocator,
            &allocator.allocator,
            type_examples.node_structure,
            &expect_error,
        )).success.definitions[0].structure.generic,
    );

    testing.expectEqualStrings(output, expected_output);
}
