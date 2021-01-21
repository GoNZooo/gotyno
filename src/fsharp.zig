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

    const format =
        \\type {s} =
        \\    {{
        \\{s}
        \\    }}
        \\
        \\{s}
        \\
        \\{s}
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
        \\    static member Decoder: Decoder<{s}> =
        \\        Decode.object (fun get ->
        \\            {{
        \\{s}
        \\            }}
        \\        )
    ;

    return try fmt.allocPrint(allocator, format, .{ s.name.value, decoders_output });
}

fn outputDecoderForGenericStructure(allocator: *mem.Allocator, s: GenericStructure) ![]const u8 {
    var decoder_outputs = ArrayList([]const u8).init(allocator);
    defer utilities.freeStringList(decoder_outputs);

    const type_variables = try openNamesAsFSharpTypeVariables(allocator, s.open_names);
    defer utilities.freeStringArray(allocator, type_variables);

    const joined_type_variables = try mem.join(allocator, ", ", type_variables);
    defer allocator.free(joined_type_variables);

    var open_name_decoders = try allocator.alloc([]const u8, s.open_names.len);
    defer utilities.freeStringArray(allocator, open_name_decoders);
    for (open_name_decoders) |*d, i| {
        d.* = try fmt.allocPrint(allocator, "decode{s}", .{s.open_names[i]});
    }

    for (s.fields) |f| {
        try decoder_outputs.append(try outputDecoderForField(allocator, f));
    }

    const decoders_output = try mem.join(allocator, "\n", decoder_outputs.items);
    defer allocator.free(decoders_output);

    const joined_open_name_decoders = try mem.join(allocator, " ", open_name_decoders);
    defer allocator.free(joined_open_name_decoders);

    const format =
        \\    static member Decoder {s}: Decoder<{s}<{s}>> =
        \\        Decode.object (fun get ->
        \\            {{
        \\{s}
        \\            }}
        \\        )
    ;

    return try fmt.allocPrint(
        allocator,
        format,
        .{ joined_open_name_decoders, s.name.value, joined_type_variables, decoders_output },
    );
}

fn isKeyword(string: []const u8) bool {
    return utilities.isStringEqualToOneOf(string, &[_][]const u8{ "type", "private" });
}

fn maybeEscapeName(allocator: *mem.Allocator, name: []const u8) ![]const u8 {
    return if (isKeyword(name))
        try fmt.allocPrint(allocator, "``{s}``", .{name})
    else
        try allocator.dupe(u8, name);
}

fn outputDecoderForField(allocator: *mem.Allocator, f: Field) ![]const u8 {
    const decoder = try decoderForType(allocator, f.@"type");
    defer allocator.free(decoder);

    const name = try maybeEscapeName(allocator, f.name);
    defer allocator.free(name);

    const format = "              {s} = get.Required.Field \"{s}\" {s}";
    const format_for_optional = "              {s} = get.Optional.Field \"{s}\" {s}";

    return switch (f.@"type") {
        .optional => try fmt.allocPrint(allocator, format_for_optional, .{ name, f.name, decoder }),
        else => try fmt.allocPrint(allocator, format, .{ name, f.name, decoder }),
    };
}

fn decoderForType(allocator: *mem.Allocator, t: Type) error{OutOfMemory}![]const u8 {
    const array_format = "(Decode.list {s})";
    const applied_name_format = "({s} {s})";
    const string_format = "(GotynoCoders.decodeLiteralString \"{s}\")";

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
        .loose => |d| try fmt.allocPrint(allocator, "{s}.Decoder", .{d.name}),
        .open => |d| try fmt.allocPrint(allocator, "decode{s}", .{d}),
    };
}

fn decoderForBuiltin(allocator: *mem.Allocator, b: Builtin) ![]const u8 {
    return try allocator.dupe(u8, switch (b) {
        .String => "Decode.string",
        .Boolean => "Decode.bool",
        .U8 => "Decode.byte",
        .U16 => "Decode.uint16",
        .U32 => "Decode.uint32",
        .U64 => "Decode.uint64",
        .U128 => "Decode.uint128",
        .I8 => "Decode.sbyte",
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
            .plain => |p| try fmt.allocPrint(allocator, "{s}.Decoder", .{p.name.value}),
            .generic => debug.panic("Generic structure does not have decoder yet.\n", .{}),
        },
        .@"union" => debug.panic("Union does not have decoder yet.\n", .{}),
        .untagged_union => debug.panic("Untagged union does not have decoder yet.\n", .{}),
        .enumeration => debug.panic("Enumeration does not have decoder yet.\n", .{}),
        .import => debug.panic("Import cannot have decoder\n", .{}),
    };
}

fn outputEncoderForPlainStructure(allocator: *mem.Allocator, s: PlainStructure) ![]const u8 {
    const encoders_output = try outputEncodersForFields(allocator, s.fields, 16, "value");
    defer allocator.free(encoders_output);

    const format =
        \\    static member Encoder value =
        \\        Encode.object
        \\            [
        \\{s}
        \\            ]
    ;

    return try fmt.allocPrint(allocator, format, .{encoders_output});
}

fn outputEncoderForGenericStructure(allocator: *mem.Allocator, s: GenericStructure) ![]const u8 {
    const encoders_output = try outputEncodersForFields(allocator, s.fields, 16, "value");
    defer allocator.free(encoders_output);

    var open_name_encoders = try allocator.alloc([]const u8, s.open_names.len);
    defer utilities.freeStringArray(allocator, open_name_encoders);
    for (open_name_encoders) |*e, i| {
        e.* = try fmt.allocPrint(allocator, "encode{s}", .{s.open_names[i]});
    }

    const joined_open_name_encoders = try mem.join(allocator, " ", open_name_encoders);
    defer allocator.free(joined_open_name_encoders);

    const format =
        \\    static member Encoder {s} value =
        \\        Encode.object
        \\            [
        \\{s}
        \\            ]
    ;

    return try fmt.allocPrint(allocator, format, .{ joined_open_name_encoders, encoders_output });
}

fn outputEncodersForFields(
    allocator: *mem.Allocator,
    fields: []const Field,
    comptime indentation: usize,
    comptime value_name: []const u8,
) ![]const u8 {
    var encoder_outputs = ArrayList([]const u8).init(allocator);
    defer utilities.freeStringList(encoder_outputs);

    for (fields) |f| {
        try encoder_outputs.append(try outputEncoderForField(allocator, f, indentation, value_name));
    }

    return try mem.join(allocator, "\n", encoder_outputs.items);
}

fn outputEncoderForField(
    allocator: *mem.Allocator,
    f: Field,
    comptime indentation: usize,
    comptime value_name: []const u8,
) ![]const u8 {
    var indentation_buffer = [_]u8{' '} ** indentation;

    const encoder = try encoderForType(allocator, f.name, f.@"type", value_name);
    defer allocator.free(encoder);

    const format = "{s}\"{s}\", {s}";

    return try fmt.allocPrint(allocator, format, .{ indentation_buffer, f.name, encoder });
}

fn encoderForType(allocator: *mem.Allocator, field_name: ?[]const u8, t: Type, comptime value_name: ?[]const u8) error{OutOfMemory}![]const u8 {
    const array_format = "GotynoCoders.encodeList {s}";
    const applied_name_format = "({s} {s})";
    const string_format = "Encode.string \"{s}\"";

    return switch (t) {
        .string => |s| try fmt.allocPrint(allocator, string_format, .{s}),
        .reference => |d| o: {
            const encoder = try encoderForTypeReference(allocator, d);

            if (value_name != null and field_name != null) {
                defer allocator.free(encoder);
                const escaped_field_name = try maybeEscapeName(allocator, field_name.?);
                defer allocator.free(escaped_field_name);

                break :o try fmt.allocPrint(
                    allocator,
                    "{s} {s}.{s}",
                    .{ encoder, value_name.?, escaped_field_name },
                );
            } else
                break :o encoder;
        },
        .pointer => |d| try encoderForType(allocator, field_name, d.@"type".*, value_name),
        .array => |d| o: {
            const nested_type_output = try encoderForType(allocator, field_name, d.@"type".*, value_name);
            defer allocator.free(nested_type_output);

            break :o try fmt.allocPrint(allocator, array_format, .{nested_type_output});
        },
        .slice => |d| o: {
            const nested_type_output = try encoderForType(allocator, field_name, d.@"type".*, value_name);
            defer allocator.free(nested_type_output);

            break :o try fmt.allocPrint(allocator, array_format, .{nested_type_output});
        },
        .optional => |d| try encoderForType(allocator, field_name, d.@"type".*, value_name),
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
        .loose => |d| try fmt.allocPrint(allocator, "{s}.Encoder", .{d.name}),
        .open => |d| try fmt.allocPrint(allocator, "encode{s}", .{d}),
    };
}

fn encoderForBuiltin(allocator: *mem.Allocator, b: Builtin) ![]const u8 {
    return try allocator.dupe(u8, switch (b) {
        .String => "Encode.string",
        .Boolean => "Encode.bool",
        .U8 => "Encode.byte",
        .U16 => "Encode.uint16",
        .U32 => "Encode.uint32",
        .U64 => "Encode.uint64",
        .U128 => "Encode.uint128",
        .I8 => "Encode.sbyte",
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
            .plain => |p| try fmt.allocPrint(allocator, "{s}.Encoder", .{p.name.value}),
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

    const format = "        {s}: {s}";

    const name = try maybeEscapeName(allocator, field.name);
    defer allocator.free(name);

    return try fmt.allocPrint(allocator, format, .{ name, type_output });
}

fn outputStructureFieldType(allocator: *mem.Allocator, t: Type) error{OutOfMemory}![]const u8 {
    const array_format = "list<{s}>";
    const optional_format = "option<{s}>";
    const applied_name_format = "{s}<{s}>";

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

            const fsharped_open_names = try openNamesAsFSharpTypeVariables(allocator, d.open_names);
            defer utilities.freeStringArray(allocator, fsharped_open_names);

            const joined_open_names = try mem.join(allocator, ", ", fsharped_open_names);
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
        .open => |o| try makeFSharpTypeVariable(allocator, o),
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

        break :o try fmt.allocPrint(allocator, "{s}<{s}>", .{ l.name, joined_open_names });
    };
}

fn outputGenericStructure(allocator: *mem.Allocator, s: GenericStructure) ![]const u8 {
    const type_variables = try openNamesAsFSharpTypeVariables(allocator, s.open_names);
    defer utilities.freeStringArray(allocator, type_variables);

    const fields = try outputStructureFields(allocator, s.fields);
    defer allocator.free(fields);

    const joined_type_variables = try mem.join(allocator, ", ", type_variables);
    defer allocator.free(joined_type_variables);

    const decoder_output = try outputDecoderForGenericStructure(allocator, s);
    defer allocator.free(decoder_output);

    const encoder_output = try outputEncoderForGenericStructure(allocator, s);
    defer allocator.free(encoder_output);

    const format =
        \\type {s}<{s}> =
        \\    {{
        \\{s}
        \\    }}
        \\
        \\{s}
        \\
        \\{s}
    ;

    return try fmt.allocPrint(
        allocator,
        format,
        .{ s.name.value, joined_type_variables, fields, decoder_output, encoder_output },
    );
}

fn openNamesAsFSharpTypeVariables(
    allocator: *mem.Allocator,
    open_names: []const []const u8,
) ![]const []const u8 {
    const type_variables = try allocator.alloc([]const u8, open_names.len);

    for (type_variables) |*v, i| {
        v.* = try makeFSharpTypeVariable(allocator, open_names[i]);
    }

    return type_variables;
}

fn makeFSharpTypeVariable(allocator: *mem.Allocator, name: []const u8) ![]const u8 {
    const lowercased_name = try utilities.camelCaseWord(allocator, name);
    defer allocator.free(lowercased_name);

    return try fmt.allocPrint(allocator, "'{s}", .{lowercased_name});
}

fn outputPlainUnion(allocator: *mem.Allocator, s: PlainUnion) ![]const u8 {
    var constructor_outputs = ArrayList([]const u8).init(allocator);
    defer utilities.freeStringList(constructor_outputs);

    var titlecased_tags = try allocator.alloc([]const u8, s.constructors.len);
    defer allocator.free(titlecased_tags);
    defer for (titlecased_tags) |t| {
        allocator.free(t);
    };
    for (titlecased_tags) |*t, i| {
        t.* = try utilities.titleCaseWord(allocator, s.constructors[i].tag);
    }

    for (s.constructors) |c, i| {
        try constructor_outputs.append(try outputConstructor(
            allocator,
            titlecased_tags[i],
            c.parameter,
        ));
    }

    const joined_constructors = try mem.join(allocator, "\n", constructor_outputs.items);
    defer allocator.free(joined_constructors);

    const decoder_output = try outputDecoderForUnion(
        allocator,
        s.name.value,
        titlecased_tags,
        s.constructors,
        s.tag_field,
    );
    defer allocator.free(decoder_output);

    const encoder_output = try outputEncoderForUnion(
        allocator,
        titlecased_tags,
        s.constructors,
        s.tag_field,
    );
    defer allocator.free(encoder_output);

    const format =
        \\type {s} =
        \\{s}
        \\
        \\{s}
        \\
        \\{s}
    ;

    return try fmt.allocPrint(allocator, format, .{
        s.name.value,
        joined_constructors,
        decoder_output,
        encoder_output,
    });
}

fn outputConstructor(allocator: *mem.Allocator, name: []const u8, parameter: Type) ![]const u8 {
    const format =
        \\    | {s}{s}
    ;

    const parameter_output = try outputConstructorParameter(allocator, parameter);
    defer allocator.free(parameter_output);

    return try fmt.allocPrint(allocator, format, .{ name, parameter_output });
}

fn outputConstructorParameter(allocator: *mem.Allocator, p: Type) ![]const u8 {
    return switch (p) {
        .empty => try allocator.dupe(u8, ""),
        else => o: {
            const type_output = try outputStructureFieldType(allocator, p);
            defer allocator.free(type_output);

            break :o fmt.allocPrint(allocator, " of {s}", .{type_output});
        },
    };
}

fn outputDecoderForUnion(
    allocator: *mem.Allocator,
    union_name: []const u8,
    tags: []const []const u8,
    constructors: []const Constructor,
    tag_field: []const u8,
) ![]const u8 {
    var constructor_decoders = ArrayList([]const u8).init(allocator);
    defer utilities.freeStringList(constructor_decoders);
    var tag_decoder_pairs = ArrayList([]const u8).init(allocator);
    defer utilities.freeStringList(tag_decoder_pairs);

    for (constructors) |c, i| {
        const format =
            \\    static member {s}Decoder: Decoder<{s}> =
            \\        Decode.object (fun get -> {s}(get.Required.Field "data" {s}))
        ;

        const format_without_parameter =
            \\    static member {s}Decoder: Decoder<{s}> =
            \\        Decode.succeed {s}
        ;

        const titlecased_tag = tags[i];

        const constructor_decoder_output = switch (c.parameter) {
            .empty => try fmt.allocPrint(
                allocator,
                format_without_parameter,
                .{ titlecased_tag, union_name, titlecased_tag },
            ),
            else => o: {
                const parameter_decoder_output = try decoderForType(allocator, c.parameter);
                defer allocator.free(parameter_decoder_output);

                break :o try fmt.allocPrint(
                    allocator,
                    format,
                    .{ titlecased_tag, union_name, titlecased_tag, parameter_decoder_output },
                );
            },
        };

        const indentation = "                ";
        const tag_decoder_pair = try fmt.allocPrint(
            allocator,
            "{s}\"{s}\", {s}.{s}Decoder",
            .{ indentation, c.tag, union_name, titlecased_tag },
        );

        try constructor_decoders.append(constructor_decoder_output);
        try tag_decoder_pairs.append(tag_decoder_pair);
    }

    const joined_constructor_decoders = try mem.join(allocator, "\n\n", constructor_decoders.items);
    defer allocator.free(joined_constructor_decoders);

    const joined_tag_decoder_pairs = try mem.join(allocator, "\n", tag_decoder_pairs.items);
    defer allocator.free(joined_tag_decoder_pairs);

    const union_decoder_format =
        \\    static member Decoder: Decoder<{s}> =
        \\        GotynoCoders.decodeWithTypeTag
        \\            "{s}"
        \\            [|
        \\{s}
        \\            |]
    ;

    const union_decoder = try fmt.allocPrint(
        allocator,
        union_decoder_format,
        .{ union_name, tag_field, joined_tag_decoder_pairs },
    );
    defer allocator.free(union_decoder);

    const format =
        \\{s}
        \\
        \\{s}
    ;

    return try fmt.allocPrint(allocator, format, .{ joined_constructor_decoders, union_decoder });
}

fn outputEncoderForUnion(
    allocator: *mem.Allocator,
    tags: []const []const u8,
    constructors: []const Constructor,
    tag_field: []const u8,
) ![]const u8 {
    var encoder_clauses = ArrayList([]const u8).init(allocator);
    defer utilities.freeStringList(encoder_clauses);

    for (constructors) |c, i| {
        const indentation = "        ";
        const format =
            \\{s}| {s} payload ->
            \\{s}    Encode.object [ "{s}", Encode.string "{s}"
            \\{s}                    "data", {s} payload ]
        ;

        const format_without_parameter =
            \\{s}| {s} ->
            \\{s}    Encode.object [ "{s}", Encode.string "{s}" ]
        ;

        const titlecased_tag = tags[i];

        const constructor_encoder_output = switch (c.parameter) {
            .empty => try fmt.allocPrint(
                allocator,
                format_without_parameter,
                .{ indentation, titlecased_tag, indentation, tag_field, c.tag },
            ),
            else => o: {
                const parameter_encoder_output = try encoderForType(allocator, null, c.parameter, null);
                defer allocator.free(parameter_encoder_output);

                break :o try fmt.allocPrint(
                    allocator,
                    format,
                    .{
                        indentation,
                        titlecased_tag,
                        indentation,
                        tag_field,
                        c.tag,
                        indentation,
                        parameter_encoder_output,
                    },
                );
            },
        };

        try encoder_clauses.append(constructor_encoder_output);
    }

    const joined_encoder_clauses = try mem.join(allocator, "\n\n", encoder_clauses.items);
    defer allocator.free(joined_encoder_clauses);

    const format =
        \\    static member Encoder =
        \\        function
        \\{s}
    ;

    return try fmt.allocPrint(allocator, format, .{joined_encoder_clauses});
}

fn outputGenericUnion(allocator: *mem.Allocator, u: GenericUnion) ![]const u8 {
    var type_variables = try openNamesAsFSharpTypeVariables(allocator, u.open_names);
    defer utilities.freeStringArray(allocator, type_variables);

    const joined_type_variables = try mem.join(allocator, ", ", type_variables);
    defer allocator.free(joined_type_variables);

    var constructors = try allocator.alloc([]const u8, u.constructors.len);
    defer utilities.freeStringArray(allocator, constructors);
    for (constructors) |*c, i| {
        c.* = try outputConstructor(allocator, u.constructors[i].tag, u.constructors[i].parameter);
    }
    const joined_constructors = try mem.join(allocator, "\n", constructors);
    defer allocator.free(joined_constructors);

    var titlecased_tags = try allocator.alloc([]const u8, u.constructors.len);
    defer utilities.freeStringArray(allocator, titlecased_tags);
    for (titlecased_tags) |*t, i| {
        t.* = try utilities.titleCaseWord(allocator, u.constructors[i].tag);
    }

    const decoder_output = try outputDecoderForGenericUnion(allocator, u, titlecased_tags);
    defer allocator.free(decoder_output);

    const encoder_output = try outputEncoderForGenericUnion(allocator, u, titlecased_tags);
    defer allocator.free(encoder_output);

    const format =
        \\type {s}<{s}> =
        \\{s}
        \\
        \\{s}
        \\
        \\{s}
    ;

    return try fmt.allocPrint(
        allocator,
        format,
        .{
            u.name.value,
            joined_type_variables,
            joined_constructors,
            decoder_output,
            encoder_output,
        },
    );
}

fn outputDecoderForGenericUnion(allocator: *mem.Allocator, u: GenericUnion, tags: []const []const u8) ![]const u8 {
    const union_name = u.name.value;

    const type_variables = try openNamesAsFSharpTypeVariables(allocator, u.open_names);
    defer utilities.freeStringArray(allocator, type_variables);

    const joined_type_variables = try mem.join(allocator, ", ", type_variables);
    defer allocator.free(joined_type_variables);

    const tag_decoder_pairs = try allocator.alloc([]const u8, u.constructors.len);
    defer utilities.freeStringArray(allocator, tag_decoder_pairs);

    const constructor_decoders = try allocator.alloc([]const u8, u.constructors.len);
    defer utilities.freeStringArray(allocator, constructor_decoders);

    var union_open_name_decoders = try allocator.alloc([]const u8, u.open_names.len);
    defer utilities.freeStringArray(allocator, union_open_name_decoders);
    for (union_open_name_decoders) |*d, i| {
        d.* = try fmt.allocPrint(allocator, "decode{s}", .{u.open_names[i]});
    }
    const joined_union_open_name_decoders = try mem.join(allocator, " ", union_open_name_decoders);
    defer allocator.free(joined_union_open_name_decoders);

    for (tag_decoder_pairs) |*p, i| {
        const c = u.constructors[i];

        const open_names_for_constructor = try general.openNamesFromType(
            allocator,
            c.parameter,
            u.open_names,
        );
        defer utilities.freeStringList(open_names_for_constructor);
        var open_name_decoders = try allocator.alloc([]const u8, open_names_for_constructor.items.len);
        defer utilities.freeStringArray(allocator, open_name_decoders);
        for (open_name_decoders) |*d, di| {
            d.* = try fmt.allocPrint(allocator, "decode{s}", .{open_names_for_constructor.items[di]});
        }

        const joined_open_name_decoders = try mem.join(allocator, " ", open_name_decoders);
        defer allocator.free(joined_open_name_decoders);
        const space_for_decoder = if (open_names_for_constructor.items.len > 0) " " else "";

        p.* = try fmt.allocPrint(
            allocator,
            "                \"{s}\", {s}.{s}Decoder{s}{s}",
            .{
                u.constructors[i].tag,
                u.name.value,
                u.constructors[i].tag,
                space_for_decoder,
                joined_open_name_decoders,
            },
        );

        const format =
            \\    static member {s}Decoder{s}{s}: Decoder<{s}<{s}>> =
            \\        Decode.object (fun get -> {s}(get.Required.Field "data" {s}))
        ;

        const format_without_parameter =
            \\    static member {s}Decoder: Decoder<{s}<{s}>> =
            \\        Decode.succeed {s}
        ;

        const titlecased_tag = tags[i];

        const constructor_decoder_output = switch (c.parameter) {
            .empty => try fmt.allocPrint(
                allocator,
                format_without_parameter,
                .{ titlecased_tag, union_name, joined_type_variables, titlecased_tag },
            ),
            else => o: {
                const parameter_decoder_output = try decoderForType(allocator, c.parameter);
                defer allocator.free(parameter_decoder_output);

                break :o try fmt.allocPrint(
                    allocator,
                    format,
                    .{
                        titlecased_tag,
                        space_for_decoder,
                        joined_open_name_decoders,
                        union_name,
                        joined_type_variables,
                        titlecased_tag,
                        parameter_decoder_output,
                    },
                );
            },
        };

        constructor_decoders[i] = constructor_decoder_output;
    }

    const joined_tag_decoder_pairs = try mem.join(allocator, "\n", tag_decoder_pairs);
    defer allocator.free(joined_tag_decoder_pairs);

    const joined_constructor_decoders = try mem.join(allocator, "\n\n", constructor_decoders);
    defer allocator.free(joined_constructor_decoders);

    const format =
        \\{s}
        \\
        \\    static member Decoder {s}: Decoder<{s}<{s}>> =
        \\        GotynoCoders.decodeWithTypeTag
        \\            "{s}"
        \\            [|
        \\{s}
        \\            |]
    ;

    return try fmt.allocPrint(
        allocator,
        format,
        .{
            joined_constructor_decoders,
            joined_union_open_name_decoders,
            u.name.value,
            joined_type_variables,
            u.tag_field,
            joined_tag_decoder_pairs,
        },
    );
}

fn outputEncoderForGenericUnion(allocator: *mem.Allocator, u: GenericUnion, tags: []const []const u8) ![]const u8 {
    const union_name = u.name.value;

    const type_variables = try openNamesAsFSharpTypeVariables(allocator, u.open_names);
    defer utilities.freeStringArray(allocator, type_variables);

    const joined_type_variables = try mem.join(allocator, ", ", type_variables);
    defer allocator.free(joined_type_variables);

    const constructor_encoders = try allocator.alloc([]const u8, u.constructors.len);
    defer utilities.freeStringArray(allocator, constructor_encoders);

    var union_open_name_encoders = try allocator.alloc([]const u8, u.open_names.len);
    defer utilities.freeStringArray(allocator, union_open_name_encoders);
    for (union_open_name_encoders) |*d, i| {
        d.* = try fmt.allocPrint(allocator, "encode{s}", .{u.open_names[i]});
    }
    const joined_union_open_name_encoders = try mem.join(allocator, " ", union_open_name_encoders);
    defer allocator.free(joined_union_open_name_encoders);

    for (constructor_encoders) |*e, i| {
        const c = u.constructors[i];

        const open_names_for_constructor = try general.openNamesFromType(
            allocator,
            c.parameter,
            u.open_names,
        );
        defer utilities.freeStringList(open_names_for_constructor);

        const format =
            \\        | {s} payload ->
            \\            Encode.object [ "{s}", Encode.string "{s}"
            \\                            "data", {s} payload ]
        ;

        const format_without_parameter =
            \\        | {s} ->
            \\            Encode.object [ "{s}", Encode.string "{s}" ]
        ;

        const titlecased_tag = tags[i];

        const constructor_encoder_output = switch (c.parameter) {
            .empty => try fmt.allocPrint(
                allocator,
                format_without_parameter,
                .{ titlecased_tag, u.tag_field, c.tag },
            ),
            else => o: {
                const parameter_encoder_output = try encoderForType(
                    allocator,
                    null,
                    c.parameter,
                    "payload",
                );
                defer allocator.free(parameter_encoder_output);

                break :o try fmt.allocPrint(
                    allocator,
                    format,
                    .{
                        titlecased_tag,
                        u.tag_field,
                        c.tag,
                        parameter_encoder_output,
                    },
                );
            },
        };

        e.* = constructor_encoder_output;
    }

    const joined_constructor_encoders = try mem.join(allocator, "\n\n", constructor_encoders);
    defer allocator.free(joined_constructor_encoders);

    const format =
        \\    static member Encoder {s} =
        \\        function
        \\{s}
    ;

    return try fmt.allocPrint(
        allocator,
        format,
        .{
            joined_union_open_name_encoders,
            joined_constructor_encoders,
        },
    );
}

fn outputEmbeddedUnion(allocator: *mem.Allocator, s: EmbeddedUnion) ![]const u8 {
    var constructor_outputs = ArrayList([]const u8).init(allocator);
    defer utilities.freeStringList(constructor_outputs);

    var tag_decoder_pairs = ArrayList([]const u8).init(allocator);
    defer utilities.freeStringList(tag_decoder_pairs);

    var constructor_encoders = ArrayList([]const u8).init(allocator);
    defer utilities.freeStringList(constructor_encoders);

    for (s.constructors) |c| {
        const format_with_payload = "    | {s} {s}";
        const format_without_payload = "    | {s}";
        const titlecased_tag = try utilities.titleCaseWord(allocator, c.tag);
        defer allocator.free(titlecased_tag);

        if (c.parameter) |p| {
            const parameter_name = p.name().value;

            const tag_decoder_pair_indentation = "                ";
            const tag_decoder_pair_format = "{s}\"{s}\", {s}.Decoder";

            var fields_with_type_field = ArrayList(Field).init(allocator);
            defer fields_with_type_field.deinit();
            try fields_with_type_field.append(Field{
                .name = s.tag_field,
                .@"type" = Type{ .string = c.tag },
            });
            const fields = switch (p) {
                .plain => |plain| plain.fields,
                .generic => |generic| generic.fields,
            };
            try fields_with_type_field.appendSlice(fields);

            const joined_field_encoders = try outputEncodersForFields(
                allocator,
                fields_with_type_field.items,
                20,
                "payload",
            );
            defer allocator.free(joined_field_encoders);

            const constructor_encoder_format =
                \\        | {s} payload ->
                \\            Encode.object
                \\                [
                \\{s}
                \\                ]
            ;

            try constructor_outputs.append(try fmt.allocPrint(
                allocator,
                format_with_payload,
                .{ titlecased_tag, parameter_name },
            ));

            try tag_decoder_pairs.append(try fmt.allocPrint(
                allocator,
                tag_decoder_pair_format,
                .{ tag_decoder_pair_indentation, c.tag, parameter_name },
            ));

            try constructor_encoders.append(try fmt.allocPrint(
                allocator,
                constructor_encoder_format,
                .{ titlecased_tag, joined_field_encoders },
            ));
        } else {
            const tag_decoder_pair_indentation = "                ";
            const tag_decoder_pair_format = "{s}\"{s}\", Decode.succeed";

            const constructor_encoder_format =
                \\        | {s} ->
                \\            Encode.object [ "{s}", Encode.string "{s}" ]
            ;

            try constructor_outputs.append(try fmt.allocPrint(
                allocator,
                format_without_payload,
                .{titlecased_tag},
            ));

            try tag_decoder_pairs.append(try fmt.allocPrint(
                allocator,
                tag_decoder_pair_format,
                .{ tag_decoder_pair_indentation, c.tag },
            ));

            try constructor_encoders.append(try fmt.allocPrint(
                allocator,
                constructor_encoder_format,
                .{ titlecased_tag, s.tag_field, c.tag },
            ));
        }
    }

    const joined_constructors = try mem.join(allocator, "\n", constructor_outputs.items);
    defer allocator.free(joined_constructors);

    const joined_tag_decoder_pairs = try mem.join(allocator, "\n", tag_decoder_pairs.items);
    defer allocator.free(joined_tag_decoder_pairs);

    const decoder_format =
        \\    static member Decoder: Decoder<{s}> =
        \\        GotynoCoders.decodeWithTypeTag
        \\            "{s}"
        \\            [|
        \\{s}
        \\            |]
    ;
    const decoder_output = try fmt.allocPrint(
        allocator,
        decoder_format,
        .{ s.name.value, s.tag_field, joined_tag_decoder_pairs },
    );
    defer allocator.free(decoder_output);

    const joined_constructor_encoders = try mem.join(allocator, "\n\n", constructor_encoders.items);
    defer allocator.free(joined_constructor_encoders);

    const encoder_format =
        \\    static member Encoder =
        \\        function
        \\{s}
    ;
    const encoder_output = try fmt.allocPrint(
        allocator,
        encoder_format,
        .{joined_constructor_encoders},
    );
    defer allocator.free(encoder_output);

    const format =
        \\type {s} =
        \\{s}
        \\
        \\{s}
        \\
        \\{s}
    ;

    return try fmt.allocPrint(
        allocator,
        format,
        .{ s.name.value, joined_constructors, decoder_output, encoder_output },
    );
}

fn outputEnumeration(allocator: *mem.Allocator, e: Enumeration) ![]const u8 {
    var titlecased_tags = try allocator.alloc([]const u8, e.fields.len);
    defer allocator.free(titlecased_tags);

    for (titlecased_tags) |*t, i| {
        t.* = try utilities.titleCaseWord(allocator, e.fields[i].tag);
    }
    defer for (titlecased_tags) |t| {
        allocator.free(t);
    };

    var enumeration_tags = try allocator.alloc([]const u8, e.fields.len);
    defer allocator.free(enumeration_tags);
    for (enumeration_tags) |*t, i| {
        t.* = try fmt.allocPrint(allocator, "    | {s}", .{titlecased_tags[i]});
    }
    defer for (enumeration_tags) |t| {
        allocator.free(t);
    };

    const joined_enumeration_tags = try mem.join(allocator, "\n", enumeration_tags);
    defer allocator.free(joined_enumeration_tags);

    var value_constructors = try allocator.alloc([]const u8, e.fields.len);
    defer allocator.free(value_constructors);
    for (value_constructors) |*vc, i| {
        const value_as_string = try e.fields[i].value.toString(allocator);
        defer allocator.free(value_as_string);

        vc.* = try fmt.allocPrint(
            allocator,
            "{s}, {s}",
            .{ value_as_string, titlecased_tags[i] },
        );
    }
    defer for (value_constructors) |vc| {
        allocator.free(vc);
    };

    const joined_value_constructors = try mem.join(allocator, "; ", value_constructors);
    defer allocator.free(joined_value_constructors);

    debug.assert(e.fields.len > 0);
    const enumeration_value_decoder = switch (e.fields[0].value) {
        .string => "Decode.string",
        .unsigned_integer => "Decode.uint32",
    };

    const decoder_format =
        \\    static member Decoder: Decoder<{s}> =
        \\        GotynoCoders.decodeOneOf {s} [|{s}|]
    ;
    const decoder_output = try fmt.allocPrint(
        allocator,
        decoder_format,
        .{ e.name.value, enumeration_value_decoder, joined_value_constructors },
    );
    defer allocator.free(decoder_output);

    const value_encoder = switch (e.fields[0].value) {
        .string => "Encode.string",
        .unsigned_integer => "Encode.uint32",
    };

    var constructor_encoders = try allocator.alloc([]const u8, e.fields.len);
    defer allocator.free(constructor_encoders);
    for (constructor_encoders) |*constructor_encoder, i| {
        const value_as_string = try e.fields[i].value.toString(allocator);
        defer allocator.free(value_as_string);

        constructor_encoder.* = try fmt.allocPrint(
            allocator,
            "        | {s} -> {s} {s}",
            .{ titlecased_tags[i], value_encoder, value_as_string },
        );
    }
    defer for (constructor_encoders) |ce| {
        allocator.free(ce);
    };
    const joined_constructor_encoders = try mem.join(allocator, "\n", constructor_encoders);
    defer allocator.free(joined_constructor_encoders);

    const encoder_format =
        \\    static member Encoder =
        \\        function
        \\{s}
    ;
    const encoder_output = try fmt.allocPrint(
        allocator,
        encoder_format,
        .{joined_constructor_encoders},
    );
    defer allocator.free(encoder_output);

    const format =
        \\type {s} =
        \\{s}
        \\
        \\{s}
        \\
        \\{s}
    ;

    return try fmt.allocPrint(
        allocator,
        format,
        .{ e.name.value, joined_enumeration_tags, decoder_output, encoder_output },
    );
}

fn outputUntaggedUnion(allocator: *mem.Allocator, u: UntaggedUnion) ![]const u8 {
    var constructors = try allocator.alloc([]const u8, u.values.len);
    defer utilities.freeStringArray(allocator, constructors);

    var constructor_names = try allocator.alloc([]const u8, u.values.len);
    defer utilities.freeStringArray(allocator, constructor_names);
    for (constructor_names) |*n, i| {
        const value_type_name = try u.values[i].toString(allocator);
        defer allocator.free(value_type_name);

        n.* = try fmt.allocPrint(allocator, "{s}{s}", .{ u.name.value, value_type_name });
    }

    for (constructors) |*c, i| {
        const value_type = try outputTypeReference(allocator, u.values[i].reference);
        defer allocator.free(value_type);

        c.* = try fmt.allocPrint(
            allocator,
            "    | {s} of {s}",
            .{ constructor_names[i], value_type },
        );
    }

    const joined_constructors = try mem.join(allocator, "\n", constructors);
    defer allocator.free(joined_constructors);

    var decoder_pairs = try allocator.alloc([]const u8, u.values.len);
    defer utilities.freeStringArray(allocator, decoder_pairs);

    for (decoder_pairs) |*p, i| {
        const type_reference_decoder = try decoderForTypeReference(allocator, u.values[i].reference);
        defer allocator.free(type_reference_decoder);

        p.* = try fmt.allocPrint(
            allocator,
            "            {s}, {s}",
            .{ type_reference_decoder, constructor_names[i] },
        );
    }

    const joined_decoder_pairs = try mem.join(allocator, "\n", decoder_pairs);
    defer allocator.free(joined_decoder_pairs);

    const decoder_format =
        \\    static member Decoder: Decoder<{s}> =
        \\        GotynoCoders.decodeIntoOneOf
        \\        [|
        \\{s}
        \\        |]
    ;

    const decoder_output = try fmt.allocPrint(allocator, decoder_format, .{ u.name.value, joined_decoder_pairs });
    defer allocator.free(decoder_output);

    var constructor_encoders = try allocator.alloc([]const u8, u.values.len);
    defer utilities.freeStringArray(allocator, constructor_encoders);

    const constructor_encoder_format =
        \\        | {s} payload ->
        \\            {s} payload
    ;

    for (constructor_encoders) |*e, i| {
        const reference_encoder = try encoderForTypeReference(allocator, u.values[i].reference);
        defer allocator.free(reference_encoder);
        e.* = try fmt.allocPrint(
            allocator,
            constructor_encoder_format,
            .{ constructor_names[i], reference_encoder },
        );
    }

    const joined_constructor_encoders = try mem.join(allocator, "\n\n", constructor_encoders);
    defer allocator.free(joined_constructor_encoders);

    const encoder_format =
        \\    static member Encoder =
        \\        function
        \\{s}
    ;
    const encoder_output = try fmt.allocPrint(allocator, encoder_format, .{joined_constructor_encoders});
    defer allocator.free(encoder_output);

    const format =
        \\type {s} =
        \\{s}
        \\
        \\{s}
        \\
        \\{s}
    ;

    return try fmt.allocPrint(
        allocator,
        format,
        .{ u.name.value, joined_constructors, decoder_output, encoder_output },
    );
}

fn outputImport(allocator: *mem.Allocator, s: Import) ![]const u8 {
    return try allocator.dupe(u8, "");
}

test "outputs plain structure correctly" {
    var allocator = TestingAllocator{};

    const expected_output =
        \\type Person =
        \\    {
        \\        ``type``: string
        \\        name: string
        \\        age: uint8
        \\        efficiency: float32
        \\        on_vacation: bool
        \\        hobbies: list<string>
        \\        last_fifteen_comments: list<string>
        \\        recruiter: Person
        \\    }
        \\
        \\    static member Decoder: Decoder<Person> =
        \\        Decode.object (fun get ->
        \\            {
        \\              ``type`` = get.Required.Field "type" (GotynoCoders.decodeLiteralString "Person")
        \\              name = get.Required.Field "name" Decode.string
        \\              age = get.Required.Field "age" Decode.byte
        \\              efficiency = get.Required.Field "efficiency" Decode.float32
        \\              on_vacation = get.Required.Field "on_vacation" Decode.bool
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
        \\                "age", Encode.byte value.age
        \\                "efficiency", Encode.float32 value.efficiency
        \\                "on_vacation", Encode.bool value.on_vacation
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

test "outputs generic structure correctly" {
    var allocator = TestingAllocator{};

    const expected_output =
        \\type Node<'t, 'u> =
        \\    {
        \\        data: 't
        \\        otherData: 'u
        \\    }
        \\
        \\    static member Decoder decodeT decodeU: Decoder<Node<'t, 'u>> =
        \\        Decode.object (fun get ->
        \\            {
        \\              data = get.Required.Field "data" decodeT
        \\              otherData = get.Required.Field "otherData" decodeU
        \\            }
        \\        )
        \\
        \\    static member Encoder encodeT encodeU value =
        \\        Encode.object
        \\            [
        \\                "data", encodeT value.data
        \\                "otherData", encodeU value.otherData
        \\            ]
    ;

    var parsing_error: ParsingError = undefined;

    var definitions = try parser.parse(
        &allocator.allocator,
        &allocator.allocator,
        type_examples.node_structure,
        &parsing_error,
    );

    const output = try outputGenericStructure(
        &allocator.allocator,
        (definitions).definitions[0].structure.generic,
    );

    testing.expectEqualStrings(output, expected_output);

    definitions.deinit();
    allocator.allocator.free(output);
    testing_utilities.expectNoLeaks(&allocator);
}

test "outputs plain union correctly" {
    var allocator = TestingAllocator{};

    const expected_output =
        \\type Event =
        \\    | LogIn of LogInData
        \\    | LogOut of UserId
        \\    | JoinChannels of list<Channel>
        \\    | SetEmails of list<Email>
        \\    | Close
        \\
        \\    static member LogInDecoder: Decoder<Event> =
        \\        Decode.object (fun get -> LogIn(get.Required.Field "data" LogInData.Decoder))
        \\
        \\    static member LogOutDecoder: Decoder<Event> =
        \\        Decode.object (fun get -> LogOut(get.Required.Field "data" UserId.Decoder))
        \\
        \\    static member JoinChannelsDecoder: Decoder<Event> =
        \\        Decode.object (fun get -> JoinChannels(get.Required.Field "data" (Decode.list Channel.Decoder)))
        \\
        \\    static member SetEmailsDecoder: Decoder<Event> =
        \\        Decode.object (fun get -> SetEmails(get.Required.Field "data" (Decode.list Email.Decoder)))
        \\
        \\    static member CloseDecoder: Decoder<Event> =
        \\        Decode.succeed Close
        \\
        \\    static member Decoder: Decoder<Event> =
        \\        GotynoCoders.decodeWithTypeTag
        \\            "type"
        \\            [|
        \\                "LogIn", Event.LogInDecoder
        \\                "LogOut", Event.LogOutDecoder
        \\                "JoinChannels", Event.JoinChannelsDecoder
        \\                "SetEmails", Event.SetEmailsDecoder
        \\                "Close", Event.CloseDecoder
        \\            |]
        \\
        \\    static member Encoder =
        \\        function
        \\        | LogIn payload ->
        \\            Encode.object [ "type", Encode.string "LogIn"
        \\                            "data", LogInData.Encoder payload ]
        \\
        \\        | LogOut payload ->
        \\            Encode.object [ "type", Encode.string "LogOut"
        \\                            "data", UserId.Encoder payload ]
        \\
        \\        | JoinChannels payload ->
        \\            Encode.object [ "type", Encode.string "JoinChannels"
        \\                            "data", GotynoCoders.encodeList Channel.Encoder payload ]
        \\
        \\        | SetEmails payload ->
        \\            Encode.object [ "type", Encode.string "SetEmails"
        \\                            "data", GotynoCoders.encodeList Email.Encoder payload ]
        \\
        \\        | Close ->
        \\            Encode.object [ "type", Encode.string "Close" ]
    ;

    var parsing_error: ParsingError = undefined;

    var definitions = try parser.parse(
        &allocator.allocator,
        &allocator.allocator,
        type_examples.event_union,
        &parsing_error,
    );

    const output = try outputPlainUnion(
        &allocator.allocator,
        (definitions).definitions[4].@"union".plain,
    );

    testing.expectEqualStrings(output, expected_output);

    definitions.deinit();
    allocator.allocator.free(output);
    testing_utilities.expectNoLeaks(&allocator);
}

test "outputs plain union with lowercased constructors correctly" {
    var allocator = TestingAllocator{};

    const definition_buffer =
        \\struct LogInData {
        \\    username: String
        \\    password: String
        \\}
        \\
        \\struct UserId {
        \\    value: String
        \\}
        \\
        \\struct Channel {
        \\    name: String
        \\    private: Boolean
        \\}
        \\
        \\struct Email {
        \\    value: String
        \\}
        \\
        \\union Event {
        \\    logIn: LogInData
        \\    logOut: UserId
        \\    joinChannels: []Channel
        \\    setEmails: [5]Email
        \\    close
        \\}
    ;

    const expected_output =
        \\type Event =
        \\    | LogIn of LogInData
        \\    | LogOut of UserId
        \\    | JoinChannels of list<Channel>
        \\    | SetEmails of list<Email>
        \\    | Close
        \\
        \\    static member LogInDecoder: Decoder<Event> =
        \\        Decode.object (fun get -> LogIn(get.Required.Field "data" LogInData.Decoder))
        \\
        \\    static member LogOutDecoder: Decoder<Event> =
        \\        Decode.object (fun get -> LogOut(get.Required.Field "data" UserId.Decoder))
        \\
        \\    static member JoinChannelsDecoder: Decoder<Event> =
        \\        Decode.object (fun get -> JoinChannels(get.Required.Field "data" (Decode.list Channel.Decoder)))
        \\
        \\    static member SetEmailsDecoder: Decoder<Event> =
        \\        Decode.object (fun get -> SetEmails(get.Required.Field "data" (Decode.list Email.Decoder)))
        \\
        \\    static member CloseDecoder: Decoder<Event> =
        \\        Decode.succeed Close
        \\
        \\    static member Decoder: Decoder<Event> =
        \\        GotynoCoders.decodeWithTypeTag
        \\            "type"
        \\            [|
        \\                "logIn", Event.LogInDecoder
        \\                "logOut", Event.LogOutDecoder
        \\                "joinChannels", Event.JoinChannelsDecoder
        \\                "setEmails", Event.SetEmailsDecoder
        \\                "close", Event.CloseDecoder
        \\            |]
        \\
        \\    static member Encoder =
        \\        function
        \\        | LogIn payload ->
        \\            Encode.object [ "type", Encode.string "logIn"
        \\                            "data", LogInData.Encoder payload ]
        \\
        \\        | LogOut payload ->
        \\            Encode.object [ "type", Encode.string "logOut"
        \\                            "data", UserId.Encoder payload ]
        \\
        \\        | JoinChannels payload ->
        \\            Encode.object [ "type", Encode.string "joinChannels"
        \\                            "data", GotynoCoders.encodeList Channel.Encoder payload ]
        \\
        \\        | SetEmails payload ->
        \\            Encode.object [ "type", Encode.string "setEmails"
        \\                            "data", GotynoCoders.encodeList Email.Encoder payload ]
        \\
        \\        | Close ->
        \\            Encode.object [ "type", Encode.string "close" ]
    ;

    var parsing_error: ParsingError = undefined;

    var definitions = try parser.parse(
        &allocator.allocator,
        &allocator.allocator,
        definition_buffer,
        &parsing_error,
    );

    const output = try outputPlainUnion(
        &allocator.allocator,
        (definitions).definitions[4].@"union".plain,
    );

    testing.expectEqualStrings(output, expected_output);

    definitions.deinit();
    allocator.allocator.free(output);
    testing_utilities.expectNoLeaks(&allocator);
}

test "outputs Maybe union correctly" {
    var allocator = TestingAllocator{};

    const definition_buffer =
        \\union Maybe <T>{
        \\    Nothing
        \\    Just: T
        \\}
    ;

    const expected_output =
        \\type Maybe<'t> =
        \\    | Nothing
        \\    | Just of 't
        \\
        \\    static member NothingDecoder: Decoder<Maybe<'t>> =
        \\        Decode.succeed Nothing
        \\
        \\    static member JustDecoder decodeT: Decoder<Maybe<'t>> =
        \\        Decode.object (fun get -> Just(get.Required.Field "data" decodeT))
        \\
        \\    static member Decoder decodeT: Decoder<Maybe<'t>> =
        \\        GotynoCoders.decodeWithTypeTag
        \\            "type"
        \\            [|
        \\                "Nothing", Maybe.NothingDecoder
        \\                "Just", Maybe.JustDecoder decodeT
        \\            |]
        \\
        \\    static member Encoder encodeT =
        \\        function
        \\        | Nothing ->
        \\            Encode.object [ "type", Encode.string "Nothing" ]
        \\
        \\        | Just payload ->
        \\            Encode.object [ "type", Encode.string "Just"
        \\                            "data", encodeT payload ]
    ;

    var parsing_error: ParsingError = undefined;

    var definitions = try parser.parse(
        &allocator.allocator,
        &allocator.allocator,
        definition_buffer,
        &parsing_error,
    );

    const output = try outputGenericUnion(
        &allocator.allocator,
        (definitions).definitions[0].@"union".generic,
    );

    testing.expectEqualStrings(output, expected_output);

    definitions.deinit();
    allocator.allocator.free(output);
    testing_utilities.expectNoLeaks(&allocator);
}

test "Union with embedded tag is output correctly" {
    var allocator = TestingAllocator{};

    const definition_buffer =
        \\struct One {
        \\    field1: String
        \\}
        \\
        \\struct Two {
        \\    field2: F32
        \\    field3: Boolean
        \\}
        \\
        \\union(tag = media_type, embedded) Embedded {
        \\    WithOne: One
        \\    WithTwo: Two
        \\    Empty
        \\}
    ;

    const expected_output =
        \\type Embedded =
        \\    | WithOne One
        \\    | WithTwo Two
        \\    | Empty
        \\
        \\    static member Decoder: Decoder<Embedded> =
        \\        GotynoCoders.decodeWithTypeTag
        \\            "media_type"
        \\            [|
        \\                "WithOne", One.Decoder
        \\                "WithTwo", Two.Decoder
        \\                "Empty", Decode.succeed
        \\            |]
        \\
        \\    static member Encoder =
        \\        function
        \\        | WithOne payload ->
        \\            Encode.object
        \\                [
        \\                    "media_type", Encode.string "WithOne"
        \\                    "field1", Encode.string payload.field1
        \\                ]
        \\
        \\        | WithTwo payload ->
        \\            Encode.object
        \\                [
        \\                    "media_type", Encode.string "WithTwo"
        \\                    "field2", Encode.float32 payload.field2
        \\                    "field3", Encode.bool payload.field3
        \\                ]
        \\
        \\        | Empty ->
        \\            Encode.object [ "media_type", Encode.string "Empty" ]
    ;

    var parsing_error: ParsingError = undefined;
    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        definition_buffer,
        &parsing_error,
    );

    const output = try outputEmbeddedUnion(
        &allocator.allocator,
        definitions.definitions[2].@"union".embedded,
    );

    testing.expectEqualStrings(output, expected_output);

    definitions.deinit();
    allocator.allocator.free(output);
    testing_utilities.expectNoLeaks(&allocator);
}

test "Union with embedded tag and lowercase constructors is output correctly" {
    var allocator = TestingAllocator{};

    const definition_buffer =
        \\struct One {
        \\    field1: String
        \\}
        \\
        \\struct Two {
        \\    field2: F32
        \\    field3: Boolean
        \\}
        \\
        \\union(tag = media_type, embedded) Embedded {
        \\    withOne: One
        \\    withTwo: Two
        \\    empty
        \\}
    ;

    const expected_output =
        \\type Embedded =
        \\    | WithOne One
        \\    | WithTwo Two
        \\    | Empty
        \\
        \\    static member Decoder: Decoder<Embedded> =
        \\        GotynoCoders.decodeWithTypeTag
        \\            "media_type"
        \\            [|
        \\                "withOne", One.Decoder
        \\                "withTwo", Two.Decoder
        \\                "empty", Decode.succeed
        \\            |]
        \\
        \\    static member Encoder =
        \\        function
        \\        | WithOne payload ->
        \\            Encode.object
        \\                [
        \\                    "media_type", Encode.string "withOne"
        \\                    "field1", Encode.string payload.field1
        \\                ]
        \\
        \\        | WithTwo payload ->
        \\            Encode.object
        \\                [
        \\                    "media_type", Encode.string "withTwo"
        \\                    "field2", Encode.float32 payload.field2
        \\                    "field3", Encode.bool payload.field3
        \\                ]
        \\
        \\        | Empty ->
        \\            Encode.object [ "media_type", Encode.string "empty" ]
    ;

    var parsing_error: ParsingError = undefined;
    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        definition_buffer,
        &parsing_error,
    );

    const output = try outputEmbeddedUnion(
        &allocator.allocator,
        definitions.definitions[2].@"union".embedded,
    );

    testing.expectEqualStrings(output, expected_output);

    definitions.deinit();
    allocator.allocator.free(output);
    testing_utilities.expectNoLeaks(&allocator);
}

test "Enumeration is output correctly" {
    var allocator = TestingAllocator{};

    const definition_buffer =
        \\enum BackdropSize {
        \\    W300 = "w300"
        \\    W1280 = "w1280"
        \\    Original = "original"
        \\}
    ;

    const expected_output =
        \\type BackdropSize =
        \\    | W300
        \\    | W1280
        \\    | Original
        \\
        \\    static member Decoder: Decoder<BackdropSize> =
        \\        GotynoCoders.decodeOneOf Decode.string [|"w300", W300; "w1280", W1280; "original", Original|]
        \\
        \\    static member Encoder =
        \\        function
        \\        | W300 -> Encode.string "w300"
        \\        | W1280 -> Encode.string "w1280"
        \\        | Original -> Encode.string "original"
    ;

    var parsing_error: ParsingError = undefined;
    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        definition_buffer,
        &parsing_error,
    );

    const output = try outputEnumeration(
        &allocator.allocator,
        definitions.definitions[0].enumeration,
    );

    testing.expectEqualStrings(output, expected_output);

    definitions.deinit();
    allocator.allocator.free(output);
    testing_utilities.expectNoLeaks(&allocator);
}

test "Enumeration with lowercased tags is output correctly" {
    var allocator = TestingAllocator{};

    const definition_buffer =
        \\enum BackdropSize {
        \\    w300 = "w300"
        \\    w1280 = "w1280"
        \\    original = "original"
        \\}
    ;

    const expected_output =
        \\type BackdropSize =
        \\    | W300
        \\    | W1280
        \\    | Original
        \\
        \\    static member Decoder: Decoder<BackdropSize> =
        \\        GotynoCoders.decodeOneOf Decode.string [|"w300", W300; "w1280", W1280; "original", Original|]
        \\
        \\    static member Encoder =
        \\        function
        \\        | W300 -> Encode.string "w300"
        \\        | W1280 -> Encode.string "w1280"
        \\        | Original -> Encode.string "original"
    ;

    var parsing_error: ParsingError = undefined;
    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        definition_buffer,
        &parsing_error,
    );

    const output = try outputEnumeration(
        &allocator.allocator,
        definitions.definitions[0].enumeration,
    );

    testing.expectEqualStrings(output, expected_output);

    definitions.deinit();
    allocator.allocator.free(output);
    testing_utilities.expectNoLeaks(&allocator);
}

test "Enumeration with integer values is output correctly" {
    var allocator = TestingAllocator{};

    const definition_buffer =
        \\enum Indices {
        \\    First = 0
        \\    Second = 1
        \\    Indeterminate = 999
        \\}
    ;

    const expected_output =
        \\type Indices =
        \\    | First
        \\    | Second
        \\    | Indeterminate
        \\
        \\    static member Decoder: Decoder<Indices> =
        \\        GotynoCoders.decodeOneOf Decode.uint32 [|0, First; 1, Second; 999, Indeterminate|]
        \\
        \\    static member Encoder =
        \\        function
        \\        | First -> Encode.uint32 0
        \\        | Second -> Encode.uint32 1
        \\        | Indeterminate -> Encode.uint32 999
    ;

    var parsing_error: ParsingError = undefined;
    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        definition_buffer,
        &parsing_error,
    );

    const output = try outputEnumeration(
        &allocator.allocator,
        definitions.definitions[0].enumeration,
    );

    testing.expectEqualStrings(output, expected_output);

    definitions.deinit();
    allocator.allocator.free(output);
    testing_utilities.expectNoLeaks(&allocator);
}

test "Basic untagged union is output correctly" {
    var allocator = TestingAllocator{};

    const definition_buffer =
        \\struct KnownForShow {
        \\    f: String
        \\}
        \\
        \\struct KnownForMovie {
        \\    f: U32
        \\}
        \\
        \\untagged union KnownFor {
        \\    KnownForMovie
        \\    KnownForShow
        \\    String
        \\    F32
        \\}
    ;

    const expected_output =
        \\type KnownFor =
        \\    | KnownForKnownForMovie of KnownForMovie
        \\    | KnownForKnownForShow of KnownForShow
        \\    | KnownForString of string
        \\    | KnownForF32 of float32
        \\
        \\    static member Decoder: Decoder<KnownFor> =
        \\        GotynoCoders.decodeIntoOneOf
        \\        [|
        \\            KnownForMovie.Decoder, KnownForKnownForMovie
        \\            KnownForShow.Decoder, KnownForKnownForShow
        \\            Decode.string, KnownForString
        \\            Decode.float32, KnownForF32
        \\        |]
        \\
        \\    static member Encoder =
        \\        function
        \\        | KnownForKnownForMovie payload ->
        \\            KnownForMovie.Encoder payload
        \\
        \\        | KnownForKnownForShow payload ->
        \\            KnownForShow.Encoder payload
        \\
        \\        | KnownForString payload ->
        \\            Encode.string payload
        \\
        \\        | KnownForF32 payload ->
        \\            Encode.float32 payload
    ;

    var parsing_error: ParsingError = undefined;
    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        definition_buffer,
        &parsing_error,
    );

    const output = try outputUntaggedUnion(
        &allocator.allocator,
        definitions.definitions[2].untagged_union,
    );

    testing.expectEqualStrings(output, expected_output);

    definitions.deinit();
    allocator.allocator.free(output);
    testing_utilities.expectNoLeaks(&allocator);
}
