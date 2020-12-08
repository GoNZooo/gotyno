const std = @import("std");
const debug = std.debug;
const fmt = std.fmt;
const heap = std.heap;
const mem = std.mem;
const testing = std.testing;

const ArrayList = std.ArrayList;

const parser = @import("./freeform/parser.zig");
const tokenizer = @import("./freeform/tokenizer.zig");
const type_examples = @import("./freeform/type_examples.zig");

const Definition = parser.Definition;
const PlainStructure = parser.PlainStructure;
const GenericStructure = parser.GenericStructure;
const PlainUnion = parser.PlainUnion;
const GenericUnion = parser.GenericUnion;
const Constructor = parser.Constructor;
const Type = parser.Type;
const Field = parser.Field;
const ExpectError = tokenizer.ExpectError;

const TestingAllocator = heap.GeneralPurposeAllocator(.{});

pub fn outputFilename(allocator: *mem.Allocator, filename: []const u8) ![]const u8 {
    debug.assert(mem.endsWith(u8, filename, ".gotyno"));

    var split_iterator = mem.split(filename, ".gotyno");
    const before_extension = split_iterator.next().?;

    return mem.join(allocator, "", &[_][]const u8{ before_extension, ".ts" });
}

pub fn compileDefinitions(allocator: *mem.Allocator, definitions: []Definition) ![]const u8 {
    var outputs = ArrayList([]const u8).init(allocator);
    defer outputs.deinit();

    try outputs.append("import * as svt from \"simple-validation-tools\";");

    for (definitions) |definition| {
        const output = switch (definition) {
            .structure => |structure| switch (structure) {
                .plain => |plain| try outputPlainStructure(allocator, plain),
                .generic => |generic| try outputGenericStructure(allocator, generic),
            },
            .@"union" => |u| switch (u) {
                .plain => |plain| try outputPlainUnion(allocator, plain),
                .generic => |generic| try outputGenericUnion(allocator, generic),
            },
        };

        try outputs.append(output);
    }

    return try mem.join(allocator, "\n\n", outputs.items);
}

fn outputPlainStructure(
    allocator: *mem.Allocator,
    plain_structure: PlainStructure,
) ![]const u8 {
    const name = plain_structure.name;

    const fields_output = try outputStructureFields(allocator, plain_structure.fields);

    const type_guards_output = try outputTypeGuardForPlainStructure(allocator, plain_structure);

    const validator_output = try outputValidatorForPlainStructure(allocator, plain_structure);

    const output_format =
        \\export type {} = {c}
        \\    type: "{}";
        \\{}
        \\{c};
        \\
        \\{}
        \\
        \\{}
    ;

    return try fmt.allocPrint(
        allocator,
        output_format,
        .{ name, '{', name, fields_output, '}', type_guards_output, validator_output },
    );
}

fn outputGenericStructure(
    allocator: *mem.Allocator,
    generic_structure: GenericStructure,
) ![]const u8 {
    const name = generic_structure.name;

    const fields_output = try outputStructureFields(allocator, generic_structure.fields);

    const output_format =
        \\export type {}{} = {c}
        \\    type: "{}";
        \\{}
        \\{c};
    ;

    return try fmt.allocPrint(
        allocator,
        output_format,
        .{
            name,
            outputOpenNames(allocator, generic_structure.open_names),
            '{',
            name,
            fields_output,
            '}',
        },
    );
}

fn outputStructureFields(allocator: *mem.Allocator, fields: []Field) ![]const u8 {
    var fields_output: []const u8 = "";

    for (fields) |field, i| {
        const type_output = if (try outputType(allocator, field.@"type")) |output|
            output
        else
            debug.panic("Empty type is not valid for struct field\n", .{});

        const line = if (i == (fields.len - 1))
            try fmt.allocPrint(allocator, "    {}: {};", .{ field.name, type_output })
        else
            try fmt.allocPrint(allocator, "    {}: {};\n", .{ field.name, type_output });

        fields_output = try mem.concat(allocator, u8, &[_][]const u8{ fields_output, line });
    }

    return fields_output;
}

fn outputPlainUnion(allocator: *mem.Allocator, plain_union: PlainUnion) ![]const u8 {
    var constructor_names = try allocator.alloc([]const u8, plain_union.constructors.len);
    defer allocator.free(constructor_names);
    for (plain_union.constructors) |constructor, i| {
        constructor_names[i] = constructor.tag;
    }

    const constructor_names_output = try mem.join(allocator, " | ", constructor_names);

    const tagged_structures_output = try outputTaggedStructures(
        allocator,
        plain_union.constructors,
    );

    const type_guards_output = try outputTypeGuardsForConstructors(
        allocator,
        plain_union.constructors,
    );

    const validators_output = try outputValidatorsForConstructors(
        allocator,
        plain_union.constructors,
    );

    const output_format =
        \\export type {} = {};
        \\
        \\{}
        \\
        \\{}
        \\
        \\{}
    ;

    return fmt.allocPrint(
        allocator,
        output_format,
        .{
            plain_union.name,
            constructor_names_output,
            tagged_structures_output,
            type_guards_output,
            validators_output,
        },
    );
}

fn outputGenericUnion(allocator: *mem.Allocator, generic_union: GenericUnion) ![]const u8 {
    const open_names = try outputOpenNames(allocator, generic_union.open_names);

    var constructor_names = try allocator.alloc([]const u8, generic_union.constructors.len);
    for (generic_union.constructors) |constructor, i| {
        const maybe_names = try getOpenNamesFromType(
            allocator,
            constructor.parameter,
            generic_union.open_names,
        );

        constructor_names[i] = try fmt.allocPrint(
            allocator,
            "{}{}",
            .{ constructor.tag, maybe_names },
        );
    }
    const constructor_names_output = try mem.join(allocator, " | ", constructor_names);

    const tagged_structures_output = try outputTaggedMaybeGenericStructures(
        allocator,
        generic_union.constructors,
        generic_union.open_names,
    );

    const output_format =
        \\export type {}{} = {};
        \\
        \\{}
    ;

    return fmt.allocPrint(
        allocator,
        output_format,
        .{ generic_union.name, open_names, constructor_names_output, tagged_structures_output },
    );
}

fn outputTypeGuardForPlainStructure(
    allocator: *mem.Allocator,
    plain_structure: PlainStructure,
) ![]const u8 {
    const name = plain_structure.name;

    const checkers_output = try getTypeGuardsFromFields(allocator, name, plain_structure.fields);

    const output_format =
        \\export const is{} = (value: unknown): value is {} => {c}
        \\    return svt.isInterface<{}>(value, {c}{}{c});
        \\{c};
    ;

    return try fmt.allocPrint(
        allocator,
        output_format,
        .{ name, name, '{', name, '{', checkers_output, '}', '}' },
    );
}

fn outputValidatorForPlainStructure(
    allocator: *mem.Allocator,
    plain_structure: PlainStructure,
) ![]const u8 {
    const name = plain_structure.name;

    const validators_output = try getValidatorsFromFields(allocator, name, plain_structure.fields);

    const output_format =
        \\export const validate{} = (value: unknown): svt.ValidationResult<{}> => {c}
        \\    return svt.validate<{}>(value, {c}{}{c});
        \\{c};
    ;

    return try fmt.allocPrint(
        allocator,
        output_format,
        .{ name, name, '{', name, '{', validators_output, '}', '}' },
    );
}

fn getTypeGuardsFromFields(allocator: *mem.Allocator, name: []const u8, fields: []Field) ![]const u8 {
    var fields_outputs = ArrayList([]const u8).init(allocator);
    defer fields_outputs.deinit();

    try fields_outputs.append(try fmt.allocPrint(allocator, "type: \"{}\"", .{name}));

    for (fields) |field| {
        if (try getTypeGuardFromType(allocator, field.@"type")) |type_guard| {
            const output = try fmt.allocPrint(allocator, "{}: {}", .{ field.name, type_guard });
            try fields_outputs.append(output);
        }
    }

    return try mem.join(allocator, ", ", fields_outputs.items);
}

fn getValidatorsFromFields(allocator: *mem.Allocator, name: []const u8, fields: []Field) ![]const u8 {
    var fields_outputs = ArrayList([]const u8).init(allocator);
    defer fields_outputs.deinit();

    try fields_outputs.append(try fmt.allocPrint(allocator, "type: \"{}\"", .{name}));

    for (fields) |field| {
        if (try getValidatorFromType(allocator, field.@"type")) |validator| {
            const output = try fmt.allocPrint(allocator, "{}: {}", .{ field.name, validator });
            try fields_outputs.append(output);
        }
    }

    return try mem.join(allocator, ", ", fields_outputs.items);
}

fn getTypeGuardFromType(allocator: *mem.Allocator, t: Type) !?[]const u8 {
    const array_format = "svt.arrayOf({})";

    return switch (t) {
        .string => |s| try fmt.allocPrint(allocator, "\"{}\"", .{s}),
        .name => |n| try fmt.allocPrint(
            allocator,
            "{}",
            .{try translatedTypeGuardName(allocator, n)},
        ),
        .array => |a| try fmt.allocPrint(
            allocator,
            array_format,
            .{try getNestedTypeGuardFromType(allocator, a.@"type".*)},
        ),
        .slice => |s| try fmt.allocPrint(
            allocator,
            array_format,
            .{try getNestedTypeGuardFromType(allocator, s.@"type".*)},
        ),
        .pointer => |p| try getNestedTypeGuardFromType(allocator, p.@"type".*),

        .empty => debug.panic("Empty type does not seem like it should have a type guard\n", .{}),
        .applied_name => null,
    };
}

fn getValidatorFromType(allocator: *mem.Allocator, t: Type) !?[]const u8 {
    const array_format = "svt.validateArray({})";

    return switch (t) {
        .string => |s| try fmt.allocPrint(allocator, "\"{}\"", .{s}),
        .name => |n| try fmt.allocPrint(
            allocator,
            "{}",
            .{try translatedValidatorName(allocator, n)},
        ),
        .array => |a| try fmt.allocPrint(
            allocator,
            array_format,
            .{try getNestedValidatorFromType(allocator, a.@"type".*)},
        ),
        .slice => |s| try fmt.allocPrint(
            allocator,
            array_format,
            .{try getNestedValidatorFromType(allocator, s.@"type".*)},
        ),
        .pointer => |p| try getNestedValidatorFromType(allocator, p.@"type".*),

        .empty => debug.panic("Empty type does not seem like it should have a type guard\n", .{}),
        .applied_name => null,
    };
}

fn outputTypeGuardsForConstructors(
    allocator: *mem.Allocator,
    constructors: []Constructor,
) ![]const u8 {
    var type_guards = ArrayList([]const u8).init(allocator);
    defer type_guards.deinit();

    for (constructors) |constructor| {
        try type_guards.append(try outputTypeGuardForConstructor(allocator, constructor));
    }

    return try mem.join(allocator, "\n\n", type_guards.items);
}

fn outputValidatorsForConstructors(
    allocator: *mem.Allocator,
    constructors: []Constructor,
) ![]const u8 {
    var validators = ArrayList([]const u8).init(allocator);
    defer validators.deinit();

    for (constructors) |constructor| {
        try validators.append(try outputValidatorForConstructor(allocator, constructor));
    }

    return try mem.join(allocator, "\n\n", validators.items);
}

fn outputTypeGuardForConstructor(allocator: *mem.Allocator, constructor: Constructor) ![]const u8 {
    const tag = constructor.tag;

    const output_format =
        \\export const is{} = (value: unknown): value is {} => {c}
        \\    return svt.isInterface<{}>(value, {c}type: "{}"{}{c});
        \\{c};
    ;

    const type_guard_output = try getDataTypeGuardFromType(allocator, constructor.parameter);

    return try fmt.allocPrint(
        allocator,
        output_format,
        .{ tag, tag, '{', tag, '{', tag, type_guard_output, '}', '}' },
    );
}

fn outputValidatorForConstructor(allocator: *mem.Allocator, constructor: Constructor) ![]const u8 {
    const tag = constructor.tag;

    const output_format =
        \\export const validate{} = (value: unknown): svt.ValidationResult<{}> => {c}
        \\    return svt.validate<{}>(value, {c}type: "{}"{}{c});
        \\{c};
    ;

    const validator_output = try getDataValidatorFromType(allocator, constructor.parameter);

    return try fmt.allocPrint(
        allocator,
        output_format,
        .{ tag, tag, '{', tag, '{', tag, validator_output, '}', '}' },
    );
}

fn getDataTypeGuardFromType(allocator: *mem.Allocator, t: Type) ![]const u8 {
    const bare_format = ", data: {}";
    const type_guard_format = ", data: {}";
    const builtin_type_guard_format = ", data: svt.is{}";
    const array_format = ", data: svt.arrayOf({})";

    return switch (t) {
        .empty => "",
        .string => |s| try fmt.allocPrint(allocator, bare_format, .{s}),
        .name => |n| try fmt.allocPrint(
            allocator,
            type_guard_format,
            .{try translatedTypeGuardName(allocator, n)},
        ),
        .array => |a| try fmt.allocPrint(
            allocator,
            array_format,
            .{try getNestedTypeGuardFromType(allocator, a.@"type".*)},
        ),
        .slice => |s| try fmt.allocPrint(
            allocator,
            array_format,
            .{try getNestedTypeGuardFromType(allocator, s.@"type".*)},
        ),
        .pointer => |p| try fmt.allocPrint(
            allocator,
            type_guard_format,
            .{try getNestedTypeGuardFromType(allocator, p.@"type".*)},
        ),
        .applied_name => debug.panic("Trying to get type guard from type for: {}\n", .{t}),
    };
}

fn getDataValidatorFromType(allocator: *mem.Allocator, t: Type) ![]const u8 {
    const bare_format = ", data: {}";
    const validator_format = ", data: {}";
    const builtin_type_guard_format = ", data: svt.validate{}";
    const array_format = ", data: svt.validateArray({})";

    return switch (t) {
        .empty => "",
        .string => |s| try fmt.allocPrint(allocator, bare_format, .{s}),
        .name => |n| try fmt.allocPrint(
            allocator,
            validator_format,
            .{try translatedValidatorName(allocator, n)},
        ),
        .array => |a| try fmt.allocPrint(
            allocator,
            array_format,
            .{try getNestedValidatorFromType(allocator, a.@"type".*)},
        ),
        .slice => |s| try fmt.allocPrint(
            allocator,
            array_format,
            .{try getNestedValidatorFromType(allocator, s.@"type".*)},
        ),
        .pointer => |p| try fmt.allocPrint(
            allocator,
            validator_format,
            .{try getNestedValidatorFromType(allocator, p.@"type".*)},
        ),
        .applied_name => debug.panic("Trying to get validator from type for: {}\n", .{t}),
    };
}

fn getNestedTypeGuardFromType(allocator: *mem.Allocator, t: Type) error{OutOfMemory}![]const u8 {
    const array_format = "svt.arrayOf({})";

    return switch (t) {
        .empty => debug.panic("Empty nested type invalid for type guard\n", .{}),
        .string => |s| try fmt.allocPrint(allocator, "\"{}\"", .{s}),
        .name => |n| try fmt.allocPrint(
            allocator,
            "{}",
            .{try translatedTypeGuardName(allocator, n)},
        ),
        .array => |a| try fmt.allocPrint(
            allocator,
            array_format,
            .{try getNestedTypeGuardFromType(allocator, a.@"type".*)},
        ),
        .slice => |s| try fmt.allocPrint(
            allocator,
            array_format,
            .{try getNestedTypeGuardFromType(allocator, s.@"type".*)},
        ),
        .pointer => |p| try fmt.allocPrint(
            allocator,
            "is{}",
            .{try getNestedTypeGuardFromType(allocator, p.@"type".*)},
        ),
        .applied_name => debug.panic("Trying to get type guard from type for: {}\n", .{t}),
    };
}

fn getNestedValidatorFromType(allocator: *mem.Allocator, t: Type) error{OutOfMemory}![]const u8 {
    const array_format = "svt.validateArray({})";

    return switch (t) {
        .empty => debug.panic("Empty nested type invalid for validator\n", .{}),
        .string => |s| try fmt.allocPrint(allocator, "\"{}\"", .{s}),
        .name => |n| try fmt.allocPrint(
            allocator,
            "{}",
            .{try translatedValidatorName(allocator, n)},
        ),
        .array => |a| try fmt.allocPrint(
            allocator,
            array_format,
            .{try getNestedValidatorFromType(allocator, a.@"type".*)},
        ),
        .slice => |s| try fmt.allocPrint(
            allocator,
            array_format,
            .{try getNestedValidatorFromType(allocator, s.@"type".*)},
        ),
        .pointer => |p| try fmt.allocPrint(
            allocator,
            "is{}",
            .{try getNestedValidatorFromType(allocator, p.@"type".*)},
        ),
        .applied_name => debug.panic("Trying to get type guard from type for: {}\n", .{t}),
    };
}

fn outputCommonOpenNames(
    allocator: *mem.Allocator,
    as: []const []const u8,
    bs: []const []const u8,
) ![]const u8 {
    var common_names = ArrayList([]const u8).init(allocator);
    defer common_names.deinit();

    for (as) |a| {
        for (bs) |b| {
            if (mem.eql(u8, a, b) and !isTranslatedName(a)) try common_names.append(a);
        }
    }

    return if (common_names.items.len == 0) "" else try fmt.allocPrint(
        allocator,
        "<{}>",
        .{try mem.join(allocator, ", ", common_names.items)},
    );
}

fn outputTaggedStructures(allocator: *mem.Allocator, constructors: []Constructor) ![]const u8 {
    var tagged_structures_outputs = ArrayList([]const u8).init(allocator);
    defer tagged_structures_outputs.deinit();

    for (constructors) |constructor| {
        try tagged_structures_outputs.append(try outputTaggedStructure(allocator, constructor));
    }

    return try mem.join(allocator, "\n\n", tagged_structures_outputs.items);
}

fn outputTaggedMaybeGenericStructures(
    allocator: *mem.Allocator,
    constructors: []Constructor,
    open_names: []const []const u8,
) ![]const u8 {
    var tagged_structures_outputs = ArrayList([]const u8).init(allocator);
    defer tagged_structures_outputs.deinit();

    for (constructors) |constructor| {
        try tagged_structures_outputs.append(
            try outputTaggedMaybeGenericStructure(allocator, constructor, open_names),
        );
    }

    return try mem.join(allocator, "\n\n", tagged_structures_outputs.items);
}

fn outputTaggedStructure(allocator: *mem.Allocator, constructor: Constructor) ![]const u8 {
    const parameter_output = if (try outputType(allocator, constructor.parameter)) |output|
        output
    else
        "null";

    const output_format =
        \\export type {} = {c}
        \\    type: "{}";
        \\    data: {};
        \\{c};
    ;

    return fmt.allocPrint(
        allocator,
        output_format,
        .{ constructor.tag, '{', constructor.tag, parameter_output, '}' },
    );
}

fn outputTaggedMaybeGenericStructure(
    allocator: *mem.Allocator,
    constructor: Constructor,
    open_names: []const []const u8,
) ![]const u8 {
    const open_names_output = getOpenNamesFromType(allocator, constructor.parameter, open_names);

    const parameter_output = if (try outputType(allocator, constructor.parameter)) |output|
        try fmt.allocPrint(allocator, "\n    data: {};", .{output})
    else
        "";

    const output_format =
        \\export type {}{} = {c}
        \\    type: "{}";{}
        \\{c};
    ;

    return fmt.allocPrint(
        allocator,
        output_format,
        .{ constructor.tag, open_names_output, '{', constructor.tag, parameter_output, '}' },
    );
}

fn getOpenNamesFromType(
    allocator: *mem.Allocator,
    t: Type,
    open_names: []const []const u8,
) error{OutOfMemory}![]const u8 {
    return switch (t) {
        .pointer => |pointer| try getOpenNamesFromType(allocator, pointer.@"type".*, open_names),
        .array => |a| try getOpenNamesFromType(allocator, a.@"type".*, open_names),
        .slice => |s| try getOpenNamesFromType(allocator, s.@"type".*, open_names),

        // We need to check whether or not we have one of the generic names in the structure here
        // and if we do, add it as a type parameter to the tagged structure.
        // It's possible that the name is actually a concrete type and so it shouldn't show up as
        // a type parameter for the tagged structure.
        .applied_name => |applied_name| try outputCommonOpenNames(
            allocator,
            open_names,
            applied_name.open_names,
        ),

        .name => |n| if (isStringEqualToOneOf(n, open_names))
            try fmt.allocPrint(allocator, "<{}>", .{n})
        else
            "",

        .empty, .string => "",
    };
}

fn outputType(allocator: *mem.Allocator, t: Type) !?[]const u8 {
    return switch (t) {
        .empty => null,
        .string => |s| try fmt.allocPrint(allocator, "\"{}\"", .{s}),
        .name => |n| translateName(n),

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
                .applied_name => |applied_name| embedded_type: {
                    const open_names = try outputOpenNames(
                        allocator,
                        applied_name.open_names,
                    );

                    break :embedded_type try fmt.allocPrint(
                        allocator,
                        "{}{}",
                        .{ applied_name.name, open_names },
                    );
                },
                else => debug.panic("Invalid embedded type for pointer: {}\n", .{p.@"type"}),
            };

            break :output try fmt.allocPrint(allocator, "{}", .{embedded_type});
        },

        .applied_name => |applied_name| try fmt.allocPrint(
            allocator,
            "{}{}",
            .{ applied_name.name, try outputOpenNames(allocator, applied_name.open_names) },
        ),
    };
}

fn outputOpenNames(allocator: *mem.Allocator, names: []const []const u8) ![]const u8 {
    var translated_names = ArrayList([]const u8).init(allocator);
    defer translated_names.deinit();

    for (names) |name| try translated_names.append(translateName(name));

    return try fmt.allocPrint(
        allocator,
        "<{}>",
        .{try mem.join(allocator, ", ", translated_names.items)},
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

fn isTranslatedName(name: []const u8) bool {
    return isNumberType(name) or
        isStringEqualToOneOf(name, &[_][]const u8{ "String", "Boolean" });
}

fn translatedTypeGuardName(allocator: *mem.Allocator, name: []const u8) ![]const u8 {
    return if (mem.eql(u8, name, "String"))
        "svt.isString"
    else if (isNumberType(name))
        "svt.isNumber"
    else if (mem.eql(u8, name, "Boolean"))
        "svt.isBoolean"
    else
        try fmt.allocPrint(allocator, "is{}", .{name});
}

fn translatedValidatorName(allocator: *mem.Allocator, name: []const u8) ![]const u8 {
    return if (mem.eql(u8, name, "String"))
        "svt.validateString"
    else if (isNumberType(name))
        "svt.validateNumber"
    else if (mem.eql(u8, name, "Boolean"))
        "svt.validateBoolean"
    else
        try fmt.allocPrint(allocator, "validate{}", .{name});
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
        \\export type Person = {
        \\    type: "Person";
        \\    name: string;
        \\    age: number;
        \\    efficiency: number;
        \\    on_vacation: boolean;
        \\    hobbies: string[];
        \\    last_fifteen_comments: string[];
        \\    recruiter: Person;
        \\};
        \\
        \\export const isPerson = (value: unknown): value is Person => {
        \\    return svt.isInterface<Person>(value, {type: "Person", name: svt.isString, age: svt.isNumber, efficiency: svt.isNumber, on_vacation: svt.isBoolean, hobbies: svt.arrayOf(svt.isString), last_fifteen_comments: svt.arrayOf(svt.isString), recruiter: isPerson});
        \\};
        \\
        \\export const validatePerson = (value: unknown): svt.ValidationResult<Person> => {
        \\    return svt.validate<Person>(value, {type: "Person", name: svt.validateString, age: svt.validateNumber, efficiency: svt.validateNumber, on_vacation: svt.validateBoolean, hobbies: svt.validateArray(svt.validateString), last_fifteen_comments: svt.validateArray(svt.validateString), recruiter: validatePerson});
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
        \\export type Node<T> = {
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

test "Outputs `Event` union correctly" {
    var allocator = TestingAllocator{};

    const expected_output =
        \\export type Event = LogIn | LogOut | JoinChannels | SetEmails;
        \\
        \\export type LogIn = {
        \\    type: "LogIn";
        \\    data: LogInData;
        \\};
        \\
        \\export type LogOut = {
        \\    type: "LogOut";
        \\    data: UserId;
        \\};
        \\
        \\export type JoinChannels = {
        \\    type: "JoinChannels";
        \\    data: Channel[];
        \\};
        \\
        \\export type SetEmails = {
        \\    type: "SetEmails";
        \\    data: Email[];
        \\};
        \\
        \\export const isLogIn = (value: unknown): value is LogIn => {
        \\    return svt.isInterface<LogIn>(value, {type: "LogIn", data: isLogInData});
        \\};
        \\
        \\export const isLogOut = (value: unknown): value is LogOut => {
        \\    return svt.isInterface<LogOut>(value, {type: "LogOut", data: isUserId});
        \\};
        \\
        \\export const isJoinChannels = (value: unknown): value is JoinChannels => {
        \\    return svt.isInterface<JoinChannels>(value, {type: "JoinChannels", data: svt.arrayOf(isChannel)});
        \\};
        \\
        \\export const isSetEmails = (value: unknown): value is SetEmails => {
        \\    return svt.isInterface<SetEmails>(value, {type: "SetEmails", data: svt.arrayOf(isEmail)});
        \\};
        \\
        \\export const validateLogIn = (value: unknown): svt.ValidationResult<LogIn> => {
        \\    return svt.validate<LogIn>(value, {type: "LogIn", data: validateLogInData});
        \\};
        \\
        \\export const validateLogOut = (value: unknown): svt.ValidationResult<LogOut> => {
        \\    return svt.validate<LogOut>(value, {type: "LogOut", data: validateUserId});
        \\};
        \\
        \\export const validateJoinChannels = (value: unknown): svt.ValidationResult<JoinChannels> => {
        \\    return svt.validate<JoinChannels>(value, {type: "JoinChannels", data: svt.validateArray(validateChannel)});
        \\};
        \\
        \\export const validateSetEmails = (value: unknown): svt.ValidationResult<SetEmails> => {
        \\    return svt.validate<SetEmails>(value, {type: "SetEmails", data: svt.validateArray(validateEmail)});
        \\};
    ;

    var expect_error: ExpectError = undefined;

    const output = try outputPlainUnion(
        &allocator.allocator,
        (try freeform.parser.parse(
            &allocator.allocator,
            &allocator.allocator,
            type_examples.event_union,
            &expect_error,
        )).success.definitions[0].@"union".plain,
    );

    testing.expectEqualStrings(output, expected_output);
}

test "Outputs `Maybe` union correctly" {
    var allocator = TestingAllocator{};

    const expected_output =
        \\export type Maybe<T> = Just<T> | Nothing;
        \\
        \\export type Just<T> = {
        \\    type: "Just";
        \\    data: T;
        \\};
        \\
        \\export type Nothing = {
        \\    type: "Nothing";
        \\};
    ;

    var expect_error: ExpectError = undefined;

    const output = try outputGenericUnion(
        &allocator.allocator,
        (try freeform.parser.parse(
            &allocator.allocator,
            &allocator.allocator,
            type_examples.maybe_union,
            &expect_error,
        )).success.definitions[0].@"union".generic,
    );

    testing.expectEqualStrings(output, expected_output);
}

test "Outputs `Either` union correctly" {
    var allocator = TestingAllocator{};

    const expected_output =
        \\export type Either<E, T> = Left<E> | Right<T>;
        \\
        \\export type Left<E> = {
        \\    type: "Left";
        \\    data: E;
        \\};
        \\
        \\export type Right<T> = {
        \\    type: "Right";
        \\    data: T;
        \\};
    ;

    var expect_error: ExpectError = undefined;

    const output = try outputGenericUnion(
        &allocator.allocator,
        (try freeform.parser.parse(
            &allocator.allocator,
            &allocator.allocator,
            type_examples.either_union,
            &expect_error,
        )).success.definitions[0].@"union".generic,
    );

    testing.expectEqualStrings(output, expected_output);
}

test "Outputs struct with concrete `Maybe` correctly" {
    var allocator = TestingAllocator{};

    const expected_output =
        \\export type WithMaybe = {
        \\    type: "WithMaybe";
        \\    field: Maybe<string>;
        \\};
        \\
        \\export const isWithMaybe = (value: unknown): value is WithMaybe => {
        \\    return svt.isInterface<WithMaybe>(value, {type: "WithMaybe"});
        \\};
        \\
        \\export const validateWithMaybe = (value: unknown): svt.ValidationResult<WithMaybe> => {
        \\    return svt.validate<WithMaybe>(value, {type: "WithMaybe"});
        \\};
    ;

    var expect_error: ExpectError = undefined;

    const output = try outputPlainStructure(
        &allocator.allocator,
        (try freeform.parser.parse(
            &allocator.allocator,
            &allocator.allocator,
            type_examples.structure_with_concrete_maybe,
            &expect_error,
        )).success.definitions[0].structure.plain,
    );

    testing.expectEqualStrings(output, expected_output);
}

test "Outputs struct with different `Maybe`s correctly" {
    var allocator = TestingAllocator{};

    const expected_output =
        \\export type WithMaybe<T, E> = WithConcrete | WithGeneric<T> | WithBare<E>;
        \\
        \\export type WithConcrete = {
        \\    type: "WithConcrete";
        \\    data: Maybe<string>;
        \\};
        \\
        \\export type WithGeneric<T> = {
        \\    type: "WithGeneric";
        \\    data: Maybe<T>;
        \\};
        \\
        \\export type WithBare<E> = {
        \\    type: "WithBare";
        \\    data: E;
        \\};
    ;

    var expect_error: ExpectError = undefined;

    const output = try outputGenericUnion(
        &allocator.allocator,
        (try freeform.parser.parseWithDescribedError(
            &allocator.allocator,
            &allocator.allocator,
            type_examples.union_with_different_maybes,
            &expect_error,
        )).success.definitions[0].@"union".generic,
    );

    testing.expectEqualStrings(output, expected_output);
}

test "Outputs `List` union correctly" {
    var allocator = TestingAllocator{};

    const expected_output =
        \\export type List<T> = Empty | Cons<T>;
        \\
        \\export type Empty = {
        \\    type: "Empty";
        \\};
        \\
        \\export type Cons<T> = {
        \\    type: "Cons";
        \\    data: List<T>;
        \\};
    ;

    var expect_error: ExpectError = undefined;

    const output = try outputGenericUnion(
        &allocator.allocator,
        (try freeform.parser.parseWithDescribedError(
            &allocator.allocator,
            &allocator.allocator,
            type_examples.list_union,
            &expect_error,
        )).success.definitions[0].@"union".generic,
    );

    testing.expectEqualStrings(output, expected_output);
}
