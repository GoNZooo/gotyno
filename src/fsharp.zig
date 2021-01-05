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

    const decoder_output = try outputDecoderForPlainStructure(allocator, s);
    defer allocator.free(decoder_output);

    const encoder_output = try outputEncoderForPlainStructure(allocator, s);
    defer allocator.free(encoder_output);

    // @TODO: add encoder output here
    const format =
        \\type {} = {{
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
        .{ s.name.value, fields_output, decoder_output, encoder_output },
    );
}

fn outputStructureFields(allocator: *mem.Allocator, fields: []const Field) ![]const u8 {
    var field_outputs = ArrayList([]const u8).init(allocator);
    defer utilities.freeStringList(field_outputs);

    for (fields) |f| {
        try field_outputs.append(try outputStructureField(allocator, f));
    }

    return try mem.join(allocator, "\n", field_outputs.items);
}

fn outputDecoderForPlainStructure(allocator: *mem.Allocator, s: PlainStructure) ![]const u8 {
    var decoder_outputs = ArrayList([]const u8).init(allocator);
    defer utilities.freeStringList(decoder_outputs);

    for (s.fields) |f| {
        try decoder_outputs.append(try outputDecoderForField(allocator, f));
    }

    const decoders_output = try mem.join(allocator, "\n", decoder_outputs.items);
    defer allocator.free(decoders_output);

    const format =
        \\    static member Decoder: Decoder<{}>
        \\        (fun get ->
        \\            {{
        \\{}
        \\            }}
        \\        )
    ;

    return try fmt.allocPrint(allocator, format, .{ s.name.value, decoders_output });
}

fn outputDecoderForField(allocator: *mem.Allocator, f: Field) ![]const u8 {
    const decoder = try decoderForType(allocator, f.@"type");
    defer allocator.free(decoder);

    const format = "              {} = get.Required.Field \"{}\" {}";
    const format_for_optional = "              {} = get.Optional.Field \"{}\" {}";

    return switch (f.@"type") {
        .optional => try fmt.allocPrint(allocator, format_for_optional, .{ f.name, f.name, decoder }),
        else => try fmt.allocPrint(allocator, format, .{ f.name, f.name, decoder }),
    };
}

fn decoderForType(allocator: *mem.Allocator, t: Type) error{OutOfMemory}![]const u8 {
    const array_format = "(Decode.list {})";
    const applied_name_format = "({} {})";
    const string_format = "(GotynoCoders.decodeLiteralString \"{}\")";

    return switch (t) {
        .string => |s| try fmt.allocPrint(allocator, string_format, .{s}),
        .reference => |d| try decoderForTypeReference(allocator, d),
        .pointer => |d| try decoderForType(allocator, d.@"type".*),
        .array => |d| o: {
            const nested_type_output = try decoderForType(allocator, d.@"type".*);
            defer allocator.free(nested_type_output);

            break :o try fmt.allocPrint(allocator, array_format, .{nested_type_output});
        },
        .slice => |d| o: {
            const nested_type_output = try decoderForType(allocator, d.@"type".*);
            defer allocator.free(nested_type_output);

            break :o try fmt.allocPrint(allocator, array_format, .{nested_type_output});
        },
        .optional => |d| try decoderForType(allocator, d.@"type".*),
        .applied_name => |d| o: {
            const nested_type_output = try decoderForTypeReference(allocator, d.reference);
            defer allocator.free(nested_type_output);

            break :o try fmt.allocPrint(
                allocator,
                applied_name_format,
                .{ d.reference.name(), nested_type_output },
            );
        },
        .empty => debug.panic("Structure field cannot be empty\n", .{}),
    };
}

fn decoderForTypeReference(allocator: *mem.Allocator, r: TypeReference) ![]const u8 {
    return switch (r) {
        .builtin => |d| try decoderForBuiltin(allocator, d),
        .definition => |d| try decoderForDefinition(allocator, d),
        .loose => |d| try fmt.allocPrint(allocator, "{}.Decoder", .{d.name}),
        .open => |d| try fmt.allocPrint(allocator, "decode{}", .{d}),
    };
}

fn decoderForBuiltin(allocator: *mem.Allocator, b: Builtin) ![]const u8 {
    return try allocator.dupe(u8, switch (b) {
        .String => "Decode.string",
        .Boolean => "Decode.boolean",
        .U8 => "Decode.uint8",
        .U16 => "Decode.uint16",
        .U32 => "Decode.uint32",
        .U64 => "Decode.uint64",
        .U128 => "Decode.uint128",
        .I8 => "Decode.int8",
        .I16 => "Decode.int16",
        .I32 => "Decode.int32",
        .I64 => "Decode.int64",
        .I128 => "Decode.int128",
        .F32 => "Decode.float32",
        .F64 => "Decode.float64",
        .F128 => "Decode.float128",
    });
}

fn decoderForDefinition(allocator: *mem.Allocator, d: Definition) ![]const u8 {
    return switch (d) {
        .structure => |s| switch (s) {
            .plain => |p| try fmt.allocPrint(allocator, "{}.Decoder", .{p.name.value}),
            .generic => debug.panic("Generic structure does not have decoder yet.\n", .{}),
        },
        .@"union" => debug.panic("Union does not have decoder yet.\n", .{}),
        .untagged_union => debug.panic("Untagged union does not have decoder yet.\n", .{}),
        .enumeration => debug.panic("Enumeration does not have decoder yet.\n", .{}),
        .import => debug.panic("Import cannot have decoder\n", .{}),
    };
}

fn outputEncoderForPlainStructure(allocator: *mem.Allocator, s: PlainStructure) ![]const u8 {
    var encoder_outputs = ArrayList([]const u8).init(allocator);
    defer utilities.freeStringList(encoder_outputs);

    for (s.fields) |f| {
        try encoder_outputs.append(try outputEncoderForField(allocator, f));
    }

    const encoders_output = try mem.join(allocator, "\n", encoder_outputs.items);
    defer allocator.free(encoders_output);

    const format =
        \\    static member Encoder value =
        \\        Encode.object
        \\            [
        \\{}
        \\            ]
    ;

    return try fmt.allocPrint(allocator, format, .{encoders_output});
}

fn outputEncoderForField(allocator: *mem.Allocator, f: Field) ![]const u8 {
    const encoder = try encoderForType(allocator, f.name, f.@"type");
    defer allocator.free(encoder);

    const format = "                \"{}\", {}";
    const format_for_optional = "              {} = get.Optional.Field \"{}\" {}";

    return switch (f.@"type") {
        .optional => try fmt.allocPrint(allocator, format_for_optional, .{ f.name, f.name, encoder }),
        else => try fmt.allocPrint(allocator, format, .{ f.name, encoder }),
    };
}

fn encoderForType(allocator: *mem.Allocator, name: []const u8, t: Type) error{OutOfMemory}![]const u8 {
    const array_format = "GotynoCoders.encodeList {}";
    const applied_name_format = "({} {})";
    const string_format = "Encode.string \"{}\"";

    return switch (t) {
        .string => |s| try fmt.allocPrint(allocator, string_format, .{s}),
        .reference => |d| o: {
            const encoder = try encoderForTypeReference(allocator, d);
            defer allocator.free(encoder);

            break :o try fmt.allocPrint(allocator, "{} value.{}", .{ encoder, name });
        },
        .pointer => |d| try encoderForType(allocator, name, d.@"type".*),
        .array => |d| o: {
            const nested_type_output = try encoderForType(allocator, name, d.@"type".*);
            defer allocator.free(nested_type_output);

            break :o try fmt.allocPrint(allocator, array_format, .{nested_type_output});
        },
        .slice => |d| o: {
            const nested_type_output = try encoderForType(allocator, name, d.@"type".*);
            defer allocator.free(nested_type_output);

            break :o try fmt.allocPrint(allocator, array_format, .{nested_type_output});
        },
        .optional => |d| try encoderForType(allocator, name, d.@"type".*),
        .applied_name => |d| o: {
            const nested_type_output = try encoderForTypeReference(allocator, d.reference);
            defer allocator.free(nested_type_output);

            break :o try fmt.allocPrint(
                allocator,
                applied_name_format,
                .{ d.reference.name(), nested_type_output },
            );
        },
        .empty => debug.panic("Structure field cannot be empty\n", .{}),
    };
}

fn encoderForTypeReference(allocator: *mem.Allocator, r: TypeReference) ![]const u8 {
    return switch (r) {
        .builtin => |d| try encoderForBuiltin(allocator, d),
        .definition => |d| try encoderForDefinition(allocator, d),
        .loose => |d| try fmt.allocPrint(allocator, "{}.Encoder", .{d.name}),
        .open => |d| try fmt.allocPrint(allocator, "encode{}", .{d}),
    };
}

fn encoderForBuiltin(allocator: *mem.Allocator, b: Builtin) ![]const u8 {
    return try allocator.dupe(u8, switch (b) {
        .String => "Encode.string",
        .Boolean => "Encode.boolean",
        .U8 => "Encode.uint8",
        .U16 => "Encode.uint16",
        .U32 => "Encode.uint32",
        .U64 => "Encode.uint64",
        .U128 => "Encode.uint128",
        .I8 => "Encode.int8",
        .I16 => "Encode.int16",
        .I32 => "Encode.int32",
        .I64 => "Encode.int64",
        .I128 => "Encode.int128",
        .F32 => "Encode.float32",
        .F64 => "Encode.float64",
        .F128 => "Encode.float128",
    });
}

fn encoderForDefinition(allocator: *mem.Allocator, d: Definition) ![]const u8 {
    return switch (d) {
        .structure => |s| switch (s) {
            .plain => |p| try fmt.allocPrint(allocator, "{}.Encoder", .{p.name.value}),
            .generic => debug.panic("Generic structure does not have encoder yet.\n", .{}),
        },
        .@"union" => debug.panic("Union does not have encoder yet.\n", .{}),
        .untagged_union => debug.panic("Untagged union does not have encoder yet.\n", .{}),
        .enumeration => debug.panic("Enumeration does not have encoder yet.\n", .{}),
        .import => debug.panic("Import cannot have encoder\n", .{}),
    };
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
        \\
        \\    static member Decoder: Decoder<Person>
        \\        (fun get ->
        \\            {
        \\              type = get.Required.Field "type" (GotynoCoders.decodeLiteralString "Person")
        \\              name = get.Required.Field "name" Decode.string
        \\              age = get.Required.Field "age" Decode.uint8
        \\              efficiency = get.Required.Field "efficiency" Decode.float32
        \\              on_vacation = get.Required.Field "on_vacation" Decode.boolean
        \\              hobbies = get.Required.Field "hobbies" (Decode.list Decode.string)
        \\              last_fifteen_comments = get.Required.Field "last_fifteen_comments" (Decode.list Decode.string)
        \\              recruiter = get.Required.Field "recruiter" Person.Decoder
        \\            }
        \\        )
        \\
        \\    static member Encoder value =
        \\        Encode.object
        \\            [
        \\                "type", Encode.string "Person"
        \\                "name", Encode.string value.name
        \\                "age", Encode.uint8 value.age
        \\                "efficiency", Encode.float32 value.efficiency
        \\                "on_vacation", Encode.boolean value.on_vacation
        \\                "hobbies", GotynoCoders.encodeList Encode.string value.hobbies
        \\                "last_fifteen_comments", GotynoCoders.encodeList Encode.string value.last_fifteen_comments
        \\                "recruiter", Person.Encoder value.recruiter
        \\            ]
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
