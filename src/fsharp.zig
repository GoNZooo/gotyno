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
const Builtin = parser.Builtin;
const LooseReference = parser.LooseReference;

const TestingAllocator = testing_utilities.TestingAllocator;

pub fn outputFilename(allocator: *mem.Allocator, filename: []const u8) ![]const u8 {
    debug.assert(mem.endsWith(u8, filename, ".gotyno"));

    var split_iterator = mem.split(filename, ".gotyno");
    const before_extension = split_iterator.next().?;

    const only_filename = if (mem.lastIndexOf(u8, before_extension, "/")) |index|
        before_extension[(index + 1)..]
    else
        before_extension;

    return mem.join(allocator, "", &[_][]const u8{ only_filename, ".fs" });
}

pub fn compileDefinitions(allocator: *mem.Allocator, definitions: []const Definition) ![]const u8 {
    var outputs = ArrayList([]const u8).init(allocator);
    defer utilities.freeStringList(outputs);

    for (definitions) |definition| try outputs.append(try outputDefinition(allocator, definition));

    return try mem.join(allocator, "\n\n", outputs.items);
}

fn outputDefinition(allocator: *mem.Allocator, definition: Definition) ![]const u8 {
    return switch (definition) {
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
        .import => |i| try outputImport(allocator, i),
    };
}

fn outputPlainStructure(allocator: *mem.Allocator, s: PlainStructure) ![]const u8 {
    const fields_output = try outputStructureFields(allocator, s.fields);
    defer allocator.free(fields_output);

    // @TODO: add decoder & encoder output here
    // The plan is to use `Thoth` to begin with and we'll see where we go from there.
    // A utility package called `GotynoCoders` can be used to provide some basic tools, like
    // `simple-validation-tools` does for the TypeScript output.
    // Currently `decodeLiteralString` is added to the package, which means we can use that decoder
    // for literal string fields, etc.
    const format =
        \\type {} = {{
        \\{}
        \\}}
    ;

    return try fmt.allocPrint(allocator, format, .{ s.name.value, fields_output });
}

fn outputStructureFields(allocator: *mem.Allocator, fields: []const Field) ![]const u8 {
    var field_outputs = ArrayList([]const u8).init(allocator);
    defer utilities.freeStringList(field_outputs);

    for (fields) |f| {
        try field_outputs.append(try outputStructureField(allocator, f));
    }

    return try mem.join(allocator, "\n", field_outputs.items);
}

fn outputStructureField(allocator: *mem.Allocator, field: Field) ![]const u8 {
    const type_output = try outputStructureFieldType(allocator, field.@"type");
    defer allocator.free(type_output);

    const format = "    {}: {}";

    return try fmt.allocPrint(allocator, format, .{ field.name, type_output });
}

fn outputStructureFieldType(allocator: *mem.Allocator, t: Type) error{OutOfMemory}![]const u8 {
    const array_format = "list<{}>";
    const optional_format = "option<{}>";
    const applied_name_format = "{}<{}>";

    return switch (t) {
        .string => try allocator.dupe(u8, "string"),
        .reference => |d| try outputTypeReference(allocator, d),
        .pointer => |d| try outputStructureFieldType(allocator, d.@"type".*),
        .array => |d| o: {
            const nested_type_output = try outputStructureFieldType(allocator, d.@"type".*);
            defer allocator.free(nested_type_output);

            break :o try fmt.allocPrint(allocator, array_format, .{nested_type_output});
        },
        .slice => |d| o: {
            const nested_type_output = try outputStructureFieldType(allocator, d.@"type".*);
            defer allocator.free(nested_type_output);

            break :o try fmt.allocPrint(allocator, array_format, .{nested_type_output});
        },
        .optional => |d| o: {
            const nested_type_output = try outputStructureFieldType(allocator, d.@"type".*);
            defer allocator.free(nested_type_output);

            break :o try fmt.allocPrint(allocator, optional_format, .{nested_type_output});
        },
        .applied_name => |d| o: {
            const nested_type_output = try outputTypeReference(allocator, d.reference);
            defer allocator.free(nested_type_output);
            const joined_open_names = try mem.join(allocator, ", ", d.open_names);
            defer allocator.free(joined_open_names);

            break :o try fmt.allocPrint(
                allocator,
                applied_name_format,
                .{ nested_type_output, joined_open_names },
            );
        },
        .empty => debug.panic("Structure field cannot be empty\n", .{}),
    };
}

fn outputTypeReference(allocator: *mem.Allocator, r: TypeReference) ![]const u8 {
    return switch (r) {
        .builtin => |b| try outputBuiltinReference(allocator, b),
        .definition => |d| try allocator.dupe(u8, d.name().value),
        .loose => |l| try outputLooseReference(allocator, l),
        .open => |o| try allocator.dupe(u8, o),
    };
}

fn outputBuiltinReference(allocator: *mem.Allocator, b: Builtin) ![]const u8 {
    return switch (b) {
        .String => try allocator.dupe(u8, "string"),
        .Boolean => try allocator.dupe(u8, "bool"),
        .U8 => try allocator.dupe(u8, "uint8"),
        .U16 => try allocator.dupe(u8, "uint16"),
        .U32 => try allocator.dupe(u8, "uint32"),
        .U64 => try allocator.dupe(u8, "uint64"),
        .U128 => try allocator.dupe(u8, "uint128"),
        .I8 => try allocator.dupe(u8, "int8"),
        .I16 => try allocator.dupe(u8, "int16"),
        .I32 => try allocator.dupe(u8, "int32"),
        .I64 => try allocator.dupe(u8, "int64"),
        .I128 => try allocator.dupe(u8, "int128"),
        .F32 => try allocator.dupe(u8, "float32"),
        .F64 => try allocator.dupe(u8, "float64"),
        .F128 => try allocator.dupe(u8, "float128"),
    };
}

fn outputLooseReference(allocator: *mem.Allocator, l: LooseReference) ![]const u8 {
    return if (l.open_names.len == 0)
        try allocator.dupe(u8, l.name)
    else o: {
        const joined_open_names = try mem.join(allocator, ", ", l.open_names);
        defer allocator.free(joined_open_names);

        break :o try fmt.allocPrint(allocator, "{}<{}>", .{ l.name, joined_open_names });
    };
}

fn outputGenericStructure(allocator: *mem.Allocator, s: GenericStructure) ![]const u8 {
    return try allocator.dupe(u8, "");
}

fn outputPlainUnion(allocator: *mem.Allocator, s: PlainUnion) ![]const u8 {
    return try allocator.dupe(u8, "");
}

fn outputGenericUnion(allocator: *mem.Allocator, s: GenericUnion) ![]const u8 {
    return try allocator.dupe(u8, "");
}

fn outputEmbeddedUnion(allocator: *mem.Allocator, s: EmbeddedUnion) ![]const u8 {
    return try allocator.dupe(u8, "");
}

fn outputEnumeration(allocator: *mem.Allocator, s: Enumeration) ![]const u8 {
    return try allocator.dupe(u8, "");
}

fn outputUntaggedUnion(allocator: *mem.Allocator, s: UntaggedUnion) ![]const u8 {
    return try allocator.dupe(u8, "");
}

fn outputImport(allocator: *mem.Allocator, s: Import) ![]const u8 {
    return try allocator.dupe(u8, "");
}

test "outputs plain structure correctly" {
    var allocator = TestingAllocator{};

    const expected_output =
        \\type Person = {
        \\    type: string
        \\    name: string
        \\    age: uint8
        \\    efficiency: float32
        \\    on_vacation: bool
        \\    hobbies: list<string>
        \\    last_fifteen_comments: list<string>
        \\    recruiter: Person
        \\}
    ;

    var parsing_error: ParsingError = undefined;

    var definitions = try parser.parse(
        &allocator.allocator,
        &allocator.allocator,
        type_examples.person_structure,
        &parsing_error,
    );

    const output = try outputPlainStructure(
        &allocator.allocator,
        (definitions).definitions[0].structure.plain,
    );

    testing.expectEqualStrings(output, expected_output);

    definitions.deinit();
    allocator.allocator.free(output);
    testing_utilities.expectNoLeaks(&allocator);
}
