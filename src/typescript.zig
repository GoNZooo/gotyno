const std = @import("std");
const debug = std.debug;
const fmt = std.fmt;
const heap = std.heap;
const mem = std.mem;
const testing = std.testing;

const ArrayList = std.ArrayList;

const parser = @import("./freeform/parser.zig");
const general = @import("./general.zig");
const tokenizer = @import("./freeform/tokenizer.zig");
const type_examples = @import("./freeform/type_examples.zig");
const utilities = @import("./freeform/utilities.zig");
const testing_utilities = @import("./freeform/testing_utilities.zig");

const Definition = parser.Definition;
const Import = parser.Import;
const UntaggedUnion = parser.UntaggedUnion;
const UntaggedUnionValue = parser.UntaggedUnionValue;
const Enumeration = parser.Enumeration;
const EnumerationField = parser.EnumerationField;
const Structure = parser.Structure;
const PlainStructure = parser.PlainStructure;
const GenericStructure = parser.GenericStructure;
const PlainUnion = parser.PlainUnion;
const EmbeddedUnion = parser.EmbeddedUnion;
const GenericUnion = parser.GenericUnion;
const Constructor = parser.Constructor;
const ConstructorWithEmbeddedTypeTag = parser.ConstructorWithEmbeddedTypeTag;
const Type = parser.Type;
const TypeReference = parser.TypeReference;
const Field = parser.Field;
const ParsingError = parser.ParsingError;
const AppliedOpenName = parser.AppliedOpenName;

const TestingAllocator = testing_utilities.TestingAllocator;

pub fn outputFilename(allocator: *mem.Allocator, filename: []const u8) ![]const u8 {
    debug.assert(mem.endsWith(u8, filename, ".gotyno"));

    var split_iterator = mem.split(filename, ".gotyno");
    const before_extension = split_iterator.next().?;

    const only_filename = if (mem.lastIndexOf(u8, before_extension, "/")) |index|
        before_extension[(index + 1)..]
    else
        before_extension;

    return mem.join(allocator, "", &[_][]const u8{ only_filename, ".ts" });
}

pub fn compileDefinitions(allocator: *mem.Allocator, definitions: []const Definition) ![]const u8 {
    var outputs = try allocator.alloc([]const u8, definitions.len + 1);
    defer utilities.freeStringArray(allocator, outputs);

    outputs[0] = try allocator.dupe(u8, "import * as svt from \"simple-validation-tools\";");
    const prelude_definitions = 1;

    for (definitions) |definition, i| {
        outputs[i + prelude_definitions] = switch (definition) {
            .structure => |structure| switch (structure) {
                .plain => |plain| try outputPlainStructure(allocator, plain),
                .generic => |generic| try outputGenericStructure(allocator, generic),
            },
            .@"union" => |u| switch (u) {
                .plain => |plain| try outputPlainUnion(allocator, plain),
                .generic => |generic| try outputGenericUnion(allocator, generic),
                .embedded => |e| try outputEmbeddedUnion(allocator, e),
            },
            .enumeration => |enumeration| try outputEnumeration(allocator, enumeration),
            .untagged_union => |u| try outputUntaggedUnion(allocator, u),
            .import => |import| try outputImport(allocator, import),
        };
    }

    return try mem.join(allocator, "\n\n", outputs);
}

pub fn outputImport(allocator: *mem.Allocator, i: Import) ![]const u8 {
    return try fmt.allocPrint(
        allocator,
        "import * as {s} from \"./{s}\";",
        .{ i.alias, i.name.value },
    );
}

pub fn outputUntaggedUnion(allocator: *mem.Allocator, u: UntaggedUnion) ![]const u8 {
    var value_union_outputs = try allocator.alloc([]const u8, u.values.len);
    defer utilities.freeStringArray(allocator, value_union_outputs);

    for (u.values) |value, i| {
        value_union_outputs[i] = try translateReference(allocator, value.reference);
    }

    const value_union_output = try mem.join(allocator, " | ", value_union_outputs);
    defer allocator.free(value_union_output);

    const type_guard_output = try outputTypeGuardForUntaggedUnion(allocator, u);
    defer allocator.free(type_guard_output);

    const validator_output = try outputValidatorForUntaggedUnion(allocator, u);
    defer allocator.free(validator_output);

    const format =
        \\export type {s} = {s};
        \\
        \\{s}
        \\
        \\{s}
    ;

    return try fmt.allocPrint(
        allocator,
        format,
        .{ u.name.value, value_union_output, type_guard_output, validator_output },
    );
}

fn outputTypeGuardForUntaggedUnion(allocator: *mem.Allocator, u: UntaggedUnion) ![]const u8 {
    const name = u.name.value;

    var predicate_outputs = try allocator.alloc([]const u8, u.values.len);
    defer utilities.freeStringArray(allocator, predicate_outputs);

    for (u.values) |value, i| {
        predicate_outputs[i] = try translatedTypeGuardReference(allocator, value.reference);
    }

    const predicates_output = try mem.join(allocator, ", ", predicate_outputs);
    defer allocator.free(predicates_output);

    const format =
        \\export function is{s}(value: unknown): value is {s} {{
        \\    return [{s}].some((typePredicate) => typePredicate(value));
        \\}}
    ;

    return try fmt.allocPrint(allocator, format, .{ name, name, predicates_output });
}

fn outputValidatorForUntaggedUnion(allocator: *mem.Allocator, u: UntaggedUnion) ![]const u8 {
    const name = u.name.value;

    var validator_outputs = try allocator.alloc([]const u8, u.values.len);
    defer utilities.freeStringArray(allocator, validator_outputs);

    for (u.values) |value, i| {
        validator_outputs[i] = try translatedValidatorReference(allocator, value.reference);
    }

    const validators_output = try mem.join(allocator, ", ", validator_outputs);
    defer allocator.free(validators_output);

    const format =
        \\export function validate{s}(value: unknown): svt.ValidationResult<{s}> {{
        \\    return svt.validateOneOf<{s}>(value, [{s}]);
        \\}}
    ;

    return try fmt.allocPrint(allocator, format, .{ name, name, name, validators_output });
}

pub fn outputEnumeration(allocator: *mem.Allocator, enumeration: Enumeration) ![]const u8 {
    const name = enumeration.name.value;

    var field_outputs = try allocator.alloc([]const u8, enumeration.fields.len);
    defer utilities.freeStringArray(allocator, field_outputs);

    for (enumeration.fields) |field, i| {
        field_outputs[i] = try outputEnumerationField(allocator, field);
    }

    const fields_output = try mem.join(allocator, "\n", field_outputs);
    defer allocator.free(fields_output);

    const type_guard_output = try outputEnumerationTypeGuard(allocator, name, enumeration.fields);
    defer allocator.free(type_guard_output);

    const validator_output = try outputEnumerationValidator(allocator, name, enumeration.fields);
    defer allocator.free(validator_output);

    const format =
        \\export enum {s} {{
        \\{s}
        \\}}
        \\
        \\{s}
        \\
        \\{s}
    ;

    return try fmt.allocPrint(
        allocator,
        format,
        .{ name, fields_output, type_guard_output, validator_output },
    );
}

fn outputEnumerationTypeGuard(
    allocator: *mem.Allocator,
    name: []const u8,
    fields: []const EnumerationField,
) ![]const u8 {
    var tag_outputs = try allocator.alloc([]const u8, fields.len);
    defer utilities.freeStringArray(allocator, tag_outputs);

    for (fields) |field, i| {
        tag_outputs[i] = try fmt.allocPrint(allocator, "{s}.{s}", .{ name, field.tag });
    }

    const tags_output = try mem.join(allocator, ", ", tag_outputs);
    defer allocator.free(tags_output);

    const format =
        \\export function is{s}(value: unknown): value is {s} {{
        \\    return [{s}].some((v) => v === value);
        \\}}
    ;

    return try fmt.allocPrint(allocator, format, .{ name, name, tags_output });
}

fn outputEnumerationValidator(
    allocator: *mem.Allocator,
    name: []const u8,
    fields: []const EnumerationField,
) ![]const u8 {
    var tag_outputs = try allocator.alloc([]const u8, fields.len);
    defer utilities.freeStringArray(allocator, tag_outputs);

    for (fields) |field, i| {
        tag_outputs[i] = try fmt.allocPrint(allocator, "{s}.{s}", .{ name, field.tag });
    }

    const tags_output = try mem.join(allocator, ", ", tag_outputs);
    defer allocator.free(tags_output);

    const format =
        \\export function validate{s}(value: unknown): svt.ValidationResult<{s}> {{
        \\    return svt.validateOneOfLiterals<{s}>(value, [{s}]);
        \\}}
    ;

    return try fmt.allocPrint(allocator, format, .{ name, name, name, tags_output });
}

fn outputEnumerationField(allocator: *mem.Allocator, field: EnumerationField) ![]const u8 {
    const value_output = switch (field.value) {
        .string => |s| try fmt.allocPrint(allocator, "\"{s}\"", .{s}),
        .unsigned_integer => |ui| try fmt.allocPrint(allocator, "{}", .{ui}),
    };
    defer allocator.free(value_output);

    const format = "    {s} = {s},";

    return try fmt.allocPrint(allocator, format, .{ field.tag, value_output });
}

pub fn outputPlainStructure(
    allocator: *mem.Allocator,
    plain_structure: PlainStructure,
) ![]const u8 {
    const name = plain_structure.name.value;

    const fields_output = try outputStructureFields(allocator, plain_structure.fields);
    defer allocator.free(fields_output);

    const type_guards_output = try outputTypeGuardForPlainStructure(allocator, plain_structure);
    defer allocator.free(type_guards_output);

    const validator_output = try outputValidatorForPlainStructure(allocator, plain_structure);
    defer allocator.free(validator_output);

    const output_format =
        \\export type {s} = {{
        \\{s}
        \\}};
        \\
        \\{s}
        \\
        \\{s}
    ;

    return try fmt.allocPrint(
        allocator,
        output_format,
        .{ name, fields_output, type_guards_output, validator_output },
    );
}

pub fn outputGenericStructure(
    allocator: *mem.Allocator,
    generic_structure: GenericStructure,
) ![]const u8 {
    const name = generic_structure.name.value;

    const fields_output = try outputStructureFields(allocator, generic_structure.fields);
    defer allocator.free(fields_output);

    const type_guard_output = try outputTypeGuardForGenericStructure(allocator, generic_structure);
    defer allocator.free(type_guard_output);

    const validator_output = try outputValidatorForGenericStructure(allocator, generic_structure);
    defer allocator.free(validator_output);

    const open_names = try outputOpenNames(allocator, generic_structure.open_names);
    defer allocator.free(open_names);

    const output_format =
        \\export type {s}{s} = {{
        \\{s}
        \\}};
        \\
        \\{s}
        \\
        \\{s}
    ;

    return try fmt.allocPrint(
        allocator,
        output_format,
        .{
            name,
            open_names,
            fields_output,
            type_guard_output,
            validator_output,
        },
    );
}

fn outputStructureFields(allocator: *mem.Allocator, fields: []const Field) ![]const u8 {
    var lines = try allocator.alloc([]const u8, fields.len);
    defer utilities.freeStringArray(allocator, lines);

    for (fields) |field, i| {
        if (try outputType(allocator, field.@"type")) |output| {
            defer allocator.free(output);
            lines[i] = try fmt.allocPrint(allocator, "    {s}: {s};", .{ field.name, output });
        } else
            debug.panic("Empty type is not valid for struct field\n", .{});
    }

    return try mem.join(allocator, "\n", lines);
}

pub fn outputPlainUnion(allocator: *mem.Allocator, plain_union: PlainUnion) ![]const u8 {
    const name = plain_union.name.value;

    var constructor_names = try allocator.alloc([]const u8, plain_union.constructors.len);
    defer allocator.free(constructor_names);
    for (plain_union.constructors) |constructor, i| {
        constructor_names[i] = constructor.tag;
    }

    const constructor_names_output = try mem.join(allocator, " | ", constructor_names);
    defer allocator.free(constructor_names_output);

    const union_tag_enum_output = try outputUnionTagEnumerationForConstructors(
        Constructor,
        allocator,
        name,
        plain_union.constructors,
    );
    defer allocator.free(union_tag_enum_output);

    const tagged_structures_output = try outputTaggedStructures(
        allocator,
        name,
        plain_union.constructors,
        plain_union.tag_field,
    );
    defer allocator.free(tagged_structures_output);

    const constructors_output = try outputConstructors(
        allocator,
        name,
        plain_union.constructors,
        plain_union.tag_field,
    );
    defer allocator.free(constructors_output);

    const union_type_guard_output = try outputTypeGuardForPlainUnion(allocator, plain_union);
    defer allocator.free(union_type_guard_output);

    const type_guards_output = try outputTypeGuardsForConstructors(
        allocator,
        name,
        plain_union.constructors,
        &[_][]const u8{},
        plain_union.tag_field,
    );
    defer allocator.free(type_guards_output);

    const union_validator_output = try outputValidatorForPlainUnion(allocator, plain_union);
    defer allocator.free(union_validator_output);

    const validators_output = try outputValidatorsForConstructors(
        allocator,
        name,
        plain_union.constructors,
        &[_][]const u8{},
        plain_union.tag_field,
    );
    defer allocator.free(validators_output);

    const output_format =
        \\export type {s} = {s};
        \\
        \\{s}
        \\
        \\{s}
        \\
        \\{s}
        \\
        \\{s}
        \\
        \\{s}
        \\
        \\{s}
        \\
        \\{s}
    ;

    return fmt.allocPrint(
        allocator,
        output_format,
        .{
            plain_union.name.value,
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

pub fn outputEmbeddedUnion(allocator: *mem.Allocator, embedded: EmbeddedUnion) ![]const u8 {
    const name = embedded.name.value;

    const ConstructorData = struct {
        tag: []const u8,
        fields: []Field,
        structure: ?Structure,
    };

    var constructor_names = try allocator.alloc([]const u8, embedded.constructors.len);
    defer allocator.free(constructor_names);
    defer for (constructor_names) |n| allocator.free(n);
    for (embedded.constructors) |constructor, i| {
        constructor_names[i] = try allocator.dupe(u8, constructor.tag);
    }

    const constructor_names_output = try mem.join(allocator, " | ", constructor_names);
    defer allocator.free(constructor_names_output);

    const union_tag_enum_output = try outputUnionTagEnumerationForConstructors(
        ConstructorWithEmbeddedTypeTag,
        allocator,
        name,
        embedded.constructors,
    );
    defer allocator.free(union_tag_enum_output);

    var tagged_structure_outputs = try allocator.alloc([]const u8, embedded.constructors.len);
    defer utilities.freeStringArray(allocator, tagged_structure_outputs);

    var constructor_outputs = try allocator.alloc([]const u8, embedded.constructors.len);
    defer utilities.freeStringArray(allocator, constructor_outputs);

    var union_type_guards = try allocator.alloc([]const u8, embedded.constructors.len);
    defer utilities.freeStringArray(allocator, union_type_guards);

    var union_validators = try allocator.alloc([]const u8, embedded.constructors.len);
    defer utilities.freeStringArray(allocator, union_validators);

    var type_guard_outputs = try allocator.alloc([]const u8, embedded.constructors.len);
    defer utilities.freeStringArray(allocator, type_guard_outputs);

    var validator_outputs = try allocator.alloc([]const u8, embedded.constructors.len);
    defer utilities.freeStringArray(allocator, validator_outputs);

    for (embedded.constructors) |constructor, i| {
        const fields_in_structure = if (constructor.parameter) |parameter| fields: {
            switch (parameter) {
                .plain => |p| break :fields try allocator.dupe(Field, p.fields),
                .generic => |g| break :fields try allocator.dupe(Field, g.fields),
            }
        } else &[_]Field{};
        defer allocator.free(fields_in_structure);

        const enumeration_tag = try outputEnumerationTag(
            allocator,
            name,
            constructor.tag,
        );
        defer allocator.free(enumeration_tag);

        tagged_structure_outputs[i] = try outputTaggedStructureForConstructorWithEmbeddedTag(
            allocator,
            fields_in_structure,
            embedded.tag_field,
            constructor.tag,
            enumeration_tag,
        );

        constructor_outputs[i] = try outputConstructorWithEmbeddedTag(
            allocator,
            constructor.parameter,
            constructor.tag,
            embedded.tag_field,
            enumeration_tag,
        );

        const titlecased_tag = try utilities.titleCaseWord(allocator, constructor.tag);
        defer allocator.free(titlecased_tag);

        union_type_guards[i] = try fmt.allocPrint(allocator, "is{s}", .{titlecased_tag});
        union_validators[i] = try fmt.allocPrint(allocator, "validate{s}", .{titlecased_tag});

        type_guard_outputs[i] =
            try outputTypeGuardForConstructorWithEmbeddedTypeTag(
            allocator,
            fields_in_structure,
            constructor.tag,
            embedded.tag_field,
            enumeration_tag,
        );

        validator_outputs[i] =
            try outputValidatorForConstructorWithEmbeddedTypeTag(
            allocator,
            fields_in_structure,
            constructor.tag,
            embedded.tag_field,
            enumeration_tag,
        );
    }

    const tagged_structures_output = try mem.join(
        allocator,
        "\n\n",
        tagged_structure_outputs,
    );
    defer allocator.free(tagged_structures_output);

    const constructors_output = try mem.join(allocator, "\n\n", constructor_outputs);
    defer allocator.free(constructors_output);

    const joined_union_type_guards = try mem.join(allocator, ", ", union_type_guards);
    defer allocator.free(joined_union_type_guards);

    const union_type_guard_format =
        \\export function is{s}(value: unknown): value is {s} {{
        \\    return [{s}].some((typePredicate) => typePredicate(value));
        \\}}
    ;
    const union_type_guard_output = try fmt.allocPrint(
        allocator,
        union_type_guard_format,
        .{ name, name, joined_union_type_guards },
    );
    defer allocator.free(union_type_guard_output);

    const type_guards_output = try mem.join(allocator, "\n\n", type_guard_outputs);
    defer allocator.free(type_guards_output);

    const validator_specification_output = try outputValidatorSpecificationForEmbeddedUnion(
        allocator,
        embedded,
        embedded.open_names,
    );
    defer allocator.free(validator_specification_output);

    const union_validator_format =
        \\export function validate{s}(value: unknown): svt.ValidationResult<{s}> {{
        \\    return svt.validateWithTypeTag<{s}>(value, {s}, "{s}");
        \\}}
    ;

    const union_validator_output = try fmt.allocPrint(
        allocator,
        union_validator_format,
        .{ name, name, name, validator_specification_output, embedded.tag_field },
    );
    defer allocator.free(union_validator_output);

    const validators_output = try mem.join(allocator, "\n\n", validator_outputs);
    defer allocator.free(validators_output);

    const output_format =
        \\export type {s} = {s};
        \\
        \\{s}
        \\
        \\{s}
        \\
        \\{s}
        \\
        \\{s}
        \\
        \\{s}
        \\
        \\{s}
        \\
        \\{s}
    ;

    return fmt.allocPrint(
        allocator,
        output_format,
        .{
            name,
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

fn outputConstructorWithEmbeddedTag(
    allocator: *mem.Allocator,
    parameter: ?Structure,
    tag: []const u8,
    tag_field: []const u8,
    enumeration_tag: []const u8,
) ![]const u8 {
    const constructor_format_with_payload =
        \\export function {s}(data: {s}): {s} {{
        \\    return {{{s}: {s}, ...data}};
        \\}}
    ;
    const constructor_format_without_payload =
        \\export function {s}(): {s} {{
        \\    return {{{s}: {s}}};
        \\}}
    ;

    return if (parameter) |p|
        try fmt.allocPrint(
            allocator,
            constructor_format_with_payload,
            .{ tag, p.name().value, tag, tag_field, enumeration_tag },
        )
    else
        try fmt.allocPrint(
            allocator,
            constructor_format_without_payload,
            .{ tag, tag, tag_field, enumeration_tag },
        );
}

fn outputTaggedStructureForConstructorWithEmbeddedTag(
    allocator: *mem.Allocator,
    fields_in_structure: []Field,
    tag_field: []const u8,
    tag: []const u8,
    enumeration_tag: []const u8,
) ![]const u8 {
    const tagged_structure_output_with_payload =
        \\export type {s} = {{
        \\    {s}: {s};
        \\{s}
        \\}};
    ;
    const tagged_structure_output_without_payload =
        \\export type {s} = {{
        \\    {s}: {s};
        \\}};
    ;

    const structure_fields = try outputStructureFields(allocator, fields_in_structure);
    defer allocator.free(structure_fields);

    return if (fields_in_structure.len != 0)
        try fmt.allocPrint(
            allocator,
            tagged_structure_output_with_payload,
            .{ tag, tag_field, enumeration_tag, structure_fields },
        )
    else
        try fmt.allocPrint(
            allocator,
            tagged_structure_output_without_payload,
            .{ tag, tag_field, enumeration_tag },
        );
}

fn outputUnionTagEnumerationForConstructors(
    comptime T: type,
    allocator: *mem.Allocator,
    name: []const u8,
    constructors: []const T,
) ![]const u8 {
    var enumeration_tag_outputs = try allocator.alloc([]const u8, constructors.len);
    defer utilities.freeStringArray(allocator, enumeration_tag_outputs);

    for (constructors) |constructor, i| {
        enumeration_tag_outputs[i] = try fmt.allocPrint(
            allocator,
            "    {s} = \"{s}\",",
            .{ constructor.tag, constructor.tag },
        );
    }

    const enumeration_tag_output = try mem.join(allocator, "\n", enumeration_tag_outputs);
    defer allocator.free(enumeration_tag_output);

    const format =
        \\export enum {s}Tag {{
        \\{s}
        \\}}
    ;

    return try fmt.allocPrint(allocator, format, .{ name, enumeration_tag_output });
}

fn outputTypeGuardForPlainUnion(allocator: *mem.Allocator, plain: PlainUnion) ![]const u8 {
    const name = plain.name.value;

    var predicate_outputs = try predicatesFromConstructors(
        allocator,
        plain.constructors,
        &[_][]const u8{},
    );
    defer utilities.freeStringArray(allocator, predicate_outputs);

    const predicates_output = try mem.join(allocator, ", ", predicate_outputs);
    defer allocator.free(predicates_output);

    const format =
        \\export function is{s}(value: unknown): value is {s} {{
        \\    return [{s}].some((typePredicate) => typePredicate(value));
        \\}}
    ;

    return try fmt.allocPrint(allocator, format, .{ name, name, predicates_output });
}

fn outputValidatorForPlainUnion(allocator: *mem.Allocator, plain: PlainUnion) ![]const u8 {
    const name = plain.name.value;

    const validator_specification_output = try outputValidatorSpecification(
        allocator,
        plain.name.value,
        plain.constructors,
        &[_][]const u8{},
    );
    defer allocator.free(validator_specification_output);

    const format =
        \\export function validate{s}(value: unknown): svt.ValidationResult<{s}> {{
        \\    return svt.validateWithTypeTag<{s}>(value, {s}, "{s}");
        \\}}
    ;

    return try fmt.allocPrint(
        allocator,
        format,
        .{ name, name, name, validator_specification_output, plain.tag_field },
    );
}

fn outputValidatorSpecification(
    allocator: *mem.Allocator,
    name: []const u8,
    constructors: []const Constructor,
    open_names: []const []const u8,
) ![]const u8 {
    var entries = try allocator.alloc([]const u8, constructors.len);
    defer utilities.freeStringArray(allocator, entries);

    for (constructors) |c, i| {
        const enumeration_tag = try outputEnumerationTag(allocator, name, c.tag);
        defer allocator.free(enumeration_tag);

        const titlecased_tag = try utilities.titleCaseWord(allocator, c.tag);
        defer allocator.free(titlecased_tag);
        const payload_validator = try validatorFromConstructor(allocator, c, open_names);
        defer allocator.free(payload_validator);

        entries[i] = try fmt.allocPrint(
            allocator,
            "[{s}]: {s}",
            .{ enumeration_tag, payload_validator },
        );
    }

    const joined_validators = try mem.join(allocator, ", ", entries);
    defer allocator.free(joined_validators);

    return try fmt.allocPrint(allocator, "{{{s}}}", .{joined_validators});
}

fn outputValidatorSpecificationForEmbeddedUnion(
    allocator: *mem.Allocator,
    e: EmbeddedUnion,
    open_names: []const []const u8,
) ![]const u8 {
    var entries = try allocator.alloc([]const u8, e.constructors.len);
    defer utilities.freeStringArray(allocator, entries);

    for (e.constructors) |c, i| {
        const enumeration_tag = try outputEnumerationTag(allocator, e.name.value, c.tag);
        defer allocator.free(enumeration_tag);

        const titlecased_tag = try utilities.titleCaseWord(allocator, c.tag);
        defer allocator.free(titlecased_tag);
        const payload_validator = try fmt.allocPrint(allocator, "validate{s}", .{titlecased_tag});
        defer allocator.free(payload_validator);

        entries[i] = try fmt.allocPrint(
            allocator,
            "[{s}]: {s}",
            .{ enumeration_tag, payload_validator },
        );
    }

    const joined_validators = try mem.join(allocator, ", ", entries);
    defer allocator.free(joined_validators);

    return try fmt.allocPrint(allocator, "{{{s}}}", .{joined_validators});
}

pub fn outputGenericUnion(allocator: *mem.Allocator, generic_union: GenericUnion) ![]const u8 {
    const name = generic_union.name.value;

    const open_names = try outputOpenNames(allocator, generic_union.open_names);
    defer allocator.free(open_names);

    var constructor_names = try allocator.alloc([]const u8, generic_union.constructors.len);
    defer allocator.free(constructor_names);
    defer for (constructor_names) |n| allocator.free(n);
    for (generic_union.constructors) |constructor, i| {
        const maybe_names = try outputOpenNamesFromType(
            allocator,
            constructor.parameter,
            generic_union.open_names,
        );
        defer allocator.free(maybe_names);

        constructor_names[i] = try fmt.allocPrint(
            allocator,
            "{s}{s}",
            .{ constructor.tag, maybe_names },
        );
    }

    const constructor_names_output = try mem.join(allocator, " | ", constructor_names);
    defer allocator.free(constructor_names_output);

    const union_tag_enum_output = try outputUnionTagEnumerationForConstructors(
        Constructor,
        allocator,
        name,
        generic_union.constructors,
    );
    defer allocator.free(union_tag_enum_output);

    const tagged_structures_output = try outputTaggedMaybeGenericStructures(
        allocator,
        name,
        generic_union.constructors,
        generic_union.open_names,
        generic_union.tag_field,
    );
    defer allocator.free(tagged_structures_output);

    const constructors_output = try outputGenericConstructors(
        allocator,
        name,
        generic_union.constructors,
        generic_union.open_names,
        generic_union.tag_field,
    );
    defer allocator.free(constructors_output);

    const union_type_guard_output = try outputTypeGuardForGenericUnion(allocator, generic_union);
    defer allocator.free(union_type_guard_output);

    const type_guards_output = try outputTypeGuardsForConstructors(
        allocator,
        name,
        generic_union.constructors,
        generic_union.open_names,
        generic_union.tag_field,
    );
    defer allocator.free(type_guards_output);

    const union_validator_output = try outputValidatorForGenericUnion(allocator, generic_union);
    defer allocator.free(union_validator_output);

    const validators_output = try outputValidatorsForConstructors(
        allocator,
        name,
        generic_union.constructors,
        generic_union.open_names,
        generic_union.tag_field,
    );
    defer allocator.free(validators_output);

    const output_format =
        \\export type {s}{s} = {s};
        \\
        \\{s}
        \\
        \\{s}
        \\
        \\{s}
        \\
        \\{s}
        \\
        \\{s}
        \\
        \\{s}
        \\
        \\{s}
    ;

    return fmt.allocPrint(
        allocator,
        output_format,
        .{
            name,
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
    const name = plain_structure.name.value;

    const checkers_output = try getTypeGuardsFromFields(allocator, plain_structure.fields);
    defer allocator.free(checkers_output);

    const output_format =
        \\export function is{s}(value: unknown): value is {s} {{
        \\    return svt.isInterface<{s}>(value, {{{s}}});
        \\}}
    ;

    return try fmt.allocPrint(
        allocator,
        output_format,
        .{ name, name, name, checkers_output },
    );
}

fn outputTypeGuardForGenericUnion(allocator: *mem.Allocator, generic: GenericUnion) ![]const u8 {
    const name = generic.name.value;

    const open_names_predicates = try openNamePredicates(allocator, generic.open_names);
    defer utilities.freeStringArray(allocator, open_names_predicates);

    var open_name_predicate_types = try allocator.alloc([]const u8, generic.open_names.len);
    defer allocator.free(open_name_predicate_types);
    defer for (open_name_predicate_types) |t| allocator.free(t);
    for (open_name_predicate_types) |*t, i| {
        t.* = try fmt.allocPrint(
            allocator,
            "svt.TypePredicate<{s}>",
            .{generic.open_names[i]},
        );
    }

    var parameter_outputs = try allocator.alloc([]const u8, generic.open_names.len);
    defer allocator.free(parameter_outputs);
    defer for (parameter_outputs) |o| allocator.free(o);
    for (parameter_outputs) |*o, i| {
        o.* = try fmt.allocPrint(
            allocator,
            "{s}: {s}",
            .{ open_names_predicates[i], open_name_predicate_types[i] },
        );
    }

    const parameters_output = try mem.join(allocator, ", ", parameter_outputs);
    defer allocator.free(parameters_output);

    const open_names_output = try mem.join(allocator, ", ", generic.open_names);
    defer allocator.free(open_names_output);

    var predicate_list_outputs = try predicatesFromConstructors(
        allocator,
        generic.constructors,
        generic.open_names,
    );
    defer utilities.freeStringArray(allocator, predicate_list_outputs);

    const predicates_output = try mem.join(allocator, ", ", predicate_list_outputs);
    defer allocator.free(predicates_output);

    const joined_open_names = try mem.join(allocator, "", generic.open_names);
    defer allocator.free(joined_open_names);

    const format =
        \\export function is{s}<{s}>({s}): svt.TypePredicate<{s}<{s}>> {{
        \\    return function is{s}{s}(value: unknown): value is {s}<{s}> {{
        \\        return [{s}].some((typePredicate) => typePredicate(value));
        \\    }};
        \\}}
    ;

    return try fmt.allocPrint(
        allocator,
        format,
        .{
            name,
            open_names_output,
            parameters_output,
            name,
            open_names_output,
            name,
            joined_open_names,
            name,
            open_names_output,
            predicates_output,
        },
    );
}

fn predicatesFromConstructors(
    allocator: *mem.Allocator,
    constructors: []const Constructor,
    open_names: []const []const u8,
) ![]const []const u8 {
    var predicate_list_outputs = try allocator.alloc([]const u8, constructors.len);

    for (constructors) |constructor, i| {
        const constructor_open_names = try general.openNamesFromType(
            allocator,
            constructor.parameter,
            open_names,
        );
        defer utilities.freeStringList(constructor_open_names);

        const constructor_open_name_predicates = try openNamePredicates(
            allocator,
            constructor_open_names.items,
        );
        defer utilities.freeStringArray(allocator, constructor_open_name_predicates);

        const titlecased_tag = try utilities.titleCaseWord(allocator, constructor.tag);
        defer allocator.free(titlecased_tag);

        const joined_predicates = try mem.join(
            allocator,
            ", ",
            constructor_open_name_predicates,
        );
        defer allocator.free(joined_predicates);

        const output = if (constructor_open_names.items.len > 0)
            try fmt.allocPrint(
                allocator,
                "is{s}({s})",
                .{ titlecased_tag, joined_predicates },
            )
        else
            try fmt.allocPrint(allocator, "is{s}", .{titlecased_tag});

        predicate_list_outputs[i] = output;
    }

    return predicate_list_outputs;
}

fn outputValidatorForGenericUnion(allocator: *mem.Allocator, generic: GenericUnion) ![]const u8 {
    const name = generic.name.value;

    const open_name_validators = try openNameValidators(allocator, generic.open_names);
    defer utilities.freeStringArray(allocator, open_name_validators);

    var open_name_validator_types = try allocator.alloc([]const u8, generic.open_names.len);
    defer allocator.free(open_name_validator_types);
    defer for (open_name_validator_types) |t| allocator.free(t);
    for (open_name_validator_types) |*t, i| {
        t.* = try fmt.allocPrint(
            allocator,
            "svt.Validator<{s}>",
            .{generic.open_names[i]},
        );
    }

    var parameter_outputs = try allocator.alloc([]const u8, generic.open_names.len);
    defer allocator.free(parameter_outputs);
    defer for (parameter_outputs) |o| allocator.free(o);
    for (parameter_outputs) |*o, i| {
        o.* = try fmt.allocPrint(
            allocator,
            "{s}: {s}",
            .{ open_name_validators[i], open_name_validator_types[i] },
        );
    }

    const parameters_output = try mem.join(allocator, ", ", parameter_outputs);
    defer allocator.free(parameters_output);

    const joined_open_names_with_comma = try mem.join(allocator, ", ", generic.open_names);
    defer allocator.free(joined_open_names_with_comma);

    const open_names_output = try fmt.allocPrint(allocator, "{s}", .{joined_open_names_with_comma});
    defer allocator.free(open_names_output);

    const validator_specification_output = try outputValidatorSpecification(
        allocator,
        generic.name.value,
        generic.constructors,
        generic.open_names,
    );
    defer allocator.free(validator_specification_output);

    const joined_open_names = try mem.join(allocator, "", generic.open_names);
    defer allocator.free(joined_open_names);

    const format =
        \\export function validate{s}<{s}>({s}): svt.Validator<{s}<{s}>> {{
        \\    return function validate{s}{s}(value: unknown): svt.ValidationResult<{s}<{s}>> {{
        \\        return svt.validateWithTypeTag<{s}<{s}>>(value, {s}, "{s}");
        \\    }};
        \\}}
    ;

    return try fmt.allocPrint(
        allocator,
        format,
        .{
            name,
            open_names_output,
            parameters_output,
            name,
            open_names_output,
            name,
            joined_open_names,
            name,
            open_names_output,
            name,
            open_names_output,
            validator_specification_output,
            generic.tag_field,
        },
    );
}

fn validatorsFromConstructors(
    allocator: *mem.Allocator,
    constructors: []const Constructor,
    open_names: []const []const u8,
) ![]const []const u8 {
    var outputs = try allocator.alloc([]const u8, constructors.len);

    for (constructors) |constructor, i| {
        outputs[i] = try validatorFromConstructor(allocator, constructor, open_names);
    }

    return outputs;
}

fn validatorFromConstructor(
    allocator: *mem.Allocator,
    constructor: Constructor,
    open_names: []const []const u8,
) ![]const u8 {
    const constructor_open_names = try general.openNamesFromType(
        allocator,
        constructor.parameter,
        open_names,
    );
    defer utilities.freeStringList(constructor_open_names);

    const has_open_names = constructor_open_names.items.len > 0;

    const constructor_open_name_validators = try openNameValidators(
        allocator,
        constructor_open_names.items,
    );
    defer utilities.freeStringArray(allocator, constructor_open_name_validators);

    const titlecased_tag = try utilities.titleCaseWord(allocator, constructor.tag);
    defer allocator.free(titlecased_tag);

    const joined_validators = try mem.join(
        allocator,
        ", ",
        constructor_open_name_validators,
    );
    defer allocator.free(joined_validators);

    return if (has_open_names)
        try fmt.allocPrint(allocator, "validate{s}({s})", .{ titlecased_tag, joined_validators })
    else
        try fmt.allocPrint(allocator, "validate{s}", .{titlecased_tag});
}

fn outputTypeGuardForGenericStructure(
    allocator: *mem.Allocator,
    generic: GenericStructure,
) ![]const u8 {
    const name = generic.name.value;

    const open_names = try actualOpenNames(allocator, generic.open_names);
    defer utilities.freeStringList(open_names);

    const open_names_output = try mem.join(allocator, ", ", open_names.items);
    defer allocator.free(open_names_output);

    const open_names_together = try mem.join(allocator, "", open_names.items);
    defer allocator.free(open_names_together);

    const open_names_predicates = try openNamePredicates(allocator, open_names.items);
    defer utilities.freeStringArray(allocator, open_names_predicates);

    const open_names_predicates_output = try mem.join(allocator, ", ", open_names_predicates);
    defer allocator.free(open_names_predicates_output);

    var open_name_predicate_types = try allocator.alloc([]const u8, open_names.items.len);
    defer allocator.free(open_name_predicate_types);
    defer for (open_name_predicate_types) |t| allocator.free(t);
    for (open_name_predicate_types) |*t, i| {
        t.* = try fmt.allocPrint(allocator, "svt.TypePredicate<{s}>", .{open_names.items[i]});
    }

    var parameter_outputs = try allocator.alloc([]const u8, open_names.items.len);
    defer allocator.free(parameter_outputs);
    defer for (parameter_outputs) |o| allocator.free(o);
    for (parameter_outputs) |*o, i| {
        o.* = try fmt.allocPrint(
            allocator,
            "{s}: {s}",
            .{ open_names_predicates[i], open_name_predicate_types[i] },
        );
    }

    const parameters_output = try mem.join(allocator, ", ", parameter_outputs);
    defer allocator.free(parameters_output);

    const fields_output = try getTypeGuardsFromFields(allocator, generic.fields);
    defer allocator.free(fields_output);

    const format_with_open_names =
        \\export function is{s}<{s}>({s}): svt.TypePredicate<{s}<{s}>> {{
        \\    return function is{s}{s}(value: unknown): value is {s}<{s}> {{
        \\        return svt.isInterface<{s}<{s}>>(value, {{{s}}});
        \\    }};
        \\}}
    ;

    return try fmt.allocPrint(
        allocator,
        format_with_open_names,
        .{
            name,
            open_names_output,
            parameters_output,
            name,
            open_names_output,
            name,
            open_names_together,
            name,
            open_names_output,
            name,
            open_names_output,
            fields_output,
        },
    );
}

fn outputValidatorForGenericStructure(
    allocator: *mem.Allocator,
    generic: GenericStructure,
) ![]const u8 {
    const name = generic.name.value;

    const open_names = try actualOpenNames(allocator, generic.open_names);
    defer utilities.freeStringList(open_names);

    const open_names_output = try mem.join(allocator, ", ", open_names.items);
    defer allocator.free(open_names_output);

    const open_names_together = try mem.join(allocator, "", open_names.items);
    defer allocator.free(open_names_together);

    const open_names_validators = try openNameValidators(allocator, open_names.items);
    defer utilities.freeStringArray(allocator, open_names_validators);

    const open_names_predicates_output = try mem.join(allocator, ", ", open_names_validators);
    defer allocator.free(open_names_predicates_output);

    var open_name_validator_types = try allocator.alloc([]const u8, open_names.items.len);
    defer allocator.free(open_name_validator_types);
    defer for (open_name_validator_types) |t| allocator.free(t);
    for (open_name_validator_types) |*t, i| {
        t.* = try fmt.allocPrint(allocator, "svt.Validator<{s}>", .{open_names.items[i]});
    }

    var parameter_outputs = try allocator.alloc([]const u8, open_names.items.len);
    defer allocator.free(parameter_outputs);
    defer for (parameter_outputs) |o| allocator.free(o);
    for (parameter_outputs) |*o, i| {
        o.* = try fmt.allocPrint(
            allocator,
            "{s}: {s}",
            .{ open_names_validators[i], open_name_validator_types[i] },
        );
    }

    const parameters_output = try mem.join(allocator, ", ", parameter_outputs);
    defer allocator.free(parameters_output);

    const fields_output = try getValidatorsFromFields(allocator, generic.fields);
    defer allocator.free(fields_output);

    const format_with_open_names =
        \\export function validate{s}<{s}>({s}): svt.Validator<{s}<{s}>> {{
        \\    return function validate{s}{s}(value: unknown): svt.ValidationResult<{s}<{s}>> {{
        \\        return svt.validate<{s}<{s}>>(value, {{{s}}});
        \\    }};
        \\}}
    ;

    return try fmt.allocPrint(
        allocator,
        format_with_open_names,
        .{
            name,
            open_names_output,
            parameters_output,
            name,
            open_names_output,
            name,
            open_names_together,
            name,
            open_names_output,
            name,
            open_names_output,
            fields_output,
        },
    );
}

fn openNamePredicates(allocator: *mem.Allocator, names: []const []const u8) ![]const []const u8 {
    var predicates = try allocator.alloc([]const u8, names.len);

    for (names) |name, i| {
        predicates[i] = try translatedTypeGuardName(allocator, name);
    }

    return predicates;
}

fn openNameValidators(allocator: *mem.Allocator, names: []const []const u8) ![]const []const u8 {
    var validators = try allocator.alloc([]const u8, names.len);

    for (names) |name, i| {
        validators[i] = try translatedValidatorName(allocator, name);
    }

    return validators;
}

fn outputValidatorForPlainStructure(
    allocator: *mem.Allocator,
    plain_structure: PlainStructure,
) ![]const u8 {
    const name = plain_structure.name.value;

    const validators_output = try getValidatorsFromFields(allocator, plain_structure.fields);
    defer allocator.free(validators_output);

    const output_format =
        \\export function validate{s}(value: unknown): svt.ValidationResult<{s}> {{
        \\    return svt.validate<{s}>(value, {{{s}}});
        \\}}
    ;

    return try fmt.allocPrint(
        allocator,
        output_format,
        .{ name, name, name, validators_output },
    );
}

fn getTypeGuardsFromFields(allocator: *mem.Allocator, fields: []const Field) ![]const u8 {
    var fields_outputs = try allocator.alloc([]const u8, fields.len);
    defer utilities.freeStringArray(allocator, fields_outputs);

    for (fields) |field, i| {
        const type_guard = try getTypeGuardFromType(allocator, field.@"type");
        defer allocator.free(type_guard);

        fields_outputs[i] = try fmt.allocPrint(allocator, "{s}: {s}", .{ field.name, type_guard });
    }

    return try mem.join(allocator, ", ", fields_outputs);
}

fn getValidatorsFromFields(allocator: *mem.Allocator, fields: []const Field) ![]const u8 {
    var fields_outputs = try allocator.alloc([]const u8, fields.len);
    defer utilities.freeStringArray(allocator, fields_outputs);

    for (fields) |field, i| {
        const validator = try getValidatorFromType(allocator, field.@"type");
        defer allocator.free(validator);

        fields_outputs[i] = try fmt.allocPrint(allocator, "{s}: {s}", .{ field.name, validator });
    }

    return try mem.join(allocator, ", ", fields_outputs);
}

fn getTypeGuardFromType(allocator: *mem.Allocator, t: Type) ![]const u8 {
    const array_format = "svt.arrayOf({s})";
    const optional_format = "svt.optional({s})";

    return switch (t) {
        .string => |s| try fmt.allocPrint(allocator, "\"{s}\"", .{s}),
        .reference => |r| try translatedTypeGuardReference(allocator, r),
        .array => |a| output: {
            const nested_validator = try getNestedTypeGuardFromType(allocator, a.@"type".*);
            defer allocator.free(nested_validator);

            break :output try fmt.allocPrint(allocator, array_format, .{nested_validator});
        },
        .slice => |s| output: {
            const nested_validator = try getNestedTypeGuardFromType(allocator, s.@"type".*);
            defer allocator.free(nested_validator);

            break :output try fmt.allocPrint(allocator, array_format, .{nested_validator});
        },
        .pointer => |p| try getNestedTypeGuardFromType(allocator, p.@"type".*),
        .optional => |o| output: {
            const nested_validator = try getNestedTypeGuardFromType(allocator, o.@"type".*);
            defer allocator.free(nested_validator);

            break :output try fmt.allocPrint(allocator, optional_format, .{nested_validator});
        },

        .empty => debug.panic("Empty type does not seem like it should have a type guard\n", .{}),
    };
}

fn getValidatorFromType(allocator: *mem.Allocator, t: Type) ![]const u8 {
    const array_format = "svt.validateArray({s})";
    const optional_format = "svt.validateOptional({s})";

    return switch (t) {
        .string => |s| try fmt.allocPrint(allocator, "\"{s}\"", .{s}),
        .reference => |r| try translatedValidatorReference(allocator, r),
        .array => |a| output: {
            const nested_validator = try getNestedValidatorFromType(allocator, a.@"type".*);
            defer allocator.free(nested_validator);

            break :output try fmt.allocPrint(allocator, array_format, .{nested_validator});
        },
        .slice => |s| output: {
            const nested_validator = try getNestedValidatorFromType(allocator, s.@"type".*);
            defer allocator.free(nested_validator);

            break :output try fmt.allocPrint(allocator, array_format, .{nested_validator});
        },
        .pointer => |p| try getNestedValidatorFromType(allocator, p.@"type".*),
        .optional => |o| output: {
            const nested_validator = try getNestedValidatorFromType(allocator, o.@"type".*);
            defer allocator.free(nested_validator);

            break :output try fmt.allocPrint(allocator, optional_format, .{nested_validator});
        },
        .empty => debug.panic("Empty type does not seem like it should have a type guard\n", .{}),
    };
}

fn outputConstructors(
    allocator: *mem.Allocator,
    union_name: []const u8,
    constructors: []const Constructor,
    tag_field: []const u8,
) ![]const u8 {
    var constructor_outputs = try allocator.alloc([]const u8, constructors.len);
    defer utilities.freeStringArray(allocator, constructor_outputs);

    for (constructors) |constructor, i| {
        constructor_outputs[i] = try outputConstructor(
            allocator,
            union_name,
            constructor,
            &[_][]const u8{},
            tag_field,
        );
    }

    return try mem.join(allocator, "\n\n", constructor_outputs);
}

fn outputTypeGuardsForConstructors(
    allocator: *mem.Allocator,
    union_name: []const u8,
    constructors: []const Constructor,
    open_names: []const []const u8,
    tag_field: []const u8,
) ![]const u8 {
    var type_guards = try allocator.alloc([]const u8, constructors.len);
    defer utilities.freeStringArray(allocator, type_guards);

    for (constructors) |constructor, i| {
        type_guards[i] = try outputTypeGuardForConstructor(
            allocator,
            union_name,
            constructor,
            open_names,
            tag_field,
        );
    }

    return try mem.join(allocator, "\n\n", type_guards);
}

fn outputValidatorsForConstructors(
    allocator: *mem.Allocator,
    union_name: []const u8,
    constructors: []const Constructor,
    open_names: []const []const u8,
    tag_field: []const u8,
) ![]const u8 {
    var validators = try allocator.alloc([]const u8, constructors.len);
    defer utilities.freeStringArray(allocator, validators);

    for (constructors) |constructor, i| {
        validators[i] = try outputValidatorForConstructor(
            allocator,
            union_name,
            constructor,
            open_names,
            tag_field,
        );
    }

    return try mem.join(allocator, "\n\n", validators);
}

fn outputConstructor(
    allocator: *mem.Allocator,
    union_name: []const u8,
    constructor: Constructor,
    open_names: []const []const u8,
    tag_field: []const u8,
) ![]const u8 {
    const tag = constructor.tag;

    const data_specification = try getDataSpecificationFromType(
        allocator,
        constructor.parameter,
        open_names,
    );
    defer if (data_specification) |s| allocator.free(s);

    const open_names_output = try outputOpenNamesFromType(
        allocator,
        constructor.parameter,
        open_names,
    );
    defer allocator.free(open_names_output);

    const enumeration_tag_output = try outputEnumerationTag(allocator, union_name, constructor.tag);
    defer allocator.free(enumeration_tag_output);

    const output_format_with_data =
        \\export function {s}{s}(data: {s}): {s}{s} {{
        \\    return {{{s}: {s}, data}};
        \\}}
    ;

    const output_format_without_data =
        \\export function {s}(): {s} {{
        \\    return {{{s}: {s}}};
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
    return try fmt.allocPrint(allocator, "{s}Tag.{s}", .{ union_name, tag });
}

fn outputConstructorName(
    allocator: *mem.Allocator,
    constructor: Constructor,
    open_names: []const []const u8,
) ![]const u8 {
    return try fmt.allocPrint(
        allocator,
        "{s}{s}",
        .{
            constructor.tag,
            try outputOpenNamesFromType(allocator, constructor.parameter, open_names),
        },
    );
}

fn outputTypeGuardForConstructorWithEmbeddedTypeTag(
    allocator: *mem.Allocator,
    fields_in_structure: []Field,
    tag: []const u8,
    tag_field: []const u8,
    enumeration_tag: []const u8,
) ![]const u8 {
    var field_type_guard_specifications = try allocator.alloc([]const u8, fields_in_structure.len);
    defer utilities.freeStringArray(allocator, field_type_guard_specifications);

    for (fields_in_structure) |f, i| {
        const specification_format = "{s}: {s}";
        const nested = try getNestedTypeGuardFromType(allocator, f.@"type");
        defer allocator.free(nested);

        field_type_guard_specifications[i] =
            try fmt.allocPrint(allocator, specification_format, .{ f.name, nested });
    }

    const type_guard_format_with_payload =
        \\export function is{s}(value: unknown): value is {s} {{
        \\    return svt.isInterface<{s}>(value, {{{s}: {s}, {s}}});
        \\}}
    ;
    const type_guard_format_without_payload =
        \\export function is{s}(value: unknown): value is {s} {{
        \\    return svt.isInterface<{s}>(value, {{{s}: {s}}});
        \\}}
    ;

    const joined_specifications = try mem.join(
        allocator,
        ", ",
        field_type_guard_specifications,
    );
    defer allocator.free(joined_specifications);

    const titlecased_tag = try utilities.titleCaseWord(allocator, tag);
    defer allocator.free(titlecased_tag);

    return if (fields_in_structure.len != 0)
        try fmt.allocPrint(
            allocator,
            type_guard_format_with_payload,
            .{
                titlecased_tag,
                tag,
                tag,
                tag_field,
                enumeration_tag,
                joined_specifications,
            },
        )
    else
        try fmt.allocPrint(
            allocator,
            type_guard_format_without_payload,
            .{
                titlecased_tag,
                tag,
                tag,
                tag_field,
                enumeration_tag,
            },
        );
}

fn outputValidatorForConstructorWithEmbeddedTypeTag(
    allocator: *mem.Allocator,
    fields_in_structure: []Field,
    tag: []const u8,
    tag_field: []const u8,
    enumeration_tag: []const u8,
) ![]const u8 {
    var field_validator_specifications = try allocator.alloc([]const u8, fields_in_structure.len);
    defer utilities.freeStringArray(allocator, field_validator_specifications);

    for (fields_in_structure) |f, i| {
        const specification_format = "{s}: {s}";
        const nested = try getNestedValidatorFromType(allocator, f.@"type");
        defer allocator.free(nested);

        field_validator_specifications[i] =
            try fmt.allocPrint(
            allocator,
            specification_format,
            .{ f.name, nested },
        );
    }

    const validator_format_with_payload =
        \\export function validate{s}(value: unknown): svt.ValidationResult<{s}> {{
        \\    return svt.validate<{s}>(value, {{{s}: {s}, {s}}});
        \\}}
    ;
    const validator_format_without_payload =
        \\export function validate{s}(value: unknown): svt.ValidationResult<{s}> {{
        \\    return svt.validate<{s}>(value, {{{s}: {s}}});
        \\}}
    ;

    const joined_specifications = try mem.join(allocator, ", ", field_validator_specifications);
    defer allocator.free(joined_specifications);

    const titlecased_tag = try utilities.titleCaseWord(allocator, tag);
    defer allocator.free(titlecased_tag);

    return if (fields_in_structure.len != 0)
        try fmt.allocPrint(
            allocator,
            validator_format_with_payload,
            .{
                titlecased_tag,
                tag,
                tag,
                tag_field,
                enumeration_tag,
                joined_specifications,
            },
        )
    else
        try fmt.allocPrint(
            allocator,
            validator_format_without_payload,
            .{
                titlecased_tag,
                tag,
                tag,
                tag_field,
                enumeration_tag,
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

    const constructor_open_names = try general.openNamesFromType(
        allocator,
        constructor.parameter,
        open_names,
    );
    defer utilities.freeStringList(constructor_open_names);

    const open_names_output = try outputOpenNamesFromType(
        allocator,
        constructor.parameter,
        open_names,
    );
    defer allocator.free(open_names_output);

    const open_names_predicates = try openNamePredicates(allocator, constructor_open_names.items);
    defer utilities.freeStringArray(allocator, open_names_predicates);

    var open_name_predicate_types = try allocator.alloc(
        []const u8,
        constructor_open_names.items.len,
    );
    defer allocator.free(open_name_predicate_types);
    defer for (open_name_predicate_types) |t| allocator.free(t);
    for (open_name_predicate_types) |*t, i| {
        t.* = try fmt.allocPrint(
            allocator,
            "svt.TypePredicate<{s}>",
            .{constructor_open_names.items[i]},
        );
    }

    var parameter_outputs = try allocator.alloc([]const u8, constructor_open_names.items.len);
    defer allocator.free(parameter_outputs);
    defer for (parameter_outputs) |o| allocator.free(o);
    for (parameter_outputs) |*o, i| {
        o.* = try fmt.allocPrint(
            allocator,
            "{s}: {s}",
            .{ open_names_predicates[i], open_name_predicate_types[i] },
        );
    }

    const parameters_output = try mem.join(allocator, ", ", parameter_outputs);
    defer allocator.free(parameters_output);

    const enumeration_tag_output = try outputEnumerationTag(allocator, union_name, constructor.tag);
    defer allocator.free(enumeration_tag_output);

    const type_guard_output = try getDataTypeGuardFromType(allocator, constructor.parameter);
    defer allocator.free(type_guard_output);

    const titlecased_tag = try utilities.titleCaseWord(allocator, tag);
    defer allocator.free(titlecased_tag);

    const joined_open_names = try mem.join(allocator, "", constructor_open_names.items);
    defer allocator.free(joined_open_names);

    const output_format_with_open_names =
        \\export function is{s}{s}({s}): svt.TypePredicate<{s}{s}> {{
        \\    return function is{s}{s}(value: unknown): value is {s}{s} {{
        \\        return svt.isInterface<{s}{s}>(value, {{{s}: {s}{s}}});
        \\    }};
        \\}}
    ;

    const output_format_without_open_names =
        \\export function is{s}(value: unknown): value is {s} {{
        \\    return svt.isInterface<{s}>(value, {{{s}: {s}{s}}});
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
                joined_open_names,
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

    const constructor_open_names = try general.openNamesFromType(
        allocator,
        constructor.parameter,
        open_names,
    );
    defer utilities.freeStringList(constructor_open_names);

    const open_names_validators = try openNameValidators(allocator, constructor_open_names.items);
    defer utilities.freeStringArray(allocator, open_names_validators);

    const open_names_predicates_output = try mem.join(allocator, ", ", open_names_validators);
    defer allocator.free(open_names_predicates_output);

    const open_names_output = try mem.join(allocator, ", ", constructor_open_names.items);
    defer allocator.free(open_names_output);

    const joined_open_names = try mem.join(allocator, "", constructor_open_names.items);
    defer allocator.free(joined_open_names);

    var open_name_validator_types = try allocator.alloc(
        []const u8,
        constructor_open_names.items.len,
    );
    defer allocator.free(open_name_validator_types);
    defer for (open_name_validator_types) |t| allocator.free(t);
    for (open_name_validator_types) |*t, i| {
        t.* = try fmt.allocPrint(
            allocator,
            "svt.Validator<{s}>",
            .{constructor_open_names.items[i]},
        );
    }

    var parameter_outputs = try allocator.alloc([]const u8, constructor_open_names.items.len);
    defer allocator.free(parameter_outputs);
    defer for (parameter_outputs) |o| allocator.free(o);
    for (parameter_outputs) |*o, i| {
        o.* = try fmt.allocPrint(
            allocator,
            "{s}: {s}",
            .{ open_names_validators[i], open_name_validator_types[i] },
        );
    }

    const parameters_output = try mem.join(allocator, ", ", parameter_outputs);
    defer allocator.free(parameters_output);

    const union_enum_tag_output = try outputEnumerationTag(allocator, union_name, constructor.tag);
    defer allocator.free(union_enum_tag_output);

    const validator_output = try getDataValidatorFromType(allocator, constructor.parameter);
    defer allocator.free(validator_output);

    const titlecased_tag = try utilities.titleCaseWord(allocator, constructor.tag);
    defer allocator.free(titlecased_tag);

    const format_without_open_names =
        \\export function validate{s}(value: unknown): svt.ValidationResult<{s}> {{
        \\    return svt.validate<{s}>(value, {{{s}: {s}{s}}});
        \\}}
    ;

    const format_with_open_names =
        \\export function validate{s}<{s}>({s}): svt.Validator<{s}<{s}>> {{
        \\    return function validate{s}{s}(value: unknown): svt.ValidationResult<{s}<{s}>> {{
        \\        return svt.validate<{s}<{s}>>(value, {{{s}: {s}{s}}});
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
    const bare_format = "{s}";
    const array_format = "{s}[]";
    const optional_format = "{s} | null | undefined";

    return switch (t) {
        .empty => null,
        .string => |s| try fmt.allocPrint(allocator, bare_format, .{s}),
        .reference => |r| try translateReference(allocator, r),
        .array => |a| output: {
            const nested = try getNestedDataSpecificationFromType(allocator, a.@"type".*);
            defer allocator.free(nested);

            break :output try fmt.allocPrint(allocator, array_format, .{nested});
        },
        .slice => |s| output: {
            const nested = try getNestedDataSpecificationFromType(allocator, s.@"type".*);
            defer allocator.free(nested);

            break :output try fmt.allocPrint(allocator, array_format, .{nested});
        },
        .pointer => |p| output: {
            const nested = try getNestedDataSpecificationFromType(allocator, p.@"type".*);
            defer allocator.free(nested);

            break :output try fmt.allocPrint(allocator, bare_format, .{nested});
        },
        .optional => |o| output: {
            const nested = try getNestedDataSpecificationFromType(allocator, o.@"type".*);
            defer allocator.free(nested);

            break :output try fmt.allocPrint(allocator, optional_format, .{nested});
        },
    };
}

fn getDataTypeGuardFromType(allocator: *mem.Allocator, t: Type) ![]const u8 {
    const bare_format = ", data: {s}";
    const type_guard_format = ", data: {s}";
    const builtin_type_guard_format = ", data: svt.is{s}";
    const array_format = ", data: svt.arrayOf({s})";
    const optional_format = ", data: svt.optional({s})";

    return switch (t) {
        .empty => "",
        .string => |s| try fmt.allocPrint(allocator, bare_format, .{s}),
        .reference => |r| output: {
            const translated = try translatedTypeGuardReference(allocator, r);
            defer allocator.free(translated);

            break :output try fmt.allocPrint(
                allocator,
                type_guard_format,
                .{translated},
            );
        },
        .array => |a| output: {
            const nested = try getNestedTypeGuardFromType(allocator, a.@"type".*);
            defer allocator.free(nested);

            break :output try fmt.allocPrint(allocator, array_format, .{nested});
        },
        .slice => |s| output: {
            const nested = try getNestedTypeGuardFromType(allocator, s.@"type".*);
            defer allocator.free(nested);

            break :output try fmt.allocPrint(allocator, array_format, .{nested});
        },
        .pointer => |p| output: {
            const nested = try getNestedTypeGuardFromType(allocator, p.@"type".*);
            defer allocator.free(nested);

            break :output try fmt.allocPrint(allocator, type_guard_format, .{nested});
        },
        .optional => |o| output: {
            const nested = try getNestedTypeGuardFromType(allocator, o.@"type".*);
            defer allocator.free(nested);

            break :output try fmt.allocPrint(allocator, optional_format, .{nested});
        },
    };
}

fn getDataValidatorFromType(allocator: *mem.Allocator, t: Type) ![]const u8 {
    const bare_format = ", data: {s}";
    const validator_format = ", data: {s}";
    const builtin_type_guard_format = ", data: svt.validate{s}";
    const array_format = ", data: svt.validateArray({s})";
    const optional_format = ", data: svt.validateOptional({s})";

    return switch (t) {
        .empty => "",
        .string => |s| try fmt.allocPrint(allocator, bare_format, .{s}),
        .reference => |r| output: {
            const validator = try translatedValidatorReference(allocator, r);
            defer allocator.free(validator);

            break :output try fmt.allocPrint(allocator, validator_format, .{validator});
        },
        .array => |a| output: {
            const validator = try getNestedValidatorFromType(allocator, a.@"type".*);
            defer allocator.free(validator);

            break :output try fmt.allocPrint(allocator, array_format, .{validator});
        },
        .slice => |s| output: {
            const validator = try getNestedValidatorFromType(allocator, s.@"type".*);
            defer allocator.free(validator);

            break :output try fmt.allocPrint(allocator, array_format, .{validator});
        },
        .pointer => |p| output: {
            const validator = try getNestedValidatorFromType(allocator, p.@"type".*);
            defer allocator.free(validator);

            break :output try fmt.allocPrint(allocator, validator_format, .{validator});
        },
        .optional => |o| output: {
            const validator = try getNestedValidatorFromType(allocator, o.@"type".*);
            defer allocator.free(validator);

            break :output try fmt.allocPrint(allocator, optional_format, .{validator});
        },
    };
}

fn getNestedDataSpecificationFromType(
    allocator: *mem.Allocator,
    t: Type,
) error{OutOfMemory}![]const u8 {
    const array_format = "{s}[]";
    const optional_format = "{s} | null | undefined";

    return switch (t) {
        .empty => debug.panic("Empty nested type invalid for data specification\n", .{}),
        .string => |s| try fmt.allocPrint(allocator, "\"{s}\"", .{s}),
        .reference => |r| try translateReference(allocator, r),
        .array => |a| output: {
            const nested = try getNestedDataSpecificationFromType(allocator, a.@"type".*);
            defer allocator.free(nested);

            break :output try fmt.allocPrint(allocator, array_format, .{nested});
        },
        .slice => |s| output: {
            const nested = try getNestedDataSpecificationFromType(allocator, s.@"type".*);
            defer allocator.free(nested);

            break :output try fmt.allocPrint(allocator, array_format, .{nested});
        },
        .pointer => |p| output: {
            const nested = try getNestedDataSpecificationFromType(allocator, p.@"type".*);
            defer allocator.free(nested);

            break :output try fmt.allocPrint(allocator, "is{s}", .{nested});
        },
        .optional => |o| output: {
            const nested = try getNestedDataSpecificationFromType(allocator, o.@"type".*);
            defer allocator.free(nested);

            break :output try fmt.allocPrint(allocator, optional_format, .{nested});
        },
    };
}

fn getNestedTypeGuardFromType(allocator: *mem.Allocator, t: Type) error{OutOfMemory}![]const u8 {
    const array_format = "svt.arrayOf({s})";
    const optional_format = "svt.optional({s})";

    return switch (t) {
        .empty => debug.panic("Empty nested type invalid for type guard\n", .{}),
        .string => |s| try fmt.allocPrint(allocator, "\"{s}\"", .{s}),
        .reference => |r| try translatedTypeGuardReference(allocator, r),
        .array => |a| output: {
            const nested_validator = try getNestedTypeGuardFromType(allocator, a.@"type".*);
            defer allocator.free(nested_validator);

            break :output try fmt.allocPrint(allocator, array_format, .{nested_validator});
        },
        .slice => |s| output: {
            const nested_validator = try getNestedTypeGuardFromType(allocator, s.@"type".*);
            defer allocator.free(nested_validator);

            break :output try fmt.allocPrint(allocator, array_format, .{nested_validator});
        },
        .pointer => |p| output: {
            const nested_validator = try getNestedTypeGuardFromType(allocator, p.@"type".*);
            defer allocator.free(nested_validator);

            break :output try fmt.allocPrint(allocator, "is{s}", .{nested_validator});
        },
        .optional => |o| output: {
            const nested_validator = try getNestedTypeGuardFromType(allocator, o.@"type".*);
            defer allocator.free(nested_validator);

            break :output try fmt.allocPrint(allocator, optional_format, .{nested_validator});
        },
    };
}

fn getNestedValidatorFromType(allocator: *mem.Allocator, t: Type) error{OutOfMemory}![]const u8 {
    const array_format = "svt.validateArray({s})";
    const optional_format = "svt.validateOptional({s})";

    return switch (t) {
        .empty => debug.panic("Empty nested type invalid for validator\n", .{}),
        .string => |s| try fmt.allocPrint(allocator, "\"{s}\"", .{s}),
        .reference => |r| try translatedValidatorReference(allocator, r),
        .array => |a| output: {
            const nested_validator = try getNestedValidatorFromType(allocator, a.@"type".*);
            defer allocator.free(nested_validator);

            break :output try fmt.allocPrint(allocator, array_format, .{nested_validator});
        },
        .slice => |s| output: {
            const nested_validator = try getNestedValidatorFromType(allocator, s.@"type".*);
            defer allocator.free(nested_validator);

            break :output try fmt.allocPrint(allocator, array_format, .{nested_validator});
        },
        .pointer => |p| output: {
            const nested_validator = try getNestedValidatorFromType(allocator, p.@"type".*);
            defer allocator.free(nested_validator);

            break :output try fmt.allocPrint(allocator, "is{s}", .{nested_validator});
        },
        .optional => |o| output: {
            const nested_validator = try getNestedValidatorFromType(allocator, o.@"type".*);
            defer allocator.free(nested_validator);

            break :output try fmt.allocPrint(allocator, optional_format, .{nested_validator});
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
        try fmt.allocPrint(allocator, "<{s}>", .{try mem.join(allocator, ", ", common_names.items)});
}

fn outputTaggedStructures(
    allocator: *mem.Allocator,
    union_name: []const u8,
    constructors: []const Constructor,
    tag_field: []const u8,
) ![]const u8 {
    var tagged_structures_outputs = try allocator.alloc([]const u8, constructors.len);
    defer utilities.freeStringArray(allocator, tagged_structures_outputs);

    for (constructors) |constructor, i| {
        tagged_structures_outputs[i] = try outputTaggedStructure(
            allocator,
            union_name,
            constructor,
            tag_field,
        );
    }

    return try mem.join(allocator, "\n\n", tagged_structures_outputs);
}

fn outputTaggedMaybeGenericStructures(
    allocator: *mem.Allocator,
    union_name: []const u8,
    constructors: []const Constructor,
    open_names: []const []const u8,
    tag_field: []const u8,
) ![]const u8 {
    var tagged_structures_outputs = try allocator.alloc([]const u8, constructors.len);
    defer utilities.freeStringArray(allocator, tagged_structures_outputs);

    for (constructors) |constructor, i| {
        tagged_structures_outputs[i] =
            try outputTaggedMaybeGenericStructure(
            allocator,
            union_name,
            constructor,
            open_names,
            tag_field,
        );
    }

    return try mem.join(allocator, "\n\n", tagged_structures_outputs);
}

fn outputGenericConstructors(
    allocator: *mem.Allocator,
    union_name: []const u8,
    constructors: []const Constructor,
    open_names: []const []const u8,
    tag_field: []const u8,
) ![]const u8 {
    var constructor_outputs = try allocator.alloc([]const u8, constructors.len);
    defer utilities.freeStringArray(allocator, constructor_outputs);

    for (constructors) |constructor, i| {
        constructor_outputs[i] = try outputConstructor(
            allocator,
            union_name,
            constructor,
            open_names,
            tag_field,
        );
    }

    return try mem.join(allocator, "\n\n", constructor_outputs);
}

fn outputTaggedStructure(
    allocator: *mem.Allocator,
    union_name: []const u8,
    constructor: Constructor,
    tag_field: []const u8,
) ![]const u8 {
    const parameter_output = try outputType(allocator, constructor.parameter);
    defer if (parameter_output) |o| allocator.free(o);

    const enumeration_tag_output = try outputEnumerationTag(allocator, union_name, constructor.tag);
    defer allocator.free(enumeration_tag_output);

    const output_format_with_parameter =
        \\export type {s} = {{
        \\    {s}: {s};
        \\    data: {s};
        \\}};
    ;

    const output_format_without_parameter =
        \\export type {s} = {{
        \\    {s}: {s};
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
    const open_names_output = try outputOpenNamesFromType(
        allocator,
        constructor.parameter,
        open_names,
    );
    defer allocator.free(open_names_output);

    const parameter_output = if (try outputType(allocator, constructor.parameter)) |output| p: {
        defer allocator.free(output);
        break :p try fmt.allocPrint(allocator, "\n    data: {s};", .{output});
    } else "";
    defer allocator.free(parameter_output);

    const enumeration_tag_output = try outputEnumerationTag(allocator, union_name, constructor.tag);
    defer allocator.free(enumeration_tag_output);

    const output_format =
        \\export type {s}{s} = {{
        \\    {s}: {s};{s}
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

fn outputOpenNamesFromType(
    allocator: *mem.Allocator,
    t: Type,
    open_names: []const []const u8,
) error{OutOfMemory}![]const u8 {
    const type_open_names = try general.openNamesFromType(allocator, t, open_names);
    defer utilities.freeStringList(type_open_names);

    const joined_open_names = try mem.join(allocator, ", ", type_open_names.items);
    defer allocator.free(joined_open_names);

    return if (type_open_names.items.len == 0)
        ""
    else
        try fmt.allocPrint(allocator, "<{s}>", .{joined_open_names});
}

fn outputType(allocator: *mem.Allocator, t: Type) error{OutOfMemory}!?[]const u8 {
    return switch (t) {
        .empty => null,
        .string => |s| try fmt.allocPrint(allocator, "\"{s}\"", .{s}),
        .reference => |r| try translateReference(allocator, r),

        .array => |d| output: {
            if (try outputType(allocator, d.@"type".*)) |embedded_type| {
                defer allocator.free(embedded_type);

                switch (d.@"type".*) {
                    .optional => break :output try fmt.allocPrint(
                        allocator,
                        "({s})[]",
                        .{embedded_type},
                    ),
                    else => break :output try fmt.allocPrint(allocator, "{s}[]", .{embedded_type}),
                }
            } else {
                debug.panic("Invalid empty type in optional type\n", .{});
            }
        },

        .slice => |d| output: {
            if (try outputType(allocator, d.@"type".*)) |embedded_type| {
                defer allocator.free(embedded_type);

                switch (d.@"type".*) {
                    .optional => |o| break :output try fmt.allocPrint(
                        allocator,
                        "({s})[]",
                        .{embedded_type},
                    ),
                    else => break :output try fmt.allocPrint(allocator, "{s}[]", .{embedded_type}),
                }
            } else {
                debug.panic("Invalid empty type in optional type\n", .{});
            }
        },

        .pointer => |d| output: {
            if (try outputType(allocator, d.@"type".*)) |embedded_type| {
                break :output embedded_type;
            } else {
                debug.panic("Invalid empty type in optional type\n", .{});
            }
        },

        .optional => |d| output: {
            if (try outputType(allocator, d.@"type".*)) |embedded_type| {
                defer allocator.free(embedded_type);

                break :output try fmt.allocPrint(
                    allocator,
                    "{s} | null | undefined",
                    .{embedded_type},
                );
            } else {
                debug.panic("Invalid empty type in optional type\n", .{});
            }
        },
    };
}

/// Returns all actual open names for a list of names. This means they're not translated and so
/// won't be assumed to be concrete type arguments.
fn actualOpenNames(allocator: *mem.Allocator, names: []const []const u8) !ArrayList([]const u8) {
    var open_names = ArrayList([]const u8).init(allocator);

    for (names) |name| {
        if (!general.isTranslatedName(name)) try open_names.append(try allocator.dupe(u8, name));
    }

    return open_names;
}

fn outputOpenNames(allocator: *mem.Allocator, names: []const []const u8) ![]const u8 {
    var translated_names = try allocator.alloc([]const u8, names.len);
    defer utilities.freeStringArray(allocator, translated_names);

    for (names) |name, i| translated_names[i] = try allocator.dupe(u8, translateName(name));

    const joined_names = try mem.join(allocator, ", ", translated_names);
    defer allocator.free(joined_names);

    return try fmt.allocPrint(allocator, "<{s}>", .{joined_names});
}

fn translateName(name: []const u8) []const u8 {
    return if (mem.eql(u8, name, "String"))
        "string"
    else if (general.isNumberType(name))
        "number"
    else if (mem.eql(u8, name, "Boolean"))
        "boolean"
    else
        name;
}

fn translateReference(
    allocator: *mem.Allocator,
    reference: TypeReference,
) error{OutOfMemory}![]const u8 {
    return switch (reference) {
        .builtin => |b| switch (b) {
            .String => try allocator.dupe(u8, "string"),
            .Boolean => try allocator.dupe(u8, "boolean"),
            .U8,
            .U16,
            .U32,
            .U64,
            .U128,
            .I8,
            .I16,
            .I32,
            .I64,
            .I128,
            .F32,
            .F64,
            .F128,
            => try allocator.dupe(u8, "number"),
        },
        .definition => |d| try allocator.dupe(u8, d.name().value),
        .imported_definition => |id| id: {
            const name = id.definition.name().value;

            break :id try fmt.allocPrint(
                allocator,
                "{s}.{s}",
                .{ id.import_name, id.definition.name().value },
            );
        },
        .applied_name => |applied_name| output: {
            const open_names = try outputAppliedOpenNames(
                allocator,
                applied_name.open_names,
            );
            defer allocator.free(open_names);

            const reference_output = try translateReference(
                allocator,
                applied_name.reference.*,
            );
            defer allocator.free(reference_output);

            break :output try fmt.allocPrint(
                allocator,
                "{s}{s}",
                .{ reference_output, open_names },
            );
        },
        .loose => |l| try allocator.dupe(u8, l.name),
        .open => |n| try allocator.dupe(u8, n),
    };
}

fn outputAppliedOpenNames(
    allocator: *mem.Allocator,
    applied_open_names: []const AppliedOpenName,
) error{OutOfMemory}![]const u8 {
    var outputs = try allocator.alloc([]const u8, applied_open_names.len);
    defer utilities.freeStringArray(allocator, outputs);

    for (applied_open_names) |name, i| {
        outputs[i] = (try outputType(allocator, name.reference)).?;
    }

    const joined_outputs = try mem.join(allocator, ", ", outputs);
    defer allocator.free(joined_outputs);

    return try fmt.allocPrint(allocator, "<{s}>", .{joined_outputs});
}

fn translatedTypeGuardName(allocator: *mem.Allocator, name: []const u8) ![]const u8 {
    return if (mem.eql(u8, name, "String"))
        try allocator.dupe(u8, "svt.isString")
    else if (general.isNumberType(name))
        try allocator.dupe(u8, "svt.isNumber")
    else if (mem.eql(u8, name, "Boolean"))
        try allocator.dupe(u8, "svt.isBoolean")
    else
        try fmt.allocPrint(allocator, "is{s}", .{name});
}

fn translatedTypeGuardReference(
    allocator: *mem.Allocator,
    reference: TypeReference,
) error{OutOfMemory}![]const u8 {
    return switch (reference) {
        .builtin => |b| switch (b) {
            .String => try allocator.dupe(u8, "svt.isString"),
            .Boolean => try allocator.dupe(u8, "svt.isBoolean"),
            .U8,
            .U16,
            .U32,
            .U64,
            .U128,
            .I8,
            .I16,
            .I32,
            .I64,
            .I128,
            .F32,
            .F64,
            .F128,
            => try allocator.dupe(u8, "svt.isNumber"),
        },

        .definition => |d| try fmt.allocPrint(allocator, "is{s}", .{d.name().value}),

        .imported_definition => |id| try fmt.allocPrint(
            allocator,
            "{s}.is{s}",
            .{ id.import_name, id.definition.name().value },
        ),

        .applied_name => |applied_name| output: {
            const open_name_predicates = try appliedOpenNamePredicates(allocator, applied_name.open_names);
            defer utilities.freeStringArray(allocator, open_name_predicates);

            const joined_predicates = try mem.join(allocator, ", ", open_name_predicates);
            defer allocator.free(joined_predicates);

            const reference_predicate = try translatedTypeGuardReference(
                allocator,
                applied_name.reference.*,
            );
            defer allocator.free(reference_predicate);

            break :output try fmt.allocPrint(
                allocator,
                "{s}({s})",
                .{ reference_predicate, joined_predicates },
            );
        },

        .loose => |l| try fmt.allocPrint(allocator, "is{s}", .{l.name}),
        .open => |n| try fmt.allocPrint(allocator, "is{s}", .{n}),
    };
}

fn appliedOpenNamePredicates(
    allocator: *mem.Allocator,
    applied_open_names: []const AppliedOpenName,
) error{OutOfMemory}![]const []const u8 {
    var outputs = try allocator.alloc([]const u8, applied_open_names.len);

    for (applied_open_names) |name, i| {
        outputs[i] = try getTypeGuardFromType(allocator, name.reference);
    }

    return outputs;
}

fn translatedValidatorName(allocator: *mem.Allocator, name: []const u8) ![]const u8 {
    return if (mem.eql(u8, name, "String"))
        try allocator.dupe(u8, "svt.validateString")
    else if (general.isNumberType(name))
        try allocator.dupe(u8, "svt.validateNumber")
    else if (mem.eql(u8, name, "Boolean"))
        try allocator.dupe(u8, "svt.validateBoolean")
    else
        try fmt.allocPrint(allocator, "validate{s}", .{name});
}

fn translatedValidatorReference(
    allocator: *mem.Allocator,
    reference: TypeReference,
) error{OutOfMemory}![]const u8 {
    const format = "validate{s}";

    return switch (reference) {
        .builtin => |b| switch (b) {
            .String => try allocator.dupe(u8, "svt.validateString"),
            .Boolean => try allocator.dupe(u8, "svt.validateBoolean"),
            .U8,
            .U16,
            .U32,
            .U64,
            .U128,
            .I8,
            .I16,
            .I32,
            .I64,
            .I128,
            .F32,
            .F64,
            .F128,
            => try allocator.dupe(u8, "svt.validateNumber"),
        },

        .definition => |d| try fmt.allocPrint(allocator, format, .{d.name().value}),

        .imported_definition => |id| try fmt.allocPrint(
            allocator,
            "{s}.validate{s}",
            .{ id.import_name, id.definition.name().value },
        ),

        .applied_name => |applied_name| output: {
            const open_name_validators = try appliedOpenNameValidators(allocator, applied_name.open_names);
            defer utilities.freeStringArray(allocator, open_name_validators);

            const joined_validators = try mem.join(allocator, ", ", open_name_validators);
            defer allocator.free(joined_validators);

            const reference_validator = try translatedValidatorReference(
                allocator,
                applied_name.reference.*,
            );
            defer allocator.free(reference_validator);

            break :output try fmt.allocPrint(
                allocator,
                "{s}({s})",
                .{ reference_validator, joined_validators },
            );
        },

        .loose => |l| try fmt.allocPrint(allocator, format, .{l.name}),
        .open => |n| try fmt.allocPrint(allocator, format, .{n}),
    };
}

fn appliedOpenNameValidators(
    allocator: *mem.Allocator,
    applied_open_names: []const AppliedOpenName,
) error{OutOfMemory}![]const []const u8 {
    var outputs = try allocator.alloc([]const u8, applied_open_names.len);

    for (applied_open_names) |name, i| {
        outputs[i] = try getValidatorFromType(allocator, name.reference);
    }

    return outputs;
}

test "" {
    const typescript_tests = @import("./typescript_tests.zig");

    std.testing.refAllDecls(typescript_tests);
}
