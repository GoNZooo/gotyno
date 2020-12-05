const std = @import("std");
const debug = std.debug;
const fmt = std.fmt;
const heap = std.heap;
const mem = std.mem;
const testing = std.testing;

const ArrayList = std.ArrayList;

const freeform = @import("./freeform.zig");
const type_examples = @import("./freeform/type_examples.zig");

const PlainStructure = freeform.parser.PlainStructure;
const GenericStructure = freeform.parser.GenericStructure;
const PlainUnion = freeform.parser.PlainUnion;
const GenericUnion = freeform.parser.GenericUnion;
const Constructor = freeform.parser.Constructor;
const Type = freeform.parser.Type;
const Field = freeform.parser.Field;
const ExpectError = freeform.tokenizer.ExpectError;

const TestingAllocator = heap.GeneralPurposeAllocator(.{});

fn outputPlainStructure(
    allocator: *mem.Allocator,
    plain_structure: PlainStructure,
) ![]const u8 {
    const name = plain_structure.name;

    const fields_output = try outputStructureFields(allocator, plain_structure.fields);

    const output_format =
        \\type {} = {c}
        \\    type: "{}";
        \\{}
        \\{c};
    ;

    return try fmt.allocPrint(allocator, output_format, .{ name, '{', name, fields_output, '}' });
}

fn outputGenericStructure(
    allocator: *mem.Allocator,
    generic_structure: GenericStructure,
) ![]const u8 {
    const name = generic_structure.name;

    const fields_output = try outputStructureFields(allocator, generic_structure.fields);

    const output_format =
        \\type {}{} = {c}
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
    for (plain_union.constructors) |constructor, i| {
        constructor_names[i] = constructor.tag;
    }

    const constructor_names_output = try mem.join(allocator, " | ", constructor_names);

    const tagged_structures_output = try outputTaggedStructures(
        allocator,
        plain_union.constructors,
    );

    const type_guards_output = try outputTypeGuards(allocator, plain_union.constructors);

    const output_format =
        \\type {} = {};
        \\
        \\{}
        \\
        \\{}
    ;

    return fmt.allocPrint(
        allocator,
        output_format,
        .{ plain_union.name, constructor_names_output, tagged_structures_output, type_guards_output },
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
        \\type {}{} = {};
        \\
        \\{}
    ;

    return fmt.allocPrint(
        allocator,
        output_format,
        .{ generic_union.name, open_names, constructor_names_output, tagged_structures_output },
    );
}

fn outputTypeGuards(allocator: *mem.Allocator, constructors: []Constructor) ![]const u8 {
    var type_guards = try allocator.alloc([]const u8, constructors.len);

    for (constructors) |constructor, i| {
        type_guards[i] = try outputTypeGuard(allocator, constructor);
    }

    const joined_type_guards = try mem.join(allocator, "\n\n", type_guards);

    // for (type_guards) |type_guard| {
    //     allocator.free(type_guard);
    // }

    return joined_type_guards;
}

fn outputTypeGuard(allocator: *mem.Allocator, constructor: Constructor) ![]const u8 {
    const tag = constructor.tag;

    const output_format =
        \\const is{} = (value: unknown): value is {} => {c}
        \\    return svt.isInterfaceOf<{}>(value, {c}type: "{}"{}{c});
        \\{c};
    ;

    const type_guard_output = try getTypeGuardFromType(allocator, constructor.parameter);

    return try fmt.allocPrint(
        allocator,
        output_format,
        .{ tag, tag, '{', tag, '{', tag, type_guard_output, '}', '}' },
    );
}

fn getTypeGuardFromType(allocator: *mem.Allocator, t: Type) ![]const u8 {
    const bare_format = ", data: {}";
    const type_guard_format = ", data: is{}";
    const array_format = ", data: svt.arrayOf({})";

    return switch (t) {
        .empty => "",
        .string => |s| try fmt.allocPrint(allocator, bare_format, .{s}),
        .name => |n| try fmt.allocPrint(allocator, type_guard_format, .{n}),
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

fn getNestedTypeGuardFromType(allocator: *mem.Allocator, t: Type) error{OutOfMemory}![]const u8 {
    const array_format = "svt.arrayOf({})";

    return switch (t) {
        .empty => debug.panic("Empty nested type invalid for type guard\n", .{}),
        .string => |s| try fmt.allocPrint(allocator, "\"{}\"", .{s}),
        .name => |n| try fmt.allocPrint(allocator, "is{}", .{n}),
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
    var tagged_structures_outputs = try allocator.alloc([]const u8, constructors.len);

    for (constructors) |constructor, i| {
        tagged_structures_outputs[i] = try outputTaggedStructure(allocator, constructor);
    }

    return try mem.join(allocator, "\n\n", tagged_structures_outputs);
}

fn outputTaggedMaybeGenericStructures(
    allocator: *mem.Allocator,
    constructors: []Constructor,
    open_names: []const []const u8,
) ![]const u8 {
    var tagged_structures_outputs = try allocator.alloc([]const u8, constructors.len);

    for (constructors) |constructor, i| {
        tagged_structures_outputs[i] = try outputTaggedMaybeGenericStructure(
            allocator,
            constructor,
            open_names,
        );
    }

    return try mem.join(allocator, "\n\n", tagged_structures_outputs);
}

fn outputTaggedStructure(allocator: *mem.Allocator, constructor: Constructor) ![]const u8 {
    const parameter_output = if (try outputType(allocator, constructor.parameter)) |output|
        output
    else
        "null";

    const output_format =
        \\type {} = {c}
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
        \\type {}{} = {c}
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

        else => "",
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

fn isTranslatedName(name: []const u8) bool {
    return isNumberType(name) or
        isStringEqualToOneOf(name, &[_][]const u8{ "String", "Boolean" });
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

test "Outputs `Event` union correctly" {
    var allocator = TestingAllocator{};

    const expected_output =
        \\type Event = LogIn | LogOut | JoinChannels | SetEmails;
        \\
        \\type LogIn = {
        \\    type: "LogIn";
        \\    data: LogInData;
        \\};
        \\
        \\type LogOut = {
        \\    type: "LogOut";
        \\    data: UserId;
        \\};
        \\
        \\type JoinChannels = {
        \\    type: "JoinChannels";
        \\    data: Channel[];
        \\};
        \\
        \\type SetEmails = {
        \\    type: "SetEmails";
        \\    data: Email[];
        \\};
        \\
        \\const isLogIn = (value: unknown): value is LogIn => {
        \\    return svt.isInterfaceOf<LogIn>(value, {type: "LogIn", data: isLogInData});
        \\};
        \\
        \\const isLogOut = (value: unknown): value is LogOut => {
        \\    return svt.isInterfaceOf<LogOut>(value, {type: "LogOut", data: isUserId});
        \\};
        \\
        \\const isJoinChannels = (value: unknown): value is JoinChannels => {
        \\    return svt.isInterfaceOf<JoinChannels>(value, {type: "JoinChannels", data: svt.arrayOf(isChannel)});
        \\};
        \\
        \\const isSetEmails = (value: unknown): value is SetEmails => {
        \\    return svt.isInterfaceOf<SetEmails>(value, {type: "SetEmails", data: svt.arrayOf(isEmail)});
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
        \\type Maybe<T> = Just<T> | Nothing;
        \\
        \\type Just<T> = {
        \\    type: "Just";
        \\    data: T;
        \\};
        \\
        \\type Nothing = {
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
        \\type Either<E, T> = Left<E> | Right<T>;
        \\
        \\type Left<E> = {
        \\    type: "Left";
        \\    data: E;
        \\};
        \\
        \\type Right<T> = {
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
        \\type WithMaybe = {
        \\    type: "WithMaybe";
        \\    field: Maybe<string>;
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
        \\type WithMaybe<T, E> = WithConcrete | WithGeneric<T> | WithBare<E>;
        \\
        \\type WithConcrete = {
        \\    type: "WithConcrete";
        \\    data: Maybe<string>;
        \\};
        \\
        \\type WithGeneric<T> = {
        \\    type: "WithGeneric";
        \\    data: Maybe<T>;
        \\};
        \\
        \\type WithBare<E> = {
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
        \\type List<T> = Empty | Cons<T>;
        \\
        \\type Empty = {
        \\    type: "Empty";
        \\};
        \\
        \\type Cons<T> = {
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
