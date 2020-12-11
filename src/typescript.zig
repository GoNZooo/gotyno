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
        \\export type {} = {{
        \\{}
        \\}};
        \\
        \\{}
        \\
        \\{}
    ;

    return try fmt.allocPrint(
        allocator,
        output_format,
        .{ name, fields_output, type_guards_output, validator_output },
    );
}

fn outputGenericStructure(
    allocator: *mem.Allocator,
    generic_structure: GenericStructure,
) ![]const u8 {
    const name = generic_structure.name;

    const fields_output = try outputStructureFields(allocator, generic_structure.fields);

    const type_guard_output = try outputTypeGuardForGenericStructure(allocator, generic_structure);

    const validator_output = try outputValidatorForGenericStructure(allocator, generic_structure);

    const output_format =
        \\export type {}{} = {{
        \\{}
        \\}};
        \\
        \\{}
        \\
        \\{}
    ;

    return try fmt.allocPrint(
        allocator,
        output_format,
        .{
            name,
            outputOpenNames(allocator, generic_structure.open_names),
            fields_output,
            type_guard_output,
            validator_output,
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

    const constructors_output = try outputConstructors(allocator, plain_union.constructors);

    const union_type_guard_output = try outputTypeGuardForPlainUnion(allocator, plain_union);

    const type_guards_output = try outputTypeGuardsForConstructors(
        allocator,
        plain_union.constructors,
        &[_][]const u8{},
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
            constructors_output,
            union_type_guard_output,
            type_guards_output,
            validators_output,
        },
    );
}

fn outputTypeGuardForPlainUnion(allocator: *mem.Allocator, plain: PlainUnion) ![]const u8 {
    var predicate_outputs = ArrayList([]const u8).init(allocator);
    defer predicate_outputs.deinit();

    for (plain.constructors) |constructor| {
        try predicate_outputs.append(try fmt.allocPrint(allocator, "is{}", .{constructor.tag}));
    }

    const predicates_output = try mem.join(allocator, ", ", predicate_outputs.items);

    const format =
        \\export function is{}(value: unknown): value is {} {{
        \\    return [{}].some((typePredicate) => typePredicate(value));
        \\}}
    ;

    return try fmt.allocPrint(allocator, format, .{ plain.name, plain.name, predicates_output });
}

fn outputGenericUnion(allocator: *mem.Allocator, generic_union: GenericUnion) ![]const u8 {
    const open_names = try outputOpenNames(allocator, generic_union.open_names);

    var constructor_names = try allocator.alloc([]const u8, generic_union.constructors.len);
    for (generic_union.constructors) |constructor, i| {
        const maybe_names = try outputOpenNamesFromType(
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

    const constructors_output = try outputGenericConstructors(
        allocator,
        generic_union.constructors,
        generic_union.open_names,
    );

    const union_type_guard_output = try outputTypeGuardForGenericUnion(allocator, generic_union);

    const type_guards_output = try outputTypeGuardsForConstructors(
        allocator,
        generic_union.constructors,
        generic_union.open_names,
    );

    const output_format =
        \\export type {}{} = {};
        \\
        \\{}
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
            generic_union.name,
            open_names,
            constructor_names_output,
            tagged_structures_output,
            constructors_output,
            union_type_guard_output,
            type_guards_output,
        },
    );
}

fn outputTypeGuardForPlainStructure(
    allocator: *mem.Allocator,
    plain_structure: PlainStructure,
) ![]const u8 {
    const name = plain_structure.name;

    const checkers_output = try getTypeGuardsFromFields(allocator, plain_structure.fields);

    const output_format =
        \\export function is{}(value: unknown): value is {} {{
        \\    return svt.isInterface<{}>(value, {{{}}});
        \\}}
    ;

    return try fmt.allocPrint(
        allocator,
        output_format,
        .{ name, name, name, checkers_output },
    );
}

fn outputTypeGuardForGenericUnion(allocator: *mem.Allocator, generic: GenericUnion) ![]const u8 {
    var predicate_outputs = ArrayList([]const u8).init(allocator);
    defer predicate_outputs.deinit();

    const open_names_predicates = try openNamePredicates(allocator, generic.open_names);

    var open_name_predicate_types = try allocator.alloc([]const u8, generic.open_names.len);
    for (open_name_predicate_types) |*t, i| {
        t.* = try fmt.allocPrint(
            allocator,
            "svt.TypePredicate<{}>",
            .{generic.open_names[i]},
        );
    }
    defer allocator.free(open_name_predicate_types);

    var parameter_outputs = try allocator.alloc([]const u8, generic.open_names.len);
    defer allocator.free(parameter_outputs);
    for (parameter_outputs) |*o, i| {
        o.* = try fmt.allocPrint(
            allocator,
            "{}: {}",
            .{ open_names_predicates.items[i], open_name_predicate_types[i] },
        );
    }

    const parameters_output = try mem.join(allocator, ", ", parameter_outputs);

    const open_names_output = try fmt.allocPrint(
        allocator,
        "{}",
        .{try mem.join(allocator, ", ", generic.open_names)},
    );

    var predicate_list_outputs = ArrayList([]const u8).init(allocator);
    defer predicate_list_outputs.deinit();
    for (generic.constructors) |constructor| {
        const constructor_open_names = try openNamesFromType(
            allocator,
            constructor.parameter,
            generic.open_names,
        );
        defer constructor_open_names.deinit();
        const constructor_open_name_predicates = try openNamePredicates(
            allocator,
            constructor_open_names.items,
        );
        defer constructor_open_name_predicates.deinit();

        try predicate_list_outputs.append(if (constructor_open_names.items.len > 0)
            try fmt.allocPrint(
                allocator,
                "is{}({})",
                .{
                    constructor.tag,
                    try mem.join(allocator, ", ", constructor_open_name_predicates.items),
                },
            )
        else
            try fmt.allocPrint(allocator, "is{}", .{constructor.tag}));
    }

    const predicates_output = try mem.join(allocator, ", ", predicate_list_outputs.items);

    const joined_open_names = try mem.join(allocator, "", generic.open_names);

    const format =
        \\export function is{}<{}>({}): svt.TypePredicate<{}<{}>> {{
        \\    return function is{}{}(value: unknown): value is {}<{}> {{
        \\        return [{}].some((typePredicate) => typePredicate(value));
        \\    }};
        \\}}
    ;

    return try fmt.allocPrint(
        allocator,
        format,
        .{
            generic.name,
            open_names_output,
            parameters_output,
            generic.name,
            open_names_output,
            generic.name,
            joined_open_names,
            generic.name,
            open_names_output,
            predicates_output,
        },
    );
}

fn outputTypeGuardForGenericStructure(
    allocator: *mem.Allocator,
    generic: GenericStructure,
) ![]const u8 {
    const open_names = try actualOpenNames(allocator, generic.open_names);
    defer open_names.deinit();
    const open_names_output = try mem.join(allocator, ", ", open_names.items);
    const open_names_together = try mem.join(allocator, "", open_names.items);

    const open_names_predicates = try openNamePredicates(allocator, open_names.items);
    defer open_names_predicates.deinit();
    const open_names_predicates_output = try mem.join(allocator, ", ", open_names_predicates.items);

    var open_name_predicate_types = try allocator.alloc([]const u8, open_names.items.len);
    for (open_name_predicate_types) |*t, i| {
        t.* = try fmt.allocPrint(allocator, "svt.TypePredicate<{}>", .{open_names.items[i]});
    }
    defer allocator.free(open_name_predicate_types);

    var parameter_outputs = try allocator.alloc([]const u8, open_names.items.len);
    defer allocator.free(parameter_outputs);
    for (parameter_outputs) |*o, i| {
        o.* = try fmt.allocPrint(
            allocator,
            "{}: {}",
            .{ open_names_predicates.items[i], open_name_predicate_types[i] },
        );
    }

    const parameters_output = try mem.join(allocator, ", ", parameter_outputs);

    const fields_output = try getTypeGuardsFromFields(allocator, generic.fields);

    const format_with_open_names =
        \\export function is{}<{}>({}): svt.TypePredicate<{}<{}>> {{
        \\    return function is{}{}(value: unknown): value is {}<{}> {{
        \\        return svt.isInstance<{}<{}>>(value, {{{}}});
        \\    }};
        \\}}
    ;

    return try fmt.allocPrint(
        allocator,
        format_with_open_names,
        .{
            generic.name,
            open_names_output,
            parameters_output,
            generic.name,
            open_names_output,
            generic.name,
            open_names_together,
            generic.name,
            open_names_output,
            generic.name,
            open_names_output,
            fields_output,
        },
    );
}

fn outputValidatorForGenericStructure(
    allocator: *mem.Allocator,
    generic: GenericStructure,
) ![]const u8 {
    const open_names = try actualOpenNames(allocator, generic.open_names);
    defer open_names.deinit();
    const open_names_output = try mem.join(allocator, ", ", open_names.items);
    const open_names_together = try mem.join(allocator, "", open_names.items);

    const open_names_validators = try openNameValidators(allocator, open_names.items);
    defer open_names_validators.deinit();
    const open_names_predicates_output = try mem.join(allocator, ", ", open_names_validators.items);

    var open_name_validator_types = try allocator.alloc([]const u8, open_names.items.len);
    for (open_name_validator_types) |*t, i| {
        t.* = try fmt.allocPrint(allocator, "svt.Validator<{}>", .{open_names.items[i]});
    }
    defer allocator.free(open_name_validator_types);

    var parameter_outputs = try allocator.alloc([]const u8, open_names.items.len);
    defer allocator.free(parameter_outputs);
    for (parameter_outputs) |*o, i| {
        o.* = try fmt.allocPrint(
            allocator,
            "{}: {}",
            .{ open_names_validators.items[i], open_name_validator_types[i] },
        );
    }

    const parameters_output = try mem.join(allocator, ", ", parameter_outputs);

    const fields_output = try getValidatorsFromFields(allocator, generic.fields);

    const format_with_open_names =
        \\export function validate{}<{}>({}): svt.Validator<{}<{}>> {{
        \\    return function validate{}{}(value: unknown): svt.ValidationResult<{}<{}>> {{
        \\        return svt.validate<{}<{}>>(value, {{{}}});
        \\    }};
        \\}}
    ;

    return try fmt.allocPrint(
        allocator,
        format_with_open_names,
        .{
            generic.name,
            open_names_output,
            parameters_output,
            generic.name,
            open_names_output,
            generic.name,
            open_names_together,
            generic.name,
            open_names_output,
            generic.name,
            open_names_output,
            fields_output,
        },
    );
}

fn openNamePredicates(allocator: *mem.Allocator, names: []const []const u8) !ArrayList([]const u8) {
    var predicates = ArrayList([]const u8).init(allocator);

    for (names) |name| {
        try predicates.append(try translatedTypeGuardName(allocator, name));
    }

    return predicates;
}

fn openNameValidators(allocator: *mem.Allocator, names: []const []const u8) !ArrayList([]const u8) {
    var validators = ArrayList([]const u8).init(allocator);

    for (names) |name| {
        try validators.append(try translatedValidatorName(allocator, name));
    }

    return validators;
}

fn outputValidatorForPlainStructure(
    allocator: *mem.Allocator,
    plain_structure: PlainStructure,
) ![]const u8 {
    const name = plain_structure.name;

    const validators_output = try getValidatorsFromFields(allocator, plain_structure.fields);

    const output_format =
        \\export function validate{}(value: unknown): svt.ValidationResult<{}> {{
        \\    return svt.validate<{}>(value, {{{}}});
        \\}}
    ;

    return try fmt.allocPrint(
        allocator,
        output_format,
        .{ name, name, name, validators_output },
    );
}

fn getTypeGuardsFromFields(allocator: *mem.Allocator, fields: []Field) ![]const u8 {
    var fields_outputs = ArrayList([]const u8).init(allocator);
    defer fields_outputs.deinit();

    for (fields) |field| {
        if (try getTypeGuardFromType(allocator, field.@"type")) |type_guard| {
            const output = try fmt.allocPrint(allocator, "{}: {}", .{ field.name, type_guard });
            try fields_outputs.append(output);
        }
    }

    return try mem.join(allocator, ", ", fields_outputs.items);
}

fn getValidatorsFromFields(allocator: *mem.Allocator, fields: []Field) ![]const u8 {
    var fields_outputs = ArrayList([]const u8).init(allocator);
    defer fields_outputs.deinit();

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
    const optional_format = "svt.optional({})";

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
        .optional => |o| try fmt.allocPrint(
            allocator,
            optional_format,
            .{try getNestedTypeGuardFromType(allocator, o.@"type".*)},
        ),

        .applied_name => |applied_name| output: {
            const open_name_predicates = try openNamePredicates(allocator, applied_name.open_names);

            break :output try fmt.allocPrint(
                allocator,
                "is{}({})",
                .{ applied_name.name, try mem.join(allocator, ", ", open_name_predicates.items) },
            );
        },

        .empty => debug.panic("Empty type does not seem like it should have a type guard\n", .{}),
    };
}

fn getValidatorFromType(allocator: *mem.Allocator, t: Type) !?[]const u8 {
    const array_format = "svt.validateArray({})";
    const optional_format = "svt.validateOptional({})";

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
        .optional => |o| try fmt.allocPrint(
            allocator,
            optional_format,
            .{try getNestedValidatorFromType(allocator, o.@"type".*)},
        ),

        .applied_name => |applied_name| output: {
            const open_name_validators = try openNameValidators(allocator, applied_name.open_names);

            break :output try fmt.allocPrint(
                allocator,
                "validate{}({})",
                .{ applied_name.name, try mem.join(allocator, ", ", open_name_validators.items) },
            );
        },

        .empty => debug.panic("Empty type does not seem like it should have a type guard\n", .{}),
    };
}

fn outputConstructors(
    allocator: *mem.Allocator,
    constructors: []Constructor,
) ![]const u8 {
    var constructor_outputs = ArrayList([]const u8).init(allocator);
    defer constructor_outputs.deinit();

    for (constructors) |constructor| {
        try constructor_outputs.append(try outputConstructor(
            allocator,
            constructor,
            &[_][]const u8{},
        ));
    }

    return try mem.join(allocator, "\n\n", constructor_outputs.items);
}

fn outputTypeGuardsForConstructors(
    allocator: *mem.Allocator,
    constructors: []Constructor,
    open_names: []const []const u8,
) ![]const u8 {
    var type_guards = ArrayList([]const u8).init(allocator);
    defer type_guards.deinit();

    for (constructors) |constructor| {
        try type_guards.append(
            try outputTypeGuardForConstructor(allocator, constructor, open_names),
        );
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

fn outputConstructor(
    allocator: *mem.Allocator,
    constructor: Constructor,
    open_names: []const []const u8,
) ![]const u8 {
    const constructor_name = try outputConstructorName(allocator, constructor, open_names);
    const tag = constructor.tag;

    const data_specification = try getDataSpecificationFromType(
        allocator,
        constructor.parameter,
        open_names,
    );

    const open_names_output = try outputOpenNamesFromType(
        allocator,
        constructor.parameter,
        open_names,
    );

    const output_format_with_data =
        \\export function {}{}(data: {}): {}{} {{
        \\    return {{type: "{}", data}};
        \\}}
    ;

    const output_format_without_data =
        \\export function {}(): {} {{
        \\    return {{type: "{}"}};
        \\}}
    ;

    return if (data_specification) |specification|
        try fmt.allocPrint(
            allocator,
            output_format_with_data,
            .{ tag, open_names_output, specification, tag, open_names_output, tag },
        )
    else
        try fmt.allocPrint(allocator, output_format_without_data, .{ tag, tag, tag });
}

fn outputConstructorName(
    allocator: *mem.Allocator,
    constructor: Constructor,
    open_names: []const []const u8,
) ![]const u8 {
    return try fmt.allocPrint(
        allocator,
        "{}{}",
        .{
            constructor.tag,
            try outputOpenNamesFromType(allocator, constructor.parameter, open_names),
        },
    );
}

fn outputTypeGuardForConstructor(
    allocator: *mem.Allocator,
    constructor: Constructor,
    open_names: []const []const u8,
) ![]const u8 {
    const tag = constructor.tag;

    const constructor_open_names = try openNamesFromType(
        allocator,
        constructor.parameter,
        open_names,
    );
    const open_names_output = try outputOpenNamesFromType(
        allocator,
        constructor.parameter,
        open_names,
    );
    const open_names_predicates = try openNamePredicates(allocator, constructor_open_names.items);

    var open_name_predicate_types = try allocator.alloc(
        []const u8,
        constructor_open_names.items.len,
    );
    for (open_name_predicate_types) |*t, i| {
        t.* = try fmt.allocPrint(
            allocator,
            "svt.TypePredicate<{}>",
            .{constructor_open_names.items[i]},
        );
    }
    defer allocator.free(open_name_predicate_types);

    var parameter_outputs = try allocator.alloc([]const u8, constructor_open_names.items.len);
    defer allocator.free(parameter_outputs);
    for (parameter_outputs) |*o, i| {
        o.* = try fmt.allocPrint(
            allocator,
            "{}: {}",
            .{ open_names_predicates.items[i], open_name_predicate_types[i] },
        );
    }

    const parameters_output = try mem.join(allocator, ", ", parameter_outputs);

    const output_format_with_open_names =
        \\export function is{}{}({}): svt.TypePredicate<{}{}> {{
        \\    return function is{}{}(value: unknown): value is {}{} {{
        \\        return svt.isInterface<{}{}>(value, {{type: "{}"{}}});
        \\    }};
        \\}}
    ;

    const output_format_without_open_names =
        \\export function is{}(value: unknown): value is {} {{
        \\    return svt.isInterface<{}>(value, {{type: "{}"{}}});
        \\}}
    ;

    const type_guard_output = try getDataTypeGuardFromType(allocator, constructor.parameter);

    return if (constructor_open_names.items.len > 0)
        try fmt.allocPrint(
            allocator,
            output_format_with_open_names,
            .{
                tag,
                open_names_output,
                parameters_output,
                tag,
                open_names_output,
                tag,
                try mem.join(allocator, "", constructor_open_names.items),
                tag,
                open_names_output,
                tag,
                open_names_output,
                tag,
                type_guard_output,
            },
        )
    else
        try fmt.allocPrint(
            allocator,
            output_format_without_open_names,
            .{ tag, tag, tag, tag, type_guard_output },
        );
}

fn outputValidatorForConstructor(allocator: *mem.Allocator, constructor: Constructor) ![]const u8 {
    const tag = constructor.tag;

    const output_format =
        \\export function validate{}(value: unknown): svt.ValidationResult<{}> {{
        \\    return svt.validate<{}>(value, {{type: "{}"{}}});
        \\}}
    ;

    const validator_output = try getDataValidatorFromType(allocator, constructor.parameter);

    return try fmt.allocPrint(allocator, output_format, .{ tag, tag, tag, tag, validator_output });
}

fn getDataSpecificationFromType(
    allocator: *mem.Allocator,
    t: Type,
    open_names: []const []const u8,
) !?[]const u8 {
    const bare_format = "{}";
    const array_format = "{}[]";
    const optional_format = "{} | null";

    return switch (t) {
        .empty => null,
        .string => |s| try fmt.allocPrint(allocator, bare_format, .{s}),
        .name => |n| try fmt.allocPrint(allocator, bare_format, .{translateName(n)}),
        .array => |a| try fmt.allocPrint(
            allocator,
            array_format,
            .{try getNestedDataSpecificationFromType(allocator, a.@"type".*)},
        ),
        .slice => |s| try fmt.allocPrint(
            allocator,
            array_format,
            .{try getNestedDataSpecificationFromType(allocator, s.@"type".*)},
        ),
        .pointer => |p| try fmt.allocPrint(
            allocator,
            bare_format,
            .{try getNestedDataSpecificationFromType(allocator, p.@"type".*)},
        ),
        .optional => |o| try fmt.allocPrint(
            allocator,
            optional_format,
            .{try getNestedDataSpecificationFromType(allocator, o.@"type".*)},
        ),
        .applied_name => |applied_name| output: {
            break :output try fmt.allocPrint(
                allocator,
                "{}{}",
                .{ applied_name.name, try outputOpenNames(allocator, applied_name.open_names) },
            );
        },
    };
}

fn getDataTypeGuardFromType(allocator: *mem.Allocator, t: Type) ![]const u8 {
    const bare_format = ", data: {}";
    const type_guard_format = ", data: {}";
    const builtin_type_guard_format = ", data: svt.is{}";
    const array_format = ", data: svt.arrayOf({})";
    const optional_format = ", data: svt.optional({})";

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
        .optional => |o| try fmt.allocPrint(
            allocator,
            optional_format,
            .{try getNestedTypeGuardFromType(allocator, o.@"type".*)},
        ),
        .applied_name => |applied| applied: {
            const open_name_predicates = try openNamePredicates(allocator, applied.open_names);
            defer open_name_predicates.deinit();

            break :applied try fmt.allocPrint(
                allocator,
                ", data: is{}({})",
                .{ applied.name, try mem.join(allocator, ", ", open_name_predicates.items) },
            );
        },
    };
}

fn getDataValidatorFromType(allocator: *mem.Allocator, t: Type) ![]const u8 {
    const bare_format = ", data: {}";
    const validator_format = ", data: {}";
    const builtin_type_guard_format = ", data: svt.validate{}";
    const array_format = ", data: svt.validateArray({})";
    const optional_format = ", data: svt.validateOptional({})";

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
        .optional => |o| try fmt.allocPrint(
            allocator,
            optional_format,
            .{try getNestedValidatorFromType(allocator, o.@"type".*)},
        ),
        .applied_name => debug.panic("Trying to get validator from type for: {}\n", .{t}),
    };
}

fn getNestedDataSpecificationFromType(
    allocator: *mem.Allocator,
    t: Type,
) error{OutOfMemory}![]const u8 {
    const array_format = "{}[]";
    const optional_format = "{} | null";

    return switch (t) {
        .empty => debug.panic("Empty nested type invalid for data specification\n", .{}),
        .string => |s| try fmt.allocPrint(allocator, "\"{}\"", .{s}),
        .name => |n| try fmt.allocPrint(
            allocator,
            "{}",
            .{translateName(n)},
        ),
        .array => |a| try fmt.allocPrint(
            allocator,
            array_format,
            .{try getNestedDataSpecificationFromType(allocator, a.@"type".*)},
        ),
        .slice => |s| try fmt.allocPrint(
            allocator,
            array_format,
            .{try getNestedDataSpecificationFromType(allocator, s.@"type".*)},
        ),
        .pointer => |p| try fmt.allocPrint(
            allocator,
            "is{}",
            .{try getNestedDataSpecificationFromType(allocator, p.@"type".*)},
        ),
        .optional => |o| try fmt.allocPrint(
            allocator,
            optional_format,
            .{try getNestedDataSpecificationFromType(allocator, o.@"type".*)},
        ),
        .applied_name => |applied_name| output: {
            break :output try fmt.allocPrint(
                allocator,
                "{}{}",
                .{ applied_name.name, try outputOpenNames(allocator, applied_name.open_names) },
            );
        },
    };
}

fn getNestedTypeGuardFromType(allocator: *mem.Allocator, t: Type) error{OutOfMemory}![]const u8 {
    const array_format = "svt.arrayOf({})";
    const optional_format = "svt.optional({})";

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
        .optional => |o| try fmt.allocPrint(
            allocator,
            optional_format,
            .{try getNestedTypeGuardFromType(allocator, o.@"type".*)},
        ),
        .applied_name => |applied| applied: {
            const open_name_predicates = try openNamePredicates(allocator, applied.open_names);
            defer open_name_predicates.deinit();

            break :applied try fmt.allocPrint(
                allocator,
                "is{}({})",
                .{ applied.name, try mem.join(allocator, ", ", open_name_predicates.items) },
            );
        },
    };
}

fn getNestedValidatorFromType(allocator: *mem.Allocator, t: Type) error{OutOfMemory}![]const u8 {
    const array_format = "svt.validateArray({})";
    const optional_format = "svt.validateOptional({})";

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
        .optional => |o| try fmt.allocPrint(
            allocator,
            optional_format,
            .{try getNestedValidatorFromType(allocator, o.@"type".*)},
        ),
        .applied_name => debug.panic("Trying to get type guard from type for: {}\n", .{t}),
    };
}

fn outputCommonOpenNames(
    allocator: *mem.Allocator,
    as: []const []const u8,
    bs: []const []const u8,
) ![]const u8 {
    const common_names = try commonOpenNames(allocator, as, bs);
    defer common_names.deinit();

    return if (common_names.items.len == 0)
        ""
    else
        try fmt.allocPrint(allocator, "<{}>", .{try mem.join(allocator, ", ", common_names.items)});
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

fn outputGenericConstructors(
    allocator: *mem.Allocator,
    constructors: []Constructor,
    open_names: []const []const u8,
) ![]const u8 {
    var constructor_outputs = ArrayList([]const u8).init(allocator);
    defer constructor_outputs.deinit();

    for (constructors) |constructor| {
        try constructor_outputs.append(try outputConstructor(
            allocator,
            constructor,
            open_names,
        ));
    }

    return try mem.join(allocator, "\n\n", constructor_outputs.items);
}

fn outputTaggedStructure(allocator: *mem.Allocator, constructor: Constructor) ![]const u8 {
    const parameter_output = try outputType(allocator, constructor.parameter);

    const output_format_with_parameter =
        \\export type {} = {{
        \\    type: "{}";
        \\    data: {};
        \\}};
    ;

    const output_format_without_parameter =
        \\export type {} = {{
        \\    type: "{}";
        \\}};
    ;

    return if (parameter_output) |output|
        try fmt.allocPrint(
            allocator,
            output_format_with_parameter,
            .{ constructor.tag, constructor.tag, output },
        )
    else
        try fmt.allocPrint(
            allocator,
            output_format_without_parameter,
            .{ constructor.tag, constructor.tag },
        );
}

fn outputTaggedMaybeGenericStructure(
    allocator: *mem.Allocator,
    constructor: Constructor,
    open_names: []const []const u8,
) ![]const u8 {
    const open_names_output = outputOpenNamesFromType(allocator, constructor.parameter, open_names);

    const parameter_output = if (try outputType(allocator, constructor.parameter)) |output|
        try fmt.allocPrint(allocator, "\n    data: {};", .{output})
    else
        "";

    const output_format =
        \\export type {}{} = {{
        \\    type: "{}";{}
        \\}};
    ;

    return fmt.allocPrint(
        allocator,
        output_format,
        .{ constructor.tag, open_names_output, constructor.tag, parameter_output },
    );
}

fn openNamesFromType(
    allocator: *mem.Allocator,
    t: Type,
    open_names: []const []const u8,
) error{OutOfMemory}!ArrayList([]const u8) {
    return switch (t) {
        .pointer => |p| try openNamesFromType(allocator, p.@"type".*, open_names),
        .array => |a| try openNamesFromType(allocator, a.@"type".*, open_names),
        .slice => |s| try openNamesFromType(allocator, s.@"type".*, open_names),
        .optional => |o| try openNamesFromType(allocator, o.@"type".*, open_names),

        .applied_name => |applied| try commonOpenNames(allocator, open_names, applied.open_names),

        .name => |name| name: {
            var open_name_list = ArrayList([]const u8).init(allocator);

            if (isStringEqualToOneOf(name, open_names)) {
                try open_name_list.append(name);
            }

            break :name open_name_list;
        },

        .string, .empty => ArrayList([]const u8).init(allocator),
    };
}

fn commonOpenNames(
    allocator: *mem.Allocator,
    as: []const []const u8,
    bs: []const []const u8,
) !ArrayList([]const u8) {
    var common_names = ArrayList([]const u8).init(allocator);

    for (as) |a| {
        for (bs) |b| {
            if (mem.eql(u8, a, b) and !isTranslatedName(a)) try common_names.append(a);
        }
    }

    return common_names;
}

fn outputOpenNamesFromType(
    allocator: *mem.Allocator,
    t: Type,
    open_names: []const []const u8,
) error{OutOfMemory}![]const u8 {
    const type_open_names = try openNamesFromType(allocator, t, open_names);
    defer type_open_names.deinit();

    return if (type_open_names.items.len == 0)
        ""
    else
        try fmt.allocPrint(
            allocator,
            "<{}>",
            .{try mem.join(allocator, ", ", type_open_names.items)},
        );
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

        .optional => |o| output: {
            const embedded_type = switch (o.@"type".*) {
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
                else => debug.panic("Invalid embedded type for optional: {}\n", .{o.@"type"}),
            };

            break :output try fmt.allocPrint(allocator, "{} | null | undefined", .{embedded_type});
        },

        .applied_name => |applied_name| try fmt.allocPrint(
            allocator,
            "{}{}",
            .{ applied_name.name, try outputOpenNames(allocator, applied_name.open_names) },
        ),
    };
}

/// Returns all actual open names for a list of names. This means they're not translated and so
/// won't be assumed to be concrete type arguments.
fn actualOpenNames(allocator: *mem.Allocator, names: []const []const u8) !ArrayList([]const u8) {
    var open_names = ArrayList([]const u8).init(allocator);

    for (names) |name| {
        if (!isTranslatedName(name)) try open_names.append(name);
    }

    return open_names;
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
        \\export function isPerson(value: unknown): value is Person {
        \\    return svt.isInterface<Person>(value, {type: "Person", name: svt.isString, age: svt.isNumber, efficiency: svt.isNumber, on_vacation: svt.isBoolean, hobbies: svt.arrayOf(svt.isString), last_fifteen_comments: svt.arrayOf(svt.isString), recruiter: isPerson});
        \\}
        \\
        \\export function validatePerson(value: unknown): svt.ValidationResult<Person> {
        \\    return svt.validate<Person>(value, {type: "Person", name: svt.validateString, age: svt.validateNumber, efficiency: svt.validateNumber, on_vacation: svt.validateBoolean, hobbies: svt.validateArray(svt.validateString), last_fifteen_comments: svt.validateArray(svt.validateString), recruiter: validatePerson});
        \\}
    ;

    var expect_error: ExpectError = undefined;

    const output = try outputPlainStructure(
        &allocator.allocator,
        (try parser.parse(
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
        \\export type Node<T, U> = {
        \\    data: T;
        \\    otherData: U;
        \\};
        \\
        \\export function isNode<T, U>(isT: svt.TypePredicate<T>, isU: svt.TypePredicate<U>): svt.TypePredicate<Node<T, U>> {
        \\    return function isNodeTU(value: unknown): value is Node<T, U> {
        \\        return svt.isInstance<Node<T, U>>(value, {data: isT, otherData: isU});
        \\    };
        \\}
        \\
        \\export function validateNode<T, U>(validateT: svt.Validator<T>, validateU: svt.Validator<U>): svt.Validator<Node<T, U>> {
        \\    return function validateNodeTU(value: unknown): svt.ValidationResult<Node<T, U>> {
        \\        return svt.validate<Node<T, U>>(value, {data: validateT, otherData: validateU});
        \\    };
        \\}
    ;

    var expect_error: ExpectError = undefined;

    const output = try outputGenericStructure(
        &allocator.allocator,
        (try parser.parse(
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
        \\export type Event = LogIn | LogOut | JoinChannels | SetEmails | Close;
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
        \\export type Close = {
        \\    type: "Close";
        \\};
        \\
        \\export function LogIn(data: LogInData): LogIn {
        \\    return {type: "LogIn", data};
        \\}
        \\
        \\export function LogOut(data: UserId): LogOut {
        \\    return {type: "LogOut", data};
        \\}
        \\
        \\export function JoinChannels(data: Channel[]): JoinChannels {
        \\    return {type: "JoinChannels", data};
        \\}
        \\
        \\export function SetEmails(data: Email[]): SetEmails {
        \\    return {type: "SetEmails", data};
        \\}
        \\
        \\export function Close(): Close {
        \\    return {type: "Close"};
        \\}
        \\
        \\export function isEvent(value: unknown): value is Event {
        \\    return [isLogIn, isLogOut, isJoinChannels, isSetEmails, isClose].some((typePredicate) => typePredicate(value));
        \\}
        \\
        \\export function isLogIn(value: unknown): value is LogIn {
        \\    return svt.isInterface<LogIn>(value, {type: "LogIn", data: isLogInData});
        \\}
        \\
        \\export function isLogOut(value: unknown): value is LogOut {
        \\    return svt.isInterface<LogOut>(value, {type: "LogOut", data: isUserId});
        \\}
        \\
        \\export function isJoinChannels(value: unknown): value is JoinChannels {
        \\    return svt.isInterface<JoinChannels>(value, {type: "JoinChannels", data: svt.arrayOf(isChannel)});
        \\}
        \\
        \\export function isSetEmails(value: unknown): value is SetEmails {
        \\    return svt.isInterface<SetEmails>(value, {type: "SetEmails", data: svt.arrayOf(isEmail)});
        \\}
        \\
        \\export function isClose(value: unknown): value is Close {
        \\    return svt.isInterface<Close>(value, {type: "Close"});
        \\}
        \\
        \\export function validateLogIn(value: unknown): svt.ValidationResult<LogIn> {
        \\    return svt.validate<LogIn>(value, {type: "LogIn", data: validateLogInData});
        \\}
        \\
        \\export function validateLogOut(value: unknown): svt.ValidationResult<LogOut> {
        \\    return svt.validate<LogOut>(value, {type: "LogOut", data: validateUserId});
        \\}
        \\
        \\export function validateJoinChannels(value: unknown): svt.ValidationResult<JoinChannels> {
        \\    return svt.validate<JoinChannels>(value, {type: "JoinChannels", data: svt.validateArray(validateChannel)});
        \\}
        \\
        \\export function validateSetEmails(value: unknown): svt.ValidationResult<SetEmails> {
        \\    return svt.validate<SetEmails>(value, {type: "SetEmails", data: svt.validateArray(validateEmail)});
        \\}
        \\
        \\export function validateClose(value: unknown): svt.ValidationResult<Close> {
        \\    return svt.validate<Close>(value, {type: "Close"});
        \\}
    ;

    var expect_error: ExpectError = undefined;

    const output = try outputPlainUnion(
        &allocator.allocator,
        (try parser.parse(
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
        \\
        \\export function Just<T>(data: T): Just<T> {
        \\    return {type: "Just", data};
        \\}
        \\
        \\export function Nothing(): Nothing {
        \\    return {type: "Nothing"};
        \\}
        \\
        \\export function isMaybe<T>(isT: svt.TypePredicate<T>): svt.TypePredicate<Maybe<T>> {
        \\    return function isMaybeT(value: unknown): value is Maybe<T> {
        \\        return [isJust(isT), isNothing].some((typePredicate) => typePredicate(value));
        \\    };
        \\}
        \\
        \\export function isJust<T>(isT: svt.TypePredicate<T>): svt.TypePredicate<Just<T>> {
        \\    return function isJustT(value: unknown): value is Just<T> {
        \\        return svt.isInterface<Just<T>>(value, {type: "Just", data: isT});
        \\    };
        \\}
        \\
        \\export function isNothing(value: unknown): value is Nothing {
        \\    return svt.isInterface<Nothing>(value, {type: "Nothing"});
        \\}
    ;

    var expect_error: ExpectError = undefined;

    const output = try outputGenericUnion(
        &allocator.allocator,
        (try parser.parse(
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
        \\
        \\export function Left<E>(data: E): Left<E> {
        \\    return {type: "Left", data};
        \\}
        \\
        \\export function Right<T>(data: T): Right<T> {
        \\    return {type: "Right", data};
        \\}
        \\
        \\export function isEither<E, T>(isE: svt.TypePredicate<E>, isT: svt.TypePredicate<T>): svt.TypePredicate<Either<E, T>> {
        \\    return function isEitherET(value: unknown): value is Either<E, T> {
        \\        return [isLeft(isE), isRight(isT)].some((typePredicate) => typePredicate(value));
        \\    };
        \\}
        \\
        \\export function isLeft<E>(isE: svt.TypePredicate<E>): svt.TypePredicate<Left<E>> {
        \\    return function isLeftE(value: unknown): value is Left<E> {
        \\        return svt.isInterface<Left<E>>(value, {type: "Left", data: isE});
        \\    };
        \\}
        \\
        \\export function isRight<T>(isT: svt.TypePredicate<T>): svt.TypePredicate<Right<T>> {
        \\    return function isRightT(value: unknown): value is Right<T> {
        \\        return svt.isInterface<Right<T>>(value, {type: "Right", data: isT});
        \\    };
        \\}
    ;

    var expect_error: ExpectError = undefined;

    const output = try outputGenericUnion(
        &allocator.allocator,
        (try parser.parse(
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
        \\    field: Maybe<string>;
        \\};
        \\
        \\export function isWithMaybe(value: unknown): value is WithMaybe {
        \\    return svt.isInterface<WithMaybe>(value, {field: isMaybe(svt.isString)});
        \\}
        \\
        \\export function validateWithMaybe(value: unknown): svt.ValidationResult<WithMaybe> {
        \\    return svt.validate<WithMaybe>(value, {field: validateMaybe(svt.validateString)});
        \\}
    ;

    var expect_error: ExpectError = undefined;

    const output = try outputPlainStructure(
        &allocator.allocator,
        (try parser.parse(
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
        \\
        \\export function WithConcrete(data: Maybe<string>): WithConcrete {
        \\    return {type: "WithConcrete", data};
        \\}
        \\
        \\export function WithGeneric<T>(data: Maybe<T>): WithGeneric<T> {
        \\    return {type: "WithGeneric", data};
        \\}
        \\
        \\export function WithBare<E>(data: E): WithBare<E> {
        \\    return {type: "WithBare", data};
        \\}
        \\
        \\export function isWithMaybe<T, E>(isT: svt.TypePredicate<T>, isE: svt.TypePredicate<E>): svt.TypePredicate<WithMaybe<T, E>> {
        \\    return function isWithMaybeTE(value: unknown): value is WithMaybe<T, E> {
        \\        return [isWithConcrete, isWithGeneric(isT), isWithBare(isE)].some((typePredicate) => typePredicate(value));
        \\    };
        \\}
        \\
        \\export function isWithConcrete(value: unknown): value is WithConcrete {
        \\    return svt.isInterface<WithConcrete>(value, {type: "WithConcrete", data: isMaybe(svt.isString)});
        \\}
        \\
        \\export function isWithGeneric<T>(isT: svt.TypePredicate<T>): svt.TypePredicate<WithGeneric<T>> {
        \\    return function isWithGenericT(value: unknown): value is WithGeneric<T> {
        \\        return svt.isInterface<WithGeneric<T>>(value, {type: "WithGeneric", data: isMaybe(isT)});
        \\    };
        \\}
        \\
        \\export function isWithBare<E>(isE: svt.TypePredicate<E>): svt.TypePredicate<WithBare<E>> {
        \\    return function isWithBareE(value: unknown): value is WithBare<E> {
        \\        return svt.isInterface<WithBare<E>>(value, {type: "WithBare", data: isE});
        \\    };
        \\}
    ;

    var expect_error: ExpectError = undefined;

    const output = try outputGenericUnion(
        &allocator.allocator,
        (try parser.parseWithDescribedError(
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
        \\
        \\export function Empty(): Empty {
        \\    return {type: "Empty"};
        \\}
        \\
        \\export function Cons<T>(data: List<T>): Cons<T> {
        \\    return {type: "Cons", data};
        \\}
        \\
        \\export function isList<T>(isT: svt.TypePredicate<T>): svt.TypePredicate<List<T>> {
        \\    return function isListT(value: unknown): value is List<T> {
        \\        return [isEmpty, isCons(isT)].some((typePredicate) => typePredicate(value));
        \\    };
        \\}
        \\
        \\export function isEmpty(value: unknown): value is Empty {
        \\    return svt.isInterface<Empty>(value, {type: "Empty"});
        \\}
        \\
        \\export function isCons<T>(isT: svt.TypePredicate<T>): svt.TypePredicate<Cons<T>> {
        \\    return function isConsT(value: unknown): value is Cons<T> {
        \\        return svt.isInterface<Cons<T>>(value, {type: "Cons", data: isList(isT)});
        \\    };
        \\}
    ;

    var expect_error: ExpectError = undefined;

    const output = try outputGenericUnion(
        &allocator.allocator,
        (try parser.parseWithDescribedError(
            &allocator.allocator,
            &allocator.allocator,
            type_examples.list_union,
            &expect_error,
        )).success.definitions[0].@"union".generic,
    );

    testing.expectEqualStrings(output, expected_output);
}

test "Outputs struct with optional float value correctly" {
    var allocator = TestingAllocator{};

    const expected_output =
        \\export type WithOptionalFloat = {
        \\    field: number | null | undefined;
        \\};
        \\
        \\export function isWithOptionalFloat(value: unknown): value is WithOptionalFloat {
        \\    return svt.isInterface<WithOptionalFloat>(value, {field: svt.optional(svt.isNumber)});
        \\}
        \\
        \\export function validateWithOptionalFloat(value: unknown): svt.ValidationResult<WithOptionalFloat> {
        \\    return svt.validate<WithOptionalFloat>(value, {field: svt.validateOptional(svt.validateNumber)});
        \\}
    ;

    var expect_error: ExpectError = undefined;
    const parsed_definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        type_examples.structure_with_optional_float,
        &expect_error,
    );

    const output = try outputPlainStructure(
        &allocator.allocator,
        parsed_definitions.success.definitions[0].structure.plain,
    );

    testing.expectEqualStrings(output, expected_output);
}
