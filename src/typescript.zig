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
const Import = parser.Import;
const UntaggedUnion = parser.UntaggedUnion;
const UntaggedUnionValue = parser.UntaggedUnionValue;
const Enumeration = parser.Enumeration;
const EnumerationField = parser.EnumerationField;
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
        // @TODO: pass down definitions to most of these such that they can use other definitions
        // in their compilation, meaning we can refer/embed structures from other definitions, etc.
        // Most obviously useful for import reference, struct embedding if one wants to support
        // embedding tag fields (meaning we have to merge `tag_field: "..."` with some previously
        // defined structure).
        const output = switch (definition) {
            .structure => |structure| switch (structure) {
                .plain => |plain| try outputPlainStructure(allocator, plain),
                .generic => |generic| try outputGenericStructure(allocator, generic),
            },
            .@"union" => |u| switch (u) {
                .plain => |plain| try outputPlainUnion(allocator, plain),
                .generic => |generic| try outputGenericUnion(allocator, generic),
            },
            .enumeration => |enumeration| try outputEnumeration(allocator, enumeration),
            .untagged_union => |u| try outputUntaggedUnion(allocator, u),
            .import => |i| try outputImport(allocator, i),
        };

        try outputs.append(output);
    }

    return try mem.join(allocator, "\n\n", outputs.items);
}

fn outputImport(allocator: *mem.Allocator, i: Import) ![]const u8 {
    return try fmt.allocPrint(allocator, "import * as {} from \"{}\";", .{ i.alias, i.name });
}

fn outputUntaggedUnion(allocator: *mem.Allocator, u: UntaggedUnion) ![]const u8 {
    var value_union_outputs = ArrayList([]const u8).init(allocator);
    defer value_union_outputs.deinit();

    for (u.values) |value| {
        try value_union_outputs.append(translateName(value.name));
    }

    const value_union_output = try mem.join(allocator, " | ", value_union_outputs.items);
    defer allocator.free(value_union_output);

    const type_guard_output = try outputTypeGuardForUntaggedUnion(allocator, u);

    const validator_output = try outputValidatorForUntaggedUnion(allocator, u);

    const format =
        \\export type {} = {};
        \\
        \\{}
        \\
        \\{}
    ;

    return try fmt.allocPrint(
        allocator,
        format,
        .{ u.name, value_union_output, type_guard_output, validator_output },
    );
}

fn outputTypeGuardForUntaggedUnion(allocator: *mem.Allocator, u: UntaggedUnion) ![]const u8 {
    var predicate_outputs = ArrayList([]const u8).init(allocator);
    defer predicate_outputs.deinit();

    for (u.values) |value| {
        const translated_name = try translatedTypeGuardName(allocator, value.name);
        try predicate_outputs.append(translated_name);
    }

    const predicates_output = try mem.join(allocator, ", ", predicate_outputs.items);
    defer allocator.free(predicates_output);

    const format =
        \\export function is{}(value: unknown): value is {} {{
        \\    return [{}].some((typePredicate) => typePredicate(value));
        \\}}
    ;

    return try fmt.allocPrint(allocator, format, .{ u.name, u.name, predicates_output });
}

fn outputValidatorForUntaggedUnion(allocator: *mem.Allocator, u: UntaggedUnion) ![]const u8 {
    var validator_outputs = ArrayList([]const u8).init(allocator);
    defer validator_outputs.deinit();

    for (u.values) |value| {
        const translated_name = try translatedValidatorName(allocator, value.name);
        try validator_outputs.append(translated_name);
    }

    const validators_output = try mem.join(allocator, ", ", validator_outputs.items);
    defer allocator.free(validators_output);

    const format =
        \\export function validate{}(value: unknown): svt.ValidationResult<{}> {{
        \\    return svt.validateOneOf<{}>(value, [{}]);
        \\}}
    ;

    return try fmt.allocPrint(allocator, format, .{ u.name, u.name, u.name, validators_output });
}

fn outputEnumeration(allocator: *mem.Allocator, enumeration: Enumeration) ![]const u8 {
    var field_outputs = ArrayList([]const u8).init(allocator);
    defer field_outputs.deinit();

    for (enumeration.fields) |field| {
        try field_outputs.append(try outputEnumerationField(allocator, field));
    }

    const fields_output = try mem.join(allocator, "\n", field_outputs.items);
    defer allocator.free(fields_output);

    const type_guard_output = try outputEnumerationTypeGuard(
        allocator,
        enumeration.name,
        enumeration.fields,
    );

    const validator_output = try outputEnumerationValidator(
        allocator,
        enumeration.name,
        enumeration.fields,
    );

    const format =
        \\export enum {} {{
        \\{}
        \\}}
        \\
        \\{}
        \\
        \\{}
    ;

    return try fmt.allocPrint(
        allocator,
        format,
        .{ enumeration.name, fields_output, type_guard_output, validator_output },
    );
}

fn outputEnumerationTypeGuard(
    allocator: *mem.Allocator,
    name: []const u8,
    fields: []EnumerationField,
) ![]const u8 {
    var tag_outputs = ArrayList([]const u8).init(allocator);
    defer tag_outputs.deinit();

    for (fields) |field| {
        try tag_outputs.append(try fmt.allocPrint(allocator, "{}.{}", .{ name, field.tag }));
    }

    const tags_output = try mem.join(allocator, ", ", tag_outputs.items);
    defer allocator.free(tags_output);

    const format =
        \\export function is{}(value: unknown): value is {} {{
        \\    return [{}].some((v) => v === value);
        \\}}
    ;

    return try fmt.allocPrint(allocator, format, .{ name, name, tags_output });
}

fn outputEnumerationValidator(
    allocator: *mem.Allocator,
    name: []const u8,
    fields: []EnumerationField,
) ![]const u8 {
    var tag_outputs = ArrayList([]const u8).init(allocator);
    defer tag_outputs.deinit();

    for (fields) |field| {
        try tag_outputs.append(try fmt.allocPrint(
            allocator,
            "svt.validateConstant<{}.{}>({}.{})",
            .{ name, field.tag, name, field.tag },
        ));
    }

    const tags_output = try mem.join(allocator, ", ", tag_outputs.items);
    defer allocator.free(tags_output);

    const format =
        \\export function validate{}(value: unknown): svt.ValidationResult<{}> {{
        \\    return svt.validateOneOf<{}>(value, [{}]);
        \\}}
    ;

    return try fmt.allocPrint(allocator, format, .{ name, name, name, tags_output });
}

fn outputEnumerationField(allocator: *mem.Allocator, field: EnumerationField) ![]const u8 {
    const value_output = switch (field.value) {
        .string => |s| try fmt.allocPrint(allocator, "\"{}\"", .{s}),
        .unsigned_integer => |ui| try fmt.allocPrint(allocator, "{}", .{ui}),
    };
    defer allocator.free(value_output);

    const format = "    {} = {},";

    return try fmt.allocPrint(allocator, format, .{ field.tag, value_output });
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

    const union_tag_enum_output = try outputUnionTagEnumerationForConstructors(
        allocator,
        plain_union.name,
        plain_union.constructors,
    );

    const tagged_structures_output = try outputTaggedStructures(
        allocator,
        plain_union.name,
        plain_union.constructors,
        plain_union.tag_field,
    );

    const constructors_output = try outputConstructors(
        allocator,
        plain_union.name,
        plain_union.constructors,
        plain_union.tag_field,
    );

    const union_type_guard_output = try outputTypeGuardForPlainUnion(allocator, plain_union);

    const type_guards_output = try outputTypeGuardsForConstructors(
        allocator,
        plain_union.name,
        plain_union.constructors,
        &[_][]const u8{},
        plain_union.tag_field,
    );

    const union_validator_output = try outputValidatorForPlainUnion(allocator, plain_union);

    const validators_output = try outputValidatorsForConstructors(
        allocator,
        plain_union.name,
        plain_union.constructors,
        &[_][]const u8{},
        plain_union.tag_field,
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
            union_tag_enum_output,
            tagged_structures_output,
            constructors_output,
            union_type_guard_output,
            type_guards_output,
            union_validator_output,
            validators_output,
        },
    );
}

fn outputUnionTagEnumerationForConstructors(
    allocator: *mem.Allocator,
    name: []const u8,
    constructors: []Constructor,
) ![]const u8 {
    var enumeration_tag_outputs = ArrayList([]const u8).init(allocator);
    defer enumeration_tag_outputs.deinit();

    for (constructors) |constructor| {
        try enumeration_tag_outputs.append(
            try fmt.allocPrint(allocator, "    {} = \"{}\",", .{ constructor.tag, constructor.tag }),
        );
    }

    const enumeration_tag_output = try mem.join(allocator, "\n", enumeration_tag_outputs.items);
    defer allocator.free(enumeration_tag_output);

    const format =
        \\export enum {}Tag {{
        \\{}
        \\}}
    ;

    return try fmt.allocPrint(allocator, format, .{ name, enumeration_tag_output });
}

fn outputTypeGuardForPlainUnion(allocator: *mem.Allocator, plain: PlainUnion) ![]const u8 {
    var predicate_outputs = try predicatesFromConstructors(
        allocator,
        plain.constructors,
        &[_][]const u8{},
    );
    defer predicate_outputs.deinit();

    const predicates_output = try mem.join(allocator, ", ", predicate_outputs.items);

    const format =
        \\export function is{}(value: unknown): value is {} {{
        \\    return [{}].some((typePredicate) => typePredicate(value));
        \\}}
    ;

    return try fmt.allocPrint(allocator, format, .{ plain.name, plain.name, predicates_output });
}

fn outputValidatorForPlainUnion(allocator: *mem.Allocator, plain: PlainUnion) ![]const u8 {
    var validator_outputs = try validatorsFromConstructors(
        allocator,
        plain.constructors,
        &[_][]const u8{},
    );
    defer validator_outputs.deinit();

    const validators_output = try mem.join(allocator, ", ", validator_outputs.items);

    const format =
        \\export function validate{}(value: unknown): svt.ValidationResult<{}> {{
        \\    return svt.validateOneOf<{}>(value, [{}]);
        \\}}
    ;

    return try fmt.allocPrint(
        allocator,
        format,
        .{ plain.name, plain.name, plain.name, validators_output },
    );
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

    const union_tag_enum_output = try outputUnionTagEnumerationForConstructors(
        allocator,
        generic_union.name,
        generic_union.constructors,
    );

    const tagged_structures_output = try outputTaggedMaybeGenericStructures(
        allocator,
        generic_union.name,
        generic_union.constructors,
        generic_union.open_names,
        generic_union.tag_field,
    );

    const constructors_output = try outputGenericConstructors(
        allocator,
        generic_union.name,
        generic_union.constructors,
        generic_union.open_names,
        generic_union.tag_field,
    );

    const union_type_guard_output = try outputTypeGuardForGenericUnion(allocator, generic_union);

    const type_guards_output = try outputTypeGuardsForConstructors(
        allocator,
        generic_union.name,
        generic_union.constructors,
        generic_union.open_names,
        generic_union.tag_field,
    );

    const union_validator_output = try outputValidatorForGenericUnion(allocator, generic_union);

    const validators_output = try outputValidatorsForConstructors(
        allocator,
        generic_union.name,
        generic_union.constructors,
        generic_union.open_names,
        generic_union.tag_field,
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
            union_tag_enum_output,
            tagged_structures_output,
            constructors_output,
            union_type_guard_output,
            type_guards_output,
            union_validator_output,
            validators_output,
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

    var predicate_list_outputs = try predicatesFromConstructors(
        allocator,
        generic.constructors,
        generic.open_names,
    );
    defer predicate_list_outputs.deinit();

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

fn predicatesFromConstructors(
    allocator: *mem.Allocator,
    constructors: []Constructor,
    open_names: []const []const u8,
) !ArrayList([]const u8) {
    var predicate_list_outputs = ArrayList([]const u8).init(allocator);
    for (constructors) |constructor| {
        const constructor_open_names = try openNamesFromType(
            allocator,
            constructor.parameter,
            open_names,
        );
        defer constructor_open_names.deinit();
        const constructor_open_name_predicates = try openNamePredicates(
            allocator,
            constructor_open_names.items,
        );
        defer constructor_open_name_predicates.deinit();

        const titlecased_tag = try titleCaseWord(allocator, constructor.tag);

        try predicate_list_outputs.append(if (constructor_open_names.items.len > 0)
            try fmt.allocPrint(
                allocator,
                "is{}({})",
                .{
                    titlecased_tag,
                    try mem.join(allocator, ", ", constructor_open_name_predicates.items),
                },
            )
        else
            try fmt.allocPrint(allocator, "is{}", .{titlecased_tag}));
    }

    return predicate_list_outputs;
}

fn outputValidatorForGenericUnion(allocator: *mem.Allocator, generic: GenericUnion) ![]const u8 {
    const open_name_validators = try openNameValidators(allocator, generic.open_names);

    var open_name_validator_types = try allocator.alloc([]const u8, generic.open_names.len);
    for (open_name_validator_types) |*t, i| {
        t.* = try fmt.allocPrint(
            allocator,
            "svt.Validator<{}>",
            .{generic.open_names[i]},
        );
    }
    defer allocator.free(open_name_validator_types);

    var parameter_outputs = try allocator.alloc([]const u8, generic.open_names.len);
    defer allocator.free(parameter_outputs);
    for (parameter_outputs) |*o, i| {
        o.* = try fmt.allocPrint(
            allocator,
            "{}: {}",
            .{ open_name_validators.items[i], open_name_validator_types[i] },
        );
    }

    const parameters_output = try mem.join(allocator, ", ", parameter_outputs);

    const open_names_output = try fmt.allocPrint(
        allocator,
        "{}",
        .{try mem.join(allocator, ", ", generic.open_names)},
    );

    var validator_list_outputs = try validatorsFromConstructors(
        allocator,
        generic.constructors,
        generic.open_names,
    );
    defer validator_list_outputs.deinit();

    const validators_output = try mem.join(allocator, ", ", validator_list_outputs.items);

    const joined_open_names = try mem.join(allocator, "", generic.open_names);

    const format =
        \\export function validate{}<{}>({}): svt.Validator<{}<{}>> {{
        \\    return function validate{}{}(value: unknown): svt.ValidationResult<{}<{}>> {{
        \\        return svt.validateOneOf<{}<{}>>(value, [{}]);
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
            generic.name,
            open_names_output,
            validators_output,
        },
    );
}

fn validatorsFromConstructors(
    allocator: *mem.Allocator,
    constructors: []Constructor,
    open_names: []const []const u8,
) !ArrayList([]const u8) {
    var validator_list_outputs = ArrayList([]const u8).init(allocator);
    for (constructors) |constructor| {
        const constructor_open_names = try openNamesFromType(
            allocator,
            constructor.parameter,
            open_names,
        );
        defer constructor_open_names.deinit();
        const constructor_open_name_validators = try openNameValidators(
            allocator,
            constructor_open_names.items,
        );
        defer constructor_open_name_validators.deinit();

        const titlecased_tag = try titleCaseWord(allocator, constructor.tag);

        try validator_list_outputs.append(if (constructor_open_names.items.len > 0)
            try fmt.allocPrint(
                allocator,
                "validate{}({})",
                .{
                    titlecased_tag,
                    try mem.join(allocator, ", ", constructor_open_name_validators.items),
                },
            )
        else
            try fmt.allocPrint(allocator, "validate{}", .{titlecased_tag}));
    }

    return validator_list_outputs;
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
        \\        return svt.isInterface<{}<{}>>(value, {{{}}});
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
    union_name: []const u8,
    constructors: []Constructor,
    tag_field: []const u8,
) ![]const u8 {
    var constructor_outputs = ArrayList([]const u8).init(allocator);
    defer constructor_outputs.deinit();

    for (constructors) |constructor| {
        try constructor_outputs.append(try outputConstructor(
            allocator,
            union_name,
            constructor,
            &[_][]const u8{},
            tag_field,
        ));
    }

    return try mem.join(allocator, "\n\n", constructor_outputs.items);
}

fn outputTypeGuardsForConstructors(
    allocator: *mem.Allocator,
    union_name: []const u8,
    constructors: []Constructor,
    open_names: []const []const u8,
    tag_field: []const u8,
) ![]const u8 {
    var type_guards = ArrayList([]const u8).init(allocator);
    defer type_guards.deinit();

    for (constructors) |constructor| {
        try type_guards.append(
            try outputTypeGuardForConstructor(
                allocator,
                union_name,
                constructor,
                open_names,
                tag_field,
            ),
        );
    }

    return try mem.join(allocator, "\n\n", type_guards.items);
}

fn outputValidatorsForConstructors(
    allocator: *mem.Allocator,
    union_name: []const u8,
    constructors: []Constructor,
    open_names: []const []const u8,
    tag_field: []const u8,
) ![]const u8 {
    var validators = ArrayList([]const u8).init(allocator);
    defer validators.deinit();

    for (constructors) |constructor| {
        try validators.append(try outputValidatorForConstructor(
            allocator,
            union_name,
            constructor,
            open_names,
            tag_field,
        ));
    }

    return try mem.join(allocator, "\n\n", validators.items);
}

fn outputConstructor(
    allocator: *mem.Allocator,
    union_name: []const u8,
    constructor: Constructor,
    open_names: []const []const u8,
    tag_field: []const u8,
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

    const enumeration_tag_output = try outputEnumerationTag(allocator, union_name, constructor.tag);
    defer allocator.free(enumeration_tag_output);

    const output_format_with_data =
        \\export function {}{}(data: {}): {}{} {{
        \\    return {{{}: {}, data}};
        \\}}
    ;

    const output_format_without_data =
        \\export function {}(): {} {{
        \\    return {{{}: {}}};
        \\}}
    ;

    return if (data_specification) |specification|
        try fmt.allocPrint(
            allocator,
            output_format_with_data,
            .{
                tag,
                open_names_output,
                specification,
                tag,
                open_names_output,
                tag_field,
                enumeration_tag_output,
            },
        )
    else
        try fmt.allocPrint(
            allocator,
            output_format_without_data,
            .{ tag, tag, tag_field, enumeration_tag_output },
        );
}

fn outputEnumerationTag(
    allocator: *mem.Allocator,
    union_name: []const u8,
    tag: []const u8,
) ![]const u8 {
    return try fmt.allocPrint(allocator, "{}Tag.{}", .{ union_name, tag });
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
    union_name: []const u8,
    constructor: Constructor,
    open_names: []const []const u8,
    tag_field: []const u8,
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

    const enumeration_tag_output = try outputEnumerationTag(allocator, union_name, constructor.tag);

    const type_guard_output = try getDataTypeGuardFromType(allocator, constructor.parameter);

    const titlecased_tag = try titleCaseWord(allocator, tag);

    const output_format_with_open_names =
        \\export function is{}{}({}): svt.TypePredicate<{}{}> {{
        \\    return function is{}{}(value: unknown): value is {}{} {{
        \\        return svt.isInterface<{}{}>(value, {{{}: {}{}}});
        \\    }};
        \\}}
    ;

    const output_format_without_open_names =
        \\export function is{}(value: unknown): value is {} {{
        \\    return svt.isInterface<{}>(value, {{{}: {}{}}});
        \\}}
    ;

    return if (constructor_open_names.items.len > 0)
        try fmt.allocPrint(
            allocator,
            output_format_with_open_names,
            .{
                titlecased_tag,
                open_names_output,
                parameters_output,
                tag,
                open_names_output,
                titlecased_tag,
                try mem.join(allocator, "", constructor_open_names.items),
                tag,
                open_names_output,
                tag,
                open_names_output,
                tag_field,
                enumeration_tag_output,
                type_guard_output,
            },
        )
    else
        try fmt.allocPrint(
            allocator,
            output_format_without_open_names,
            .{ titlecased_tag, tag, tag, tag_field, enumeration_tag_output, type_guard_output },
        );
}

fn outputValidatorForConstructor(
    allocator: *mem.Allocator,
    union_name: []const u8,
    constructor: Constructor,
    open_names: []const []const u8,
    tag_field: []const u8,
) ![]const u8 {
    const tag = constructor.tag;

    const constructor_open_names = try openNamesFromType(
        allocator,
        constructor.parameter,
        open_names,
    );
    const open_names_validators = try openNameValidators(allocator, constructor_open_names.items);
    defer open_names_validators.deinit();
    const open_names_predicates_output = try mem.join(allocator, ", ", open_names_validators.items);

    const open_names_output = try mem.join(allocator, ", ", constructor_open_names.items);
    defer allocator.free(open_names_output);

    const joined_open_names = try mem.join(allocator, "", constructor_open_names.items);
    defer allocator.free(joined_open_names);

    var open_name_validator_types = try allocator.alloc(
        []const u8,
        constructor_open_names.items.len,
    );
    for (open_name_validator_types) |*t, i| {
        t.* = try fmt.allocPrint(
            allocator,
            "svt.Validator<{}>",
            .{constructor_open_names.items[i]},
        );
    }
    defer allocator.free(open_name_validator_types);

    var parameter_outputs = try allocator.alloc([]const u8, constructor_open_names.items.len);
    defer allocator.free(parameter_outputs);
    for (parameter_outputs) |*o, i| {
        o.* = try fmt.allocPrint(
            allocator,
            "{}: {}",
            .{ open_names_validators.items[i], open_name_validator_types[i] },
        );
    }

    const parameters_output = try mem.join(allocator, ", ", parameter_outputs);
    defer allocator.free(parameters_output);

    const union_enum_tag_output = try outputEnumerationTag(allocator, union_name, constructor.tag);

    const validator_output = try getDataValidatorFromType(allocator, constructor.parameter);

    const titlecased_tag = try titleCaseWord(allocator, constructor.tag);

    const format_without_open_names =
        \\export function validate{}(value: unknown): svt.ValidationResult<{}> {{
        \\    return svt.validate<{}>(value, {{{}: {}{}}});
        \\}}
    ;

    const format_with_open_names =
        \\export function validate{}<{}>({}): svt.Validator<{}<{}>> {{
        \\    return function validate{}{}(value: unknown): svt.ValidationResult<{}<{}>> {{
        \\        return svt.validate<{}<{}>>(value, {{{}: {}{}}});
        \\    }};
        \\}}
    ;

    return if (constructor_open_names.items.len == 0)
        try fmt.allocPrint(
            allocator,
            format_without_open_names,
            .{ titlecased_tag, tag, tag, tag_field, union_enum_tag_output, validator_output },
        )
    else
        try fmt.allocPrint(
            allocator,
            format_with_open_names,
            .{
                titlecased_tag,
                open_names_output,
                parameters_output,
                tag,
                open_names_output,
                titlecased_tag,
                joined_open_names,
                tag,
                open_names_output,
                tag,
                open_names_output,
                tag_field,
                union_enum_tag_output,
                validator_output,
            },
        );
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
        .applied_name => |applied| applied: {
            const open_name_validators = try openNameValidators(allocator, applied.open_names);
            defer open_name_validators.deinit();

            break :applied try fmt.allocPrint(
                allocator,
                ", data: validate{}({})",
                .{ applied.name, try mem.join(allocator, ", ", open_name_validators.items) },
            );
        },
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
        .applied_name => |applied| applied: {
            const open_name_validators = try openNameValidators(allocator, applied.open_names);
            defer open_name_validators.deinit();

            break :applied try fmt.allocPrint(
                allocator,
                "validate{}({})",
                .{ applied.name, try mem.join(allocator, ", ", open_name_validators.items) },
            );
        },
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

fn outputTaggedStructures(
    allocator: *mem.Allocator,
    union_name: []const u8,
    constructors: []Constructor,
    tag_field: []const u8,
) ![]const u8 {
    var tagged_structures_outputs = ArrayList([]const u8).init(allocator);
    defer tagged_structures_outputs.deinit();

    for (constructors) |constructor| {
        try tagged_structures_outputs.append(try outputTaggedStructure(
            allocator,
            union_name,
            constructor,
            tag_field,
        ));
    }

    return try mem.join(allocator, "\n\n", tagged_structures_outputs.items);
}

fn outputTaggedMaybeGenericStructures(
    allocator: *mem.Allocator,
    union_name: []const u8,
    constructors: []Constructor,
    open_names: []const []const u8,
    tag_field: []const u8,
) ![]const u8 {
    var tagged_structures_outputs = ArrayList([]const u8).init(allocator);
    defer tagged_structures_outputs.deinit();

    for (constructors) |constructor| {
        try tagged_structures_outputs.append(
            try outputTaggedMaybeGenericStructure(
                allocator,
                union_name,
                constructor,
                open_names,
                tag_field,
            ),
        );
    }

    return try mem.join(allocator, "\n\n", tagged_structures_outputs.items);
}

fn outputGenericConstructors(
    allocator: *mem.Allocator,
    union_name: []const u8,
    constructors: []Constructor,
    open_names: []const []const u8,
    tag_field: []const u8,
) ![]const u8 {
    var constructor_outputs = ArrayList([]const u8).init(allocator);
    defer constructor_outputs.deinit();

    for (constructors) |constructor| {
        try constructor_outputs.append(try outputConstructor(
            allocator,
            union_name,
            constructor,
            open_names,
            tag_field,
        ));
    }

    return try mem.join(allocator, "\n\n", constructor_outputs.items);
}

fn outputTaggedStructure(
    allocator: *mem.Allocator,
    union_name: []const u8,
    constructor: Constructor,
    tag_field: []const u8,
) ![]const u8 {
    const parameter_output = try outputType(allocator, constructor.parameter);

    const enumeration_tag_output = try outputEnumerationTag(allocator, union_name, constructor.tag);

    const output_format_with_parameter =
        \\export type {} = {{
        \\    {}: {};
        \\    data: {};
        \\}};
    ;

    const output_format_without_parameter =
        \\export type {} = {{
        \\    {}: {};
        \\}};
    ;

    return if (parameter_output) |output|
        try fmt.allocPrint(
            allocator,
            output_format_with_parameter,
            .{ constructor.tag, tag_field, enumeration_tag_output, output },
        )
    else
        try fmt.allocPrint(
            allocator,
            output_format_without_parameter,
            .{ constructor.tag, tag_field, enumeration_tag_output },
        );
}

fn outputTaggedMaybeGenericStructure(
    allocator: *mem.Allocator,
    union_name: []const u8,
    constructor: Constructor,
    open_names: []const []const u8,
    tag_field: []const u8,
) ![]const u8 {
    const open_names_output = outputOpenNamesFromType(allocator, constructor.parameter, open_names);

    const parameter_output = if (try outputType(allocator, constructor.parameter)) |output|
        try fmt.allocPrint(allocator, "\n    data: {};", .{output})
    else
        "";

    const enumeration_tag_output = try outputEnumerationTag(allocator, union_name, constructor.tag);

    const output_format =
        \\export type {}{} = {{
        \\    {}: {};{}
        \\}};
    ;

    return fmt.allocPrint(
        allocator,
        output_format,
        .{
            constructor.tag,
            open_names_output,
            tag_field,
            enumeration_tag_output,
            parameter_output,
        },
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

fn titleCaseWord(allocator: *mem.Allocator, word: []const u8) ![]const u8 {
    return fmt.allocPrint(allocator, "{c}{}", .{ std.ascii.toUpper(word[0]), word[1..] });
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
        ))[0].structure.plain,
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
        \\        return svt.isInterface<Node<T, U>>(value, {data: isT, otherData: isU});
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
        ))[0].structure.generic,
    );

    testing.expectEqualStrings(output, expected_output);
}

test "Outputs `Event` union correctly" {
    var allocator = TestingAllocator{};

    const expected_output =
        \\export type Event = LogIn | LogOut | JoinChannels | SetEmails | Close;
        \\
        \\export enum EventTag {
        \\    LogIn = "LogIn",
        \\    LogOut = "LogOut",
        \\    JoinChannels = "JoinChannels",
        \\    SetEmails = "SetEmails",
        \\    Close = "Close",
        \\}
        \\
        \\export type LogIn = {
        \\    type: EventTag.LogIn;
        \\    data: LogInData;
        \\};
        \\
        \\export type LogOut = {
        \\    type: EventTag.LogOut;
        \\    data: UserId;
        \\};
        \\
        \\export type JoinChannels = {
        \\    type: EventTag.JoinChannels;
        \\    data: Channel[];
        \\};
        \\
        \\export type SetEmails = {
        \\    type: EventTag.SetEmails;
        \\    data: Email[];
        \\};
        \\
        \\export type Close = {
        \\    type: EventTag.Close;
        \\};
        \\
        \\export function LogIn(data: LogInData): LogIn {
        \\    return {type: EventTag.LogIn, data};
        \\}
        \\
        \\export function LogOut(data: UserId): LogOut {
        \\    return {type: EventTag.LogOut, data};
        \\}
        \\
        \\export function JoinChannels(data: Channel[]): JoinChannels {
        \\    return {type: EventTag.JoinChannels, data};
        \\}
        \\
        \\export function SetEmails(data: Email[]): SetEmails {
        \\    return {type: EventTag.SetEmails, data};
        \\}
        \\
        \\export function Close(): Close {
        \\    return {type: EventTag.Close};
        \\}
        \\
        \\export function isEvent(value: unknown): value is Event {
        \\    return [isLogIn, isLogOut, isJoinChannels, isSetEmails, isClose].some((typePredicate) => typePredicate(value));
        \\}
        \\
        \\export function isLogIn(value: unknown): value is LogIn {
        \\    return svt.isInterface<LogIn>(value, {type: EventTag.LogIn, data: isLogInData});
        \\}
        \\
        \\export function isLogOut(value: unknown): value is LogOut {
        \\    return svt.isInterface<LogOut>(value, {type: EventTag.LogOut, data: isUserId});
        \\}
        \\
        \\export function isJoinChannels(value: unknown): value is JoinChannels {
        \\    return svt.isInterface<JoinChannels>(value, {type: EventTag.JoinChannels, data: svt.arrayOf(isChannel)});
        \\}
        \\
        \\export function isSetEmails(value: unknown): value is SetEmails {
        \\    return svt.isInterface<SetEmails>(value, {type: EventTag.SetEmails, data: svt.arrayOf(isEmail)});
        \\}
        \\
        \\export function isClose(value: unknown): value is Close {
        \\    return svt.isInterface<Close>(value, {type: EventTag.Close});
        \\}
        \\
        \\export function validateEvent(value: unknown): svt.ValidationResult<Event> {
        \\    return svt.validateOneOf<Event>(value, [validateLogIn, validateLogOut, validateJoinChannels, validateSetEmails, validateClose]);
        \\}
        \\
        \\export function validateLogIn(value: unknown): svt.ValidationResult<LogIn> {
        \\    return svt.validate<LogIn>(value, {type: EventTag.LogIn, data: validateLogInData});
        \\}
        \\
        \\export function validateLogOut(value: unknown): svt.ValidationResult<LogOut> {
        \\    return svt.validate<LogOut>(value, {type: EventTag.LogOut, data: validateUserId});
        \\}
        \\
        \\export function validateJoinChannels(value: unknown): svt.ValidationResult<JoinChannels> {
        \\    return svt.validate<JoinChannels>(value, {type: EventTag.JoinChannels, data: svt.validateArray(validateChannel)});
        \\}
        \\
        \\export function validateSetEmails(value: unknown): svt.ValidationResult<SetEmails> {
        \\    return svt.validate<SetEmails>(value, {type: EventTag.SetEmails, data: svt.validateArray(validateEmail)});
        \\}
        \\
        \\export function validateClose(value: unknown): svt.ValidationResult<Close> {
        \\    return svt.validate<Close>(value, {type: EventTag.Close});
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
        ))[0].@"union".plain,
    );

    testing.expectEqualStrings(output, expected_output);
}

test "Outputs `Maybe` union correctly" {
    var allocator = TestingAllocator{};

    const expected_output =
        \\export type Maybe<T> = just<T> | nothing;
        \\
        \\export enum MaybeTag {
        \\    just = "just",
        \\    nothing = "nothing",
        \\}
        \\
        \\export type just<T> = {
        \\    type: MaybeTag.just;
        \\    data: T;
        \\};
        \\
        \\export type nothing = {
        \\    type: MaybeTag.nothing;
        \\};
        \\
        \\export function just<T>(data: T): just<T> {
        \\    return {type: MaybeTag.just, data};
        \\}
        \\
        \\export function nothing(): nothing {
        \\    return {type: MaybeTag.nothing};
        \\}
        \\
        \\export function isMaybe<T>(isT: svt.TypePredicate<T>): svt.TypePredicate<Maybe<T>> {
        \\    return function isMaybeT(value: unknown): value is Maybe<T> {
        \\        return [isJust(isT), isNothing].some((typePredicate) => typePredicate(value));
        \\    };
        \\}
        \\
        \\export function isJust<T>(isT: svt.TypePredicate<T>): svt.TypePredicate<just<T>> {
        \\    return function isJustT(value: unknown): value is just<T> {
        \\        return svt.isInterface<just<T>>(value, {type: MaybeTag.just, data: isT});
        \\    };
        \\}
        \\
        \\export function isNothing(value: unknown): value is nothing {
        \\    return svt.isInterface<nothing>(value, {type: MaybeTag.nothing});
        \\}
        \\
        \\export function validateMaybe<T>(validateT: svt.Validator<T>): svt.Validator<Maybe<T>> {
        \\    return function validateMaybeT(value: unknown): svt.ValidationResult<Maybe<T>> {
        \\        return svt.validateOneOf<Maybe<T>>(value, [validateJust(validateT), validateNothing]);
        \\    };
        \\}
        \\
        \\export function validateJust<T>(validateT: svt.Validator<T>): svt.Validator<just<T>> {
        \\    return function validateJustT(value: unknown): svt.ValidationResult<just<T>> {
        \\        return svt.validate<just<T>>(value, {type: MaybeTag.just, data: validateT});
        \\    };
        \\}
        \\
        \\export function validateNothing(value: unknown): svt.ValidationResult<nothing> {
        \\    return svt.validate<nothing>(value, {type: MaybeTag.nothing});
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
        ))[0].@"union".generic,
    );

    testing.expectEqualStrings(output, expected_output);
}

test "Outputs `Either` union correctly" {
    var allocator = TestingAllocator{};

    const expected_output =
        \\export type Either<E, T> = Left<E> | Right<T>;
        \\
        \\export enum EitherTag {
        \\    Left = "Left",
        \\    Right = "Right",
        \\}
        \\
        \\export type Left<E> = {
        \\    type: EitherTag.Left;
        \\    data: E;
        \\};
        \\
        \\export type Right<T> = {
        \\    type: EitherTag.Right;
        \\    data: T;
        \\};
        \\
        \\export function Left<E>(data: E): Left<E> {
        \\    return {type: EitherTag.Left, data};
        \\}
        \\
        \\export function Right<T>(data: T): Right<T> {
        \\    return {type: EitherTag.Right, data};
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
        \\        return svt.isInterface<Left<E>>(value, {type: EitherTag.Left, data: isE});
        \\    };
        \\}
        \\
        \\export function isRight<T>(isT: svt.TypePredicate<T>): svt.TypePredicate<Right<T>> {
        \\    return function isRightT(value: unknown): value is Right<T> {
        \\        return svt.isInterface<Right<T>>(value, {type: EitherTag.Right, data: isT});
        \\    };
        \\}
        \\
        \\export function validateEither<E, T>(validateE: svt.Validator<E>, validateT: svt.Validator<T>): svt.Validator<Either<E, T>> {
        \\    return function validateEitherET(value: unknown): svt.ValidationResult<Either<E, T>> {
        \\        return svt.validateOneOf<Either<E, T>>(value, [validateLeft(validateE), validateRight(validateT)]);
        \\    };
        \\}
        \\
        \\export function validateLeft<E>(validateE: svt.Validator<E>): svt.Validator<Left<E>> {
        \\    return function validateLeftE(value: unknown): svt.ValidationResult<Left<E>> {
        \\        return svt.validate<Left<E>>(value, {type: EitherTag.Left, data: validateE});
        \\    };
        \\}
        \\
        \\export function validateRight<T>(validateT: svt.Validator<T>): svt.Validator<Right<T>> {
        \\    return function validateRightT(value: unknown): svt.ValidationResult<Right<T>> {
        \\        return svt.validate<Right<T>>(value, {type: EitherTag.Right, data: validateT});
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
        ))[0].@"union".generic,
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
        ))[0].structure.plain,
    );

    testing.expectEqualStrings(output, expected_output);
}

test "Outputs struct with different `Maybe`s correctly" {
    var allocator = TestingAllocator{};

    const expected_output =
        \\export type WithMaybe<T, E> = WithConcrete | WithGeneric<T> | WithBare<E>;
        \\
        \\export enum WithMaybeTag {
        \\    WithConcrete = "WithConcrete",
        \\    WithGeneric = "WithGeneric",
        \\    WithBare = "WithBare",
        \\}
        \\
        \\export type WithConcrete = {
        \\    type: WithMaybeTag.WithConcrete;
        \\    data: Maybe<string>;
        \\};
        \\
        \\export type WithGeneric<T> = {
        \\    type: WithMaybeTag.WithGeneric;
        \\    data: Maybe<T>;
        \\};
        \\
        \\export type WithBare<E> = {
        \\    type: WithMaybeTag.WithBare;
        \\    data: E;
        \\};
        \\
        \\export function WithConcrete(data: Maybe<string>): WithConcrete {
        \\    return {type: WithMaybeTag.WithConcrete, data};
        \\}
        \\
        \\export function WithGeneric<T>(data: Maybe<T>): WithGeneric<T> {
        \\    return {type: WithMaybeTag.WithGeneric, data};
        \\}
        \\
        \\export function WithBare<E>(data: E): WithBare<E> {
        \\    return {type: WithMaybeTag.WithBare, data};
        \\}
        \\
        \\export function isWithMaybe<T, E>(isT: svt.TypePredicate<T>, isE: svt.TypePredicate<E>): svt.TypePredicate<WithMaybe<T, E>> {
        \\    return function isWithMaybeTE(value: unknown): value is WithMaybe<T, E> {
        \\        return [isWithConcrete, isWithGeneric(isT), isWithBare(isE)].some((typePredicate) => typePredicate(value));
        \\    };
        \\}
        \\
        \\export function isWithConcrete(value: unknown): value is WithConcrete {
        \\    return svt.isInterface<WithConcrete>(value, {type: WithMaybeTag.WithConcrete, data: isMaybe(svt.isString)});
        \\}
        \\
        \\export function isWithGeneric<T>(isT: svt.TypePredicate<T>): svt.TypePredicate<WithGeneric<T>> {
        \\    return function isWithGenericT(value: unknown): value is WithGeneric<T> {
        \\        return svt.isInterface<WithGeneric<T>>(value, {type: WithMaybeTag.WithGeneric, data: isMaybe(isT)});
        \\    };
        \\}
        \\
        \\export function isWithBare<E>(isE: svt.TypePredicate<E>): svt.TypePredicate<WithBare<E>> {
        \\    return function isWithBareE(value: unknown): value is WithBare<E> {
        \\        return svt.isInterface<WithBare<E>>(value, {type: WithMaybeTag.WithBare, data: isE});
        \\    };
        \\}
        \\
        \\export function validateWithMaybe<T, E>(validateT: svt.Validator<T>, validateE: svt.Validator<E>): svt.Validator<WithMaybe<T, E>> {
        \\    return function validateWithMaybeTE(value: unknown): svt.ValidationResult<WithMaybe<T, E>> {
        \\        return svt.validateOneOf<WithMaybe<T, E>>(value, [validateWithConcrete, validateWithGeneric(validateT), validateWithBare(validateE)]);
        \\    };
        \\}
        \\
        \\export function validateWithConcrete(value: unknown): svt.ValidationResult<WithConcrete> {
        \\    return svt.validate<WithConcrete>(value, {type: WithMaybeTag.WithConcrete, data: validateMaybe(svt.validateString)});
        \\}
        \\
        \\export function validateWithGeneric<T>(validateT: svt.Validator<T>): svt.Validator<WithGeneric<T>> {
        \\    return function validateWithGenericT(value: unknown): svt.ValidationResult<WithGeneric<T>> {
        \\        return svt.validate<WithGeneric<T>>(value, {type: WithMaybeTag.WithGeneric, data: validateMaybe(validateT)});
        \\    };
        \\}
        \\
        \\export function validateWithBare<E>(validateE: svt.Validator<E>): svt.Validator<WithBare<E>> {
        \\    return function validateWithBareE(value: unknown): svt.ValidationResult<WithBare<E>> {
        \\        return svt.validate<WithBare<E>>(value, {type: WithMaybeTag.WithBare, data: validateE});
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
        ))[0].@"union".generic,
    );

    testing.expectEqualStrings(output, expected_output);
}

test "Outputs `List` union correctly" {
    var allocator = TestingAllocator{};

    const expected_output =
        \\export type List<T> = Empty | Cons<T>;
        \\
        \\export enum ListTag {
        \\    Empty = "Empty",
        \\    Cons = "Cons",
        \\}
        \\
        \\export type Empty = {
        \\    type: ListTag.Empty;
        \\};
        \\
        \\export type Cons<T> = {
        \\    type: ListTag.Cons;
        \\    data: List<T>;
        \\};
        \\
        \\export function Empty(): Empty {
        \\    return {type: ListTag.Empty};
        \\}
        \\
        \\export function Cons<T>(data: List<T>): Cons<T> {
        \\    return {type: ListTag.Cons, data};
        \\}
        \\
        \\export function isList<T>(isT: svt.TypePredicate<T>): svt.TypePredicate<List<T>> {
        \\    return function isListT(value: unknown): value is List<T> {
        \\        return [isEmpty, isCons(isT)].some((typePredicate) => typePredicate(value));
        \\    };
        \\}
        \\
        \\export function isEmpty(value: unknown): value is Empty {
        \\    return svt.isInterface<Empty>(value, {type: ListTag.Empty});
        \\}
        \\
        \\export function isCons<T>(isT: svt.TypePredicate<T>): svt.TypePredicate<Cons<T>> {
        \\    return function isConsT(value: unknown): value is Cons<T> {
        \\        return svt.isInterface<Cons<T>>(value, {type: ListTag.Cons, data: isList(isT)});
        \\    };
        \\}
        \\
        \\export function validateList<T>(validateT: svt.Validator<T>): svt.Validator<List<T>> {
        \\    return function validateListT(value: unknown): svt.ValidationResult<List<T>> {
        \\        return svt.validateOneOf<List<T>>(value, [validateEmpty, validateCons(validateT)]);
        \\    };
        \\}
        \\
        \\export function validateEmpty(value: unknown): svt.ValidationResult<Empty> {
        \\    return svt.validate<Empty>(value, {type: ListTag.Empty});
        \\}
        \\
        \\export function validateCons<T>(validateT: svt.Validator<T>): svt.Validator<Cons<T>> {
        \\    return function validateConsT(value: unknown): svt.ValidationResult<Cons<T>> {
        \\        return svt.validate<Cons<T>>(value, {type: ListTag.Cons, data: validateList(validateT)});
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
        ))[0].@"union".generic,
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
    const definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        type_examples.structure_with_optional_float,
        &expect_error,
    );

    const output = try outputPlainStructure(&allocator.allocator, definitions[0].structure.plain);

    testing.expectEqualStrings(output, expected_output);
}

test "lowercase plain union has correct output" {
    var allocator = TestingAllocator{};

    const definition_buffer =
        \\union BackdropSize {
        \\    w300
        \\    w1280
        \\    original
        \\}
    ;

    const expected_output =
        \\export type BackdropSize = w300 | w1280 | original;
        \\
        \\export enum BackdropSizeTag {
        \\    w300 = "w300",
        \\    w1280 = "w1280",
        \\    original = "original",
        \\}
        \\
        \\export type w300 = {
        \\    type: BackdropSizeTag.w300;
        \\};
        \\
        \\export type w1280 = {
        \\    type: BackdropSizeTag.w1280;
        \\};
        \\
        \\export type original = {
        \\    type: BackdropSizeTag.original;
        \\};
        \\
        \\export function w300(): w300 {
        \\    return {type: BackdropSizeTag.w300};
        \\}
        \\
        \\export function w1280(): w1280 {
        \\    return {type: BackdropSizeTag.w1280};
        \\}
        \\
        \\export function original(): original {
        \\    return {type: BackdropSizeTag.original};
        \\}
        \\
        \\export function isBackdropSize(value: unknown): value is BackdropSize {
        \\    return [isW300, isW1280, isOriginal].some((typePredicate) => typePredicate(value));
        \\}
        \\
        \\export function isW300(value: unknown): value is w300 {
        \\    return svt.isInterface<w300>(value, {type: BackdropSizeTag.w300});
        \\}
        \\
        \\export function isW1280(value: unknown): value is w1280 {
        \\    return svt.isInterface<w1280>(value, {type: BackdropSizeTag.w1280});
        \\}
        \\
        \\export function isOriginal(value: unknown): value is original {
        \\    return svt.isInterface<original>(value, {type: BackdropSizeTag.original});
        \\}
        \\
        \\export function validateBackdropSize(value: unknown): svt.ValidationResult<BackdropSize> {
        \\    return svt.validateOneOf<BackdropSize>(value, [validateW300, validateW1280, validateOriginal]);
        \\}
        \\
        \\export function validateW300(value: unknown): svt.ValidationResult<w300> {
        \\    return svt.validate<w300>(value, {type: BackdropSizeTag.w300});
        \\}
        \\
        \\export function validateW1280(value: unknown): svt.ValidationResult<w1280> {
        \\    return svt.validate<w1280>(value, {type: BackdropSizeTag.w1280});
        \\}
        \\
        \\export function validateOriginal(value: unknown): svt.ValidationResult<original> {
        \\    return svt.validate<original>(value, {type: BackdropSizeTag.original});
        \\}
    ;

    var expect_error: ExpectError = undefined;
    const definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        definition_buffer,
        &expect_error,
    );

    const output = try outputPlainUnion(&allocator.allocator, definitions[0].@"union".plain);

    testing.expectEqualStrings(output, expected_output);
}

test "basic string-based enumeration is output correctly" {
    var allocator = TestingAllocator{};

    const definition_buffer =
        \\enum BackdropSize {
        \\    w300 = "w300"
        \\    w1280 = "w1280"
        \\    original = "original"
        \\}
    ;

    const expected_output =
        \\export enum BackdropSize {
        \\    w300 = "w300",
        \\    w1280 = "w1280",
        \\    original = "original",
        \\}
        \\
        \\export function isBackdropSize(value: unknown): value is BackdropSize {
        \\    return [BackdropSize.w300, BackdropSize.w1280, BackdropSize.original].some((v) => v === value);
        \\}
        \\
        \\export function validateBackdropSize(value: unknown): svt.ValidationResult<BackdropSize> {
        \\    return svt.validateOneOf<BackdropSize>(value, [svt.validateConstant<BackdropSize.w300>(BackdropSize.w300), svt.validateConstant<BackdropSize.w1280>(BackdropSize.w1280), svt.validateConstant<BackdropSize.original>(BackdropSize.original)]);
        \\}
    ;

    var expect_error: ExpectError = undefined;
    const definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        definition_buffer,
        &expect_error,
    );

    const output = try outputEnumeration(&allocator.allocator, definitions[0].enumeration);

    testing.expectEqualStrings(output, expected_output);
}

test "Basic untagged union is output correctly" {
    var allocator = TestingAllocator{};

    const definition_buffer =
        \\untagged union KnownFor {
        \\    KnownForMovie
        \\    KnownForShow
        \\    String
        \\    F32
        \\}
    ;

    const expected_output =
        \\export type KnownFor = KnownForMovie | KnownForShow | string | number;
        \\
        \\export function isKnownFor(value: unknown): value is KnownFor {
        \\    return [isKnownForMovie, isKnownForShow, svt.isString, svt.isNumber].some((typePredicate) => typePredicate(value));
        \\}
        \\
        \\export function validateKnownFor(value: unknown): svt.ValidationResult<KnownFor> {
        \\    return svt.validateOneOf<KnownFor>(value, [validateKnownForMovie, validateKnownForShow, svt.validateString, svt.validateNumber]);
        \\}
    ;

    var expect_error: ExpectError = undefined;
    const definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        definition_buffer,
        &expect_error,
    );

    const output = try outputUntaggedUnion(&allocator.allocator, definitions[0].untagged_union);

    testing.expectEqualStrings(output, expected_output);
}

test "Tagged union with tag specifier is output correctly" {
    var allocator = TestingAllocator{};

    const definition_buffer =
        \\union(tag = kind) KnownFor {
        \\    KnownForMovie: Movie
        \\    KnownForShow: Show
        \\}
    ;

    const expected_output =
        \\export type KnownFor = KnownForMovie | KnownForShow;
        \\
        \\export enum KnownForTag {
        \\    KnownForMovie = "KnownForMovie",
        \\    KnownForShow = "KnownForShow",
        \\}
        \\
        \\export type KnownForMovie = {
        \\    kind: KnownForTag.KnownForMovie;
        \\    data: Movie;
        \\};
        \\
        \\export type KnownForShow = {
        \\    kind: KnownForTag.KnownForShow;
        \\    data: Show;
        \\};
        \\
        \\export function KnownForMovie(data: Movie): KnownForMovie {
        \\    return {kind: KnownForTag.KnownForMovie, data};
        \\}
        \\
        \\export function KnownForShow(data: Show): KnownForShow {
        \\    return {kind: KnownForTag.KnownForShow, data};
        \\}
        \\
        \\export function isKnownFor(value: unknown): value is KnownFor {
        \\    return [isKnownForMovie, isKnownForShow].some((typePredicate) => typePredicate(value));
        \\}
        \\
        \\export function isKnownForMovie(value: unknown): value is KnownForMovie {
        \\    return svt.isInterface<KnownForMovie>(value, {kind: KnownForTag.KnownForMovie, data: isMovie});
        \\}
        \\
        \\export function isKnownForShow(value: unknown): value is KnownForShow {
        \\    return svt.isInterface<KnownForShow>(value, {kind: KnownForTag.KnownForShow, data: isShow});
        \\}
        \\
        \\export function validateKnownFor(value: unknown): svt.ValidationResult<KnownFor> {
        \\    return svt.validateOneOf<KnownFor>(value, [validateKnownForMovie, validateKnownForShow]);
        \\}
        \\
        \\export function validateKnownForMovie(value: unknown): svt.ValidationResult<KnownForMovie> {
        \\    return svt.validate<KnownForMovie>(value, {kind: KnownForTag.KnownForMovie, data: validateMovie});
        \\}
        \\
        \\export function validateKnownForShow(value: unknown): svt.ValidationResult<KnownForShow> {
        \\    return svt.validate<KnownForShow>(value, {kind: KnownForTag.KnownForShow, data: validateShow});
        \\}
    ;

    var expect_error: ExpectError = undefined;
    const definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        definition_buffer,
        &expect_error,
    );

    const output = try outputPlainUnion(&allocator.allocator, definitions[0].@"union".plain);

    testing.expectEqualStrings(output, expected_output);
}

test "Tagged generic union with tag specifier is output correctly" {
    var allocator = TestingAllocator{};

    const definition_buffer =
        \\union(tag = kind) Option <T>{
        \\    Some: T
        \\    None
        \\}
    ;

    const expected_output =
        \\export type Option<T> = Some<T> | None;
        \\
        \\export enum OptionTag {
        \\    Some = "Some",
        \\    None = "None",
        \\}
        \\
        \\export type Some<T> = {
        \\    kind: OptionTag.Some;
        \\    data: T;
        \\};
        \\
        \\export type None = {
        \\    kind: OptionTag.None;
        \\};
        \\
        \\export function Some<T>(data: T): Some<T> {
        \\    return {kind: OptionTag.Some, data};
        \\}
        \\
        \\export function None(): None {
        \\    return {kind: OptionTag.None};
        \\}
        \\
        \\export function isOption<T>(isT: svt.TypePredicate<T>): svt.TypePredicate<Option<T>> {
        \\    return function isOptionT(value: unknown): value is Option<T> {
        \\        return [isSome(isT), isNone].some((typePredicate) => typePredicate(value));
        \\    };
        \\}
        \\
        \\export function isSome<T>(isT: svt.TypePredicate<T>): svt.TypePredicate<Some<T>> {
        \\    return function isSomeT(value: unknown): value is Some<T> {
        \\        return svt.isInterface<Some<T>>(value, {kind: OptionTag.Some, data: isT});
        \\    };
        \\}
        \\
        \\export function isNone(value: unknown): value is None {
        \\    return svt.isInterface<None>(value, {kind: OptionTag.None});
        \\}
        \\
        \\export function validateOption<T>(validateT: svt.Validator<T>): svt.Validator<Option<T>> {
        \\    return function validateOptionT(value: unknown): svt.ValidationResult<Option<T>> {
        \\        return svt.validateOneOf<Option<T>>(value, [validateSome(validateT), validateNone]);
        \\    };
        \\}
        \\
        \\export function validateSome<T>(validateT: svt.Validator<T>): svt.Validator<Some<T>> {
        \\    return function validateSomeT(value: unknown): svt.ValidationResult<Some<T>> {
        \\        return svt.validate<Some<T>>(value, {kind: OptionTag.Some, data: validateT});
        \\    };
        \\}
        \\
        \\export function validateNone(value: unknown): svt.ValidationResult<None> {
        \\    return svt.validate<None>(value, {kind: OptionTag.None});
        \\}
    ;

    var expect_error: ExpectError = undefined;
    const definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        definition_buffer,
        &expect_error,
    );

    const output = try outputGenericUnion(&allocator.allocator, definitions[0].@"union".generic);

    testing.expectEqualStrings(output, expected_output);
}

test "Imports are output correctly" {
    var allocator = TestingAllocator{};

    const definition_buffer =
        \\import other
        \\import sourceFile = importAlias
        \\
    ;

    const expected_output_1 =
        \\import * as other from "other";
    ;

    const expected_output_2 =
        \\import * as importAlias from "sourceFile";
    ;

    var expect_error: ExpectError = undefined;
    const definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        definition_buffer,
        &expect_error,
    );

    const output_1 = try outputImport(&allocator.allocator, definitions[0].import);

    testing.expectEqualStrings(output_1, expected_output_1);

    const output_2 = try outputImport(&allocator.allocator, definitions[1].import);

    testing.expectEqualStrings(output_2, expected_output_2);
}
