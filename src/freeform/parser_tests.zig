const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const debug = std.debug;

const parser = @import("./parser.zig");
const tokenizer = @import("./tokenizer.zig");
const utilities = @import("./utilities.zig");
const testing_utilities = @import("./testing_utilities.zig");
const parser_testing_utilities = @import("./parser_testing_utilities.zig");
const type_examples = @import("./type_examples.zig");

const Definition = parser.Definition;
const ImportedDefinition = parser.ImportedDefinition;
const AppliedName = parser.AppliedName;
const AppliedOpenName = parser.AppliedOpenName;
const ParsingError = parser.ParsingError;
const UnknownModule = parser.UnknownModule;
const TokenTag = tokenizer.TokenTag;
const Token = tokenizer.Token;
const EnumerationField = parser.EnumerationField;
const EnumerationValue = parser.EnumerationValue;
const DefinitionName = parser.DefinitionName;
const BufferData = parser.BufferData;
const Import = parser.Import;
const Location = utilities.Location;
const Slice = parser.Slice;
const Array = parser.Array;
const Pointer = parser.Pointer;
const Optional = parser.Optional;
const Union = parser.Union;
const PlainUnion = parser.PlainUnion;
const GenericUnion = parser.GenericUnion;
const Structure = parser.Structure;
const PlainStructure = parser.PlainStructure;
const GenericStructure = parser.GenericStructure;
const UntaggedUnion = parser.UntaggedUnion;
const UntaggedUnionValue = parser.UntaggedUnionValue;
const Enumeration = parser.Enumeration;
const Constructor = parser.Constructor;
const EmbeddedUnion = parser.EmbeddedUnion;
const ConstructorWithEmbeddedTypeTag = parser.ConstructorWithEmbeddedTypeTag;
const Field = parser.Field;
const Type = parser.Type;
const TypeReference = parser.TypeReference;
const LooseReference = parser.LooseReference;
const Builtin = parser.Builtin;
const TestingAllocator = testing_utilities.TestingAllocator;

test "Parsing `Person` structure" {
    var allocator = TestingAllocator{};
    var hobbies_slice_type = Type{ .reference = TypeReference{ .builtin = Builtin.String } };
    var comments_array_type = Type{ .reference = TypeReference{ .builtin = Builtin.String } };
    var recruiter_pointer_type = Type{
        .reference = TypeReference{
            .loose = LooseReference{
                .name = "Person",
                .open_names = &[_][]const u8{},
            },
        },
    };

    const expected_definitions = [_]Definition{.{
        .structure = Structure{
            .plain = PlainStructure{
                .name = DefinitionName{
                    .value = "Person",
                    .location = Location{ .filename = "test.gotyno", .line = 1, .column = 8 },
                },
                .fields = &[_]Field{
                    .{ .name = "type", .@"type" = Type{ .string = "Person" } },
                    .{
                        .name = "name",
                        .@"type" = Type{ .reference = TypeReference{ .builtin = Builtin.String } },
                    },
                    .{
                        .name = "age",
                        .@"type" = Type{ .reference = TypeReference{ .builtin = Builtin.U8 } },
                    },
                    .{
                        .name = "efficiency",
                        .@"type" = Type{ .reference = TypeReference{ .builtin = Builtin.F32 } },
                    },
                    .{
                        .name = "on_vacation",
                        .@"type" = Type{ .reference = TypeReference{ .builtin = Builtin.Boolean } },
                    },
                    .{
                        .name = "hobbies",
                        .@"type" = Type{ .slice = Slice{ .@"type" = &hobbies_slice_type } },
                    },
                    .{
                        .name = "last_fifteen_comments",
                        .@"type" = Type{
                            .array = Array{
                                .size = 15,
                                .@"type" = &comments_array_type,
                            },
                        },
                    },
                    .{
                        .name = "recruiter",
                        .@"type" = Type{
                            .optional = Optional{
                                .@"type" = &Type{
                                    .pointer = Pointer{ .@"type" = &recruiter_pointer_type },
                                },
                            },
                        },
                    },
                },
            },
        },
    }};

    var parsing_error: ParsingError = undefined;
    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        "test.gotyno",
        type_examples.person_structure,
        null,
        &parsing_error,
    );

    parser_testing_utilities.expectEqualDefinitions(&expected_definitions, definitions.definitions);

    definitions.deinit();
    testing_utilities.expectNoLeaks(&allocator);
}

test "Parsing basic generic structure" {
    var allocator = TestingAllocator{};

    var fields = [_]Field{
        .{
            .name = "data",
            .@"type" = Type{ .reference = TypeReference{ .open = "T" } },
        },
    };

    const expected_definitions = [_]Definition{.{
        .structure = Structure{
            .generic = GenericStructure{
                .name = DefinitionName{
                    .value = "Node",
                    .location = Location{ .filename = "test.gotyno", .line = 1, .column = 8 },
                },
                .fields = &fields,
                .open_names = &[_][]const u8{"T"},
            },
        },
    }};

    var parsing_error: ParsingError = undefined;
    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        "test.gotyno",
        type_examples.node_structure,
        null,
        &parsing_error,
    );

    parser_testing_utilities.expectEqualDefinitions(&expected_definitions, definitions.definitions);

    definitions.deinit();
    testing_utilities.expectNoLeaks(&allocator);
}

test "Parsing basic plain union" {
    var allocator = TestingAllocator{};

    var login_data_fields = [_]Field{
        .{
            .name = "username",
            .@"type" = Type{ .reference = TypeReference{ .builtin = Builtin.String } },
        },
        .{
            .name = "password",
            .@"type" = Type{ .reference = TypeReference{ .builtin = Builtin.String } },
        },
    };
    const login_data_structure = Definition{
        .structure = Structure{
            .plain = PlainStructure{
                .name = DefinitionName{
                    .value = "LogInData",
                    .location = Location{ .filename = "test.gotyno", .line = 1, .column = 8 },
                },
                .fields = &login_data_fields,
            },
        },
    };

    var userid_fields = [_]Field{
        .{
            .name = "value",
            .@"type" = Type{ .reference = TypeReference{ .builtin = Builtin.String } },
        },
    };
    const userid_structure = Definition{
        .structure = Structure{
            .plain = PlainStructure{
                .name = DefinitionName{
                    .value = "UserId",
                    .location = Location{ .filename = "test.gotyno", .line = 6, .column = 8 },
                },
                .fields = &userid_fields,
            },
        },
    };

    var channel_fields = [_]Field{
        .{
            .name = "name",
            .@"type" = Type{ .reference = TypeReference{ .builtin = Builtin.String } },
        },
        .{
            .name = "private",
            .@"type" = Type{ .reference = TypeReference{ .builtin = Builtin.Boolean } },
        },
    };
    const channel_structure = Definition{
        .structure = Structure{
            .plain = PlainStructure{
                .name = DefinitionName{
                    .value = "Channel",
                    .location = Location{ .filename = "test.gotyno", .line = 10, .column = 8 },
                },
                .fields = &channel_fields,
            },
        },
    };

    var email_fields = [_]Field{
        .{
            .name = "value",
            .@"type" = Type{ .reference = TypeReference{ .builtin = Builtin.String } },
        },
    };
    const email_structure = Definition{
        .structure = Structure{
            .plain = PlainStructure{
                .name = DefinitionName{
                    .value = "Email",
                    .location = Location{ .filename = "test.gotyno", .line = 15, .column = 8 },
                },
                .fields = &email_fields,
            },
        },
    };

    var channels_slice_type = Type{ .reference = TypeReference{ .definition = channel_structure } };
    var set_emails_array_type = Type{ .reference = TypeReference{ .definition = email_structure } };
    var expected_constructors = [_]Constructor{
        .{
            .tag = "LogIn",
            .parameter = Type{ .reference = TypeReference{ .definition = login_data_structure } },
        },
        .{
            .tag = "LogOut",
            .parameter = Type{ .reference = TypeReference{ .definition = userid_structure } },
        },
        .{
            .tag = "JoinChannels",
            .parameter = Type{ .slice = Slice{ .@"type" = &channels_slice_type } },
        },
        .{
            .tag = "SetEmails",
            .parameter = Type{ .array = Array{ .@"type" = &set_emails_array_type, .size = 5 } },
        },
    };

    const expected_definitions = [_]Definition{
        login_data_structure,
        userid_structure,
        channel_structure,
        email_structure,
        .{
            .@"union" = Union{
                .plain = PlainUnion{
                    .name = DefinitionName{
                        .value = "Event",
                        .location = Location{ .filename = "test.gotyno", .line = 19, .column = 7 },
                    },
                    .constructors = &expected_constructors,
                    .tag_field = "type",
                },
            },
        },
    };

    var parsing_error: ParsingError = undefined;
    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        "test.gotyno",
        type_examples.event_union,
        null,
        &parsing_error,
    );

    parser_testing_utilities.expectEqualDefinitions(&expected_definitions, definitions.definitions);

    definitions.deinit();
    testing_utilities.expectNoLeaks(&allocator);
}

test "Parsing `Maybe` union" {
    var allocator = TestingAllocator{};

    var expected_constructors = [_]Constructor{
        .{
            .tag = "just",
            .parameter = Type{ .reference = TypeReference{ .open = "T" } },
        },
        .{ .tag = "nothing", .parameter = Type.empty },
    };

    const expected_definitions = [_]Definition{.{
        .@"union" = Union{
            .generic = GenericUnion{
                .name = DefinitionName{
                    .value = "Maybe",
                    .location = Location{ .filename = "test.gotyno", .line = 1, .column = 7 },
                },
                .constructors = &expected_constructors,
                .open_names = &[_][]const u8{"T"},
                .tag_field = "type",
            },
        },
    }};

    var parsing_error: ParsingError = undefined;
    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        "test.gotyno",
        type_examples.maybe_union,
        null,
        &parsing_error,
    );

    parser_testing_utilities.expectEqualDefinitions(&expected_definitions, definitions.definitions);

    definitions.deinit();
    testing_utilities.expectNoLeaks(&allocator);
}

test "Parsing `Either` union" {
    var allocator = TestingAllocator{};

    var expected_constructors = [_]Constructor{
        .{
            .tag = "Left",
            .parameter = Type{ .reference = TypeReference{ .open = "E" } },
        },
        .{
            .tag = "Right",
            .parameter = Type{ .reference = TypeReference{ .open = "T" } },
        },
    };

    const expected_definitions = [_]Definition{.{
        .@"union" = Union{
            .generic = GenericUnion{
                .name = DefinitionName{
                    .value = "Either",
                    .location = Location{ .filename = "test.gotyno", .line = 1, .column = 7 },
                },
                .constructors = &expected_constructors,
                .open_names = &[_][]const u8{ "E", "T" },
                .tag_field = "type",
            },
        },
    }};

    var parsing_error: ParsingError = undefined;
    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        "test.gotyno",
        type_examples.either_union,
        null,
        &parsing_error,
    );

    parser_testing_utilities.expectEqualDefinitions(&expected_definitions, definitions.definitions);

    definitions.deinit();
    testing_utilities.expectNoLeaks(&allocator);
}

test "Parsing `List` union" {
    var allocator = TestingAllocator{};

    var applied_reference = TypeReference{
        .loose = LooseReference{ .name = "List", .open_names = &[_][]const u8{"T"} },
    };

    var applied_pointer_type = Type{
        .reference = TypeReference{
            .applied_name = AppliedName{
                .reference = &applied_reference,
                .open_names = &[_]AppliedOpenName{
                    .{
                        .reference = Type{ .reference = TypeReference{ .open = "T" } },
                    },
                },
            },
        },
    };
    var expected_constructors = [_]Constructor{
        .{ .tag = "Empty", .parameter = Type.empty },
        .{
            .tag = "Cons",
            .parameter = Type{ .pointer = Pointer{ .@"type" = &applied_pointer_type } },
        },
    };

    const expected_definitions = [_]Definition{.{
        .@"union" = Union{
            .generic = GenericUnion{
                .name = DefinitionName{
                    .value = "List",
                    .location = Location{ .filename = "test.gotyno", .line = 1, .column = 7 },
                },
                .constructors = &expected_constructors,
                .open_names = &[_][]const u8{"T"},
                .tag_field = "type",
            },
        },
    }};

    var parsing_error: ParsingError = undefined;
    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        "test.gotyno",
        type_examples.list_union,
        null,
        &parsing_error,
    );

    parser_testing_utilities.expectEqualDefinitions(&expected_definitions, definitions.definitions);

    definitions.deinit();
    testing_utilities.expectNoLeaks(&allocator);
}

test "Parsing basic string-based enumeration" {
    var allocator = TestingAllocator{};

    var expected_fields = [_]EnumerationField{
        .{ .tag = "w300", .value = EnumerationValue{ .string = "w300" } },
        .{ .tag = "original", .value = EnumerationValue{ .string = "original" } },
        .{ .tag = "number", .value = EnumerationValue{ .unsigned_integer = 42 } },
    };

    const expected_definitions = [_]Definition{.{
        .enumeration = Enumeration{
            .name = DefinitionName{
                .value = "BackdropSize",
                .location = Location{ .filename = "test.gotyno", .line = 1, .column = 6 },
            },
            .fields = &expected_fields,
        },
    }};

    const definition_buffer =
        \\enum BackdropSize {
        \\    w300 = "w300"
        \\    original = "original"
        \\    number = 42
        \\}
    ;

    var parsing_error: ParsingError = undefined;
    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        "test.gotyno",
        definition_buffer,
        null,
        &parsing_error,
    );

    parser_testing_utilities.expectEqualDefinitions(&expected_definitions, definitions.definitions);

    definitions.deinit();
    testing_utilities.expectNoLeaks(&allocator);
}

test "Parsing untagged union" {
    var allocator = TestingAllocator{};

    var known_for_show_fields = [_]Field{
        .{ .name = "f", .@"type" = Type{ .reference = TypeReference{ .builtin = Builtin.String } } },
    };

    const known_for_show = Definition{
        .structure = Structure{
            .plain = PlainStructure{
                .name = DefinitionName{
                    .value = "KnownForShow",
                    .location = Location{ .filename = "test.gotyno", .line = 1, .column = 8 },
                },
                .fields = &known_for_show_fields,
            },
        },
    };

    var known_for_movie_fields = [_]Field{
        .{ .name = "f", .@"type" = Type{ .reference = TypeReference{ .builtin = Builtin.U32 } } },
    };

    const known_for_movie = Definition{
        .structure = Structure{
            .plain = PlainStructure{
                .name = DefinitionName{
                    .value = "KnownForMovie",
                    .location = Location{ .filename = "test.gotyno", .line = 5, .column = 8 },
                },
                .fields = &known_for_movie_fields,
            },
        },
    };

    var expected_values = [_]UntaggedUnionValue{
        .{ .reference = TypeReference{ .definition = known_for_show } },
        .{ .reference = TypeReference{ .definition = known_for_movie } },
    };

    const expected_definitions = [_]Definition{
        known_for_show,
        known_for_movie,
        .{
            .untagged_union = UntaggedUnion{
                .name = DefinitionName{
                    .value = "KnownFor",
                    .location = Location{ .filename = "test.gotyno", .line = 9, .column = 16 },
                },
                .values = &expected_values,
            },
        },
    };

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
        \\    KnownForShow
        \\    KnownForMovie
        \\}
    ;

    var parsing_error: ParsingError = undefined;
    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        "test.gotyno",
        definition_buffer,
        null,
        &parsing_error,
    );

    parser_testing_utilities.expectEqualDefinitions(&expected_definitions, definitions.definitions);

    definitions.deinit();
    testing_utilities.expectNoLeaks(&allocator);
}

test "Parsing unions with options" {
    var allocator = TestingAllocator{};

    const definition_buffer =
        \\struct Value {
        \\    value: String
        \\}
        \\
        \\union(tag = kind) WithModifiedTag {
        \\    one: Value
        \\}
        \\
    ;

    var value_fields = [_]Field{
        .{
            .name = "value",
            .@"type" = Type{ .reference = TypeReference{ .builtin = Builtin.String } },
        },
    };

    const value_definition = Definition{
        .structure = Structure{
            .plain = PlainStructure{
                .name = DefinitionName{
                    .value = "Value",
                    .location = Location{ .filename = "test.gotyno", .line = 1, .column = 8 },
                },
                .fields = &value_fields,
            },
        },
    };

    var expected_constructors = [_]Constructor{
        .{
            .tag = "one",
            .parameter = Type{ .reference = TypeReference{ .definition = value_definition } },
        },
    };

    const expected_definitions = [_]Definition{
        value_definition,
        .{
            .@"union" = Union{
                .plain = PlainUnion{
                    .name = DefinitionName{
                        .value = "WithModifiedTag",
                        .location = Location{ .filename = "test.gotyno", .line = 5, .column = 19 },
                    },
                    .constructors = &expected_constructors,
                    .tag_field = "kind",
                },
            },
        },
    };

    var parsing_error: ParsingError = undefined;
    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        "test.gotyno",
        definition_buffer,
        null,
        &parsing_error,
    );

    parser_testing_utilities.expectEqualDefinitions(&expected_definitions, definitions.definitions);

    definitions.deinit();
    testing_utilities.expectNoLeaks(&allocator);
}

test "Defining a union with embedded type tags referencing unknown payloads returns error" {
    var allocator = TestingAllocator{};

    const definition_buffer =
        \\struct Two {
        \\    field2: F32
        \\    field3: Boolean
        \\}
        \\
        \\union(tag = media_type, embedded) Embedded {
        \\    movie: One
        \\    tv: Two
        \\    Empty
        \\}
    ;

    var parsing_error: ParsingError = undefined;
    var definitions = parser.parse(
        &allocator.allocator,
        &allocator.allocator,
        "test.gotyno",
        definition_buffer,
        null,
        &parsing_error,
    );

    testing.expectError(error.UnknownReference, definitions);
    switch (parsing_error) {
        .unknown_reference => |unknown_reference| {
            testing.expectEqual(unknown_reference.location.line, 7);
            testing.expectEqual(unknown_reference.location.column, 12);
            testing.expectEqualStrings(unknown_reference.location.filename, "test.gotyno");
            testing.expectEqualStrings(unknown_reference.name, "One");
        },

        .unknown_module,
        .invalid_payload,
        .expect,
        .duplicate_definition,
        .applied_name_count,
        => unreachable,
    }
}

test "Parsing invalid normal structure" {
    var allocator = TestingAllocator{};
    var parsing_error: ParsingError = undefined;
    const definitions = parser.parse(
        &allocator.allocator,
        &allocator.allocator,
        "test.gotyno",
        "struct Container T{",
        null,
        &parsing_error,
    );
    testing.expectError(error.UnexpectedToken, definitions);
    switch (parsing_error) {
        .expect => |expect| switch (expect) {
            .one_of => |one_of| {
                testing.expectEqualSlices(
                    TokenTag,
                    &[_]TokenTag{ .left_angle, .left_brace },
                    one_of.expectations,
                );
                testing.expect(one_of.got.isEqual(Token{ .name = "T" }));
            },
            .token => {
                testing_utilities.testPanic(
                    "Invalid error for expecting one of: {}",
                    .{parsing_error},
                );
            },
        },
        else => unreachable,
    }
}

test "Parsing same definition twice results in error" {
    var allocator = TestingAllocator{};
    var parsing_error: ParsingError = undefined;

    const definitions_buffer =
        \\struct Recruiter {
        \\    name: String
        \\}
        \\
        \\struct Recruiter {
        \\    n: String
        \\}
    ;

    var recruiter_fields = [_]Field{
        .{
            .name = "name",
            .@"type" = Type{
                .reference = TypeReference{ .builtin = Builtin.String },
            },
        },
    };

    const recruiter_definition = Definition{
        .structure = Structure{
            .plain = PlainStructure{
                .name = DefinitionName{
                    .value = "Recruiter",
                    .location = Location{ .filename = "test.gotyno", .line = 1, .column = 8 },
                },
                .fields = &recruiter_fields,
            },
        },
    };

    var new_recruiter_fields = [_]Field{
        .{
            .name = "n",
            .@"type" = Type{
                .reference = TypeReference{ .builtin = Builtin.String },
            },
        },
    };

    const new_recruiter_definition = Definition{
        .structure = Structure{
            .plain = PlainStructure{
                .name = DefinitionName{
                    .value = "Recruiter",
                    .location = Location{ .filename = "test.gotyno", .line = 5, .column = 8 },
                },
                .fields = &new_recruiter_fields,
            },
        },
    };

    const definitions = parser.parse(
        &allocator.allocator,
        &allocator.allocator,
        "test.gotyno",
        definitions_buffer,
        null,
        &parsing_error,
    );

    testing.expectError(error.DuplicateDefinition, definitions);
    switch (parsing_error) {
        .duplicate_definition => |d| {
            testing.expectEqual(d.location.line, 5);
            testing.expectEqual(d.location.column, 8);
            parser_testing_utilities.expectEqualDefinitions(
                &[_]Definition{recruiter_definition},
                &[_]Definition{d.existing_definition},
            );
            parser_testing_utilities.expectEqualDefinitions(
                &[_]Definition{new_recruiter_definition},
                &[_]Definition{d.definition},
            );
        },
        else => unreachable,
    }
}

test "Parsing union with embedded type tag" {
    var allocator = TestingAllocator{};
    var parsing_error: ParsingError = undefined;

    const definition_buffer =
        \\struct One {
        \\    field1: String
        \\}
        \\
        \\struct Two {
        \\    field2: F32
        \\}
        \\
        \\union(tag = media_type, embedded) Embedded {
        \\    WithOne: One
        \\    WithTwo: Two
        \\    Empty
        \\}
    ;

    var expected_struct_one_fields = [_]Field{
        .{
            .name = "field1",
            .@"type" = Type{ .reference = TypeReference{ .builtin = Builtin.String } },
        },
    };
    var expected_struct_two_fields = [_]Field{
        .{
            .name = "field2",
            .@"type" = Type{ .reference = TypeReference{ .builtin = Builtin.F32 } },
        },
    };

    const expected_struct_one = Structure{
        .plain = PlainStructure{
            .name = DefinitionName{
                .value = "One",
                .location = Location{ .filename = "test.gotyno", .line = 1, .column = 8 },
            },
            .fields = &expected_struct_one_fields,
        },
    };
    const expected_struct_two = Structure{
        .plain = PlainStructure{
            .name = DefinitionName{
                .value = "Two",
                .location = Location{ .filename = "test.gotyno", .line = 5, .column = 8 },
            },
            .fields = &expected_struct_two_fields,
        },
    };

    var expected_constructors = [_]ConstructorWithEmbeddedTypeTag{
        .{ .tag = "WithOne", .parameter = expected_struct_one },
        .{ .tag = "WithTwo", .parameter = expected_struct_two },
        .{ .tag = "Empty", .parameter = null },
    };

    const expected_definitions = [_]Definition{
        .{ .structure = expected_struct_one },
        .{ .structure = expected_struct_two },
        .{
            .@"union" = Union{
                .embedded = EmbeddedUnion{
                    .name = DefinitionName{
                        .value = "Embedded",
                        .location = Location{ .filename = "test.gotyno", .line = 9, .column = 34 },
                    },
                    .constructors = &expected_constructors,
                    .tag_field = "media_type",
                    .open_names = &[_][]u8{},
                },
            },
        },
    };

    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        "test.gotyno",
        definition_buffer,
        null,
        &parsing_error,
    );

    parser_testing_utilities.expectEqualDefinitions(&expected_definitions, definitions.definitions);

    definitions.deinit();
    testing_utilities.expectNoLeaks(&allocator);
}

test "Parsing union with embedded type tag and lowercase tags" {
    var allocator = TestingAllocator{};
    var parsing_error: ParsingError = undefined;

    const definition_buffer =
        \\struct One {
        \\    field1: String
        \\}
        \\
        \\struct Two {
        \\    field2: F32
        \\}
        \\
        \\union(tag = media_type, embedded) Embedded {
        \\    withOne: One
        \\    withTwo: Two
        \\    empty
        \\}
    ;

    var expected_struct_one_fields = [_]Field{
        .{
            .name = "field1",
            .@"type" = Type{ .reference = TypeReference{ .builtin = Builtin.String } },
        },
    };
    var expected_struct_two_fields = [_]Field{
        .{
            .name = "field2",
            .@"type" = Type{ .reference = TypeReference{ .builtin = Builtin.F32 } },
        },
    };

    const expected_struct_one = Structure{
        .plain = PlainStructure{
            .name = DefinitionName{
                .value = "One",
                .location = Location{
                    .filename = "test.gotyno",
                    .line = 1,
                    .column = 8,
                },
            },
            .fields = &expected_struct_one_fields,
        },
    };
    const expected_struct_two = Structure{
        .plain = PlainStructure{
            .name = DefinitionName{
                .value = "Two",
                .location = Location{
                    .filename = "test.gotyno",
                    .line = 5,
                    .column = 8,
                },
            },
            .fields = &expected_struct_two_fields,
        },
    };

    var expected_constructors = [_]ConstructorWithEmbeddedTypeTag{
        .{ .tag = "withOne", .parameter = expected_struct_one },
        .{ .tag = "withTwo", .parameter = expected_struct_two },
        .{ .tag = "empty", .parameter = null },
    };

    const expected_definitions = [_]Definition{
        .{ .structure = expected_struct_one },
        .{ .structure = expected_struct_two },
        .{
            .@"union" = Union{
                .embedded = EmbeddedUnion{
                    .name = DefinitionName{
                        .value = "Embedded",
                        .location = Location{ .filename = "test.gotyno", .line = 1, .column = 34 },
                    },
                    .constructors = &expected_constructors,
                    .tag_field = "media_type",
                    .open_names = &[_][]u8{},
                },
            },
        },
    };

    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        "test.gotyno",
        definition_buffer,
        null,
        &parsing_error,
    );

    parser_testing_utilities.expectEqualDefinitions(&expected_definitions, definitions.definitions);

    definitions.deinit();
    testing_utilities.expectNoLeaks(&allocator);
}

test "Parsing an import reference leads to two identical definitions in definition & reference" {
    var allocator = TestingAllocator{};
    var parsing_error: ParsingError = undefined;

    const module1_filename = "module1.gotyno";
    const module1_name = "module1";
    const module1_buffer =
        \\struct One {
        \\    field1: String
        \\}
    ;

    const module2_filename = "module2.gotyno";
    const module2_name = "module2";
    const module2_buffer =
        \\import module1
        \\
        \\struct Two {
        \\    field1: module1.One
        \\}
    ;

    var buffers = [_]BufferData{
        .{ .filename = module1_filename, .buffer = module1_buffer },
        .{ .filename = module2_filename, .buffer = module2_buffer },
    };

    const compiled_modules = try parser.parseModulesWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        &buffers,
        &parsing_error,
    );

    const maybe_module1 = compiled_modules.get(module1_name);
    testing.expect(maybe_module1 != null);
    const module1 = maybe_module1.?;

    const maybe_module2 = compiled_modules.get(module2_name);
    testing.expect(maybe_module2 != null);
    const module2 = maybe_module2.?;

    const module1_definition = module1.definitions[0];
    const module2_field_reference = module2.definitions[1].structure.plain.fields[0].@"type".reference.imported_definition.definition;

    parser_testing_utilities.expectEqualDefinitions(
        &[_]Definition{module1_definition},
        &[_]Definition{module2_field_reference},
    );
}

test "Parsing an imported reference works even with nested ones" {
    var allocator = TestingAllocator{};
    var parsing_error: ParsingError = undefined;

    const module1_filename = "module1.gotyno";
    const module1_name = "module1";
    const module1_buffer =
        \\union Maybe <T>{
        \\    Nothing
        \\    Just: T
        \\}
        \\
        \\union Either <L, R>{
        \\    Left: L
        \\    Right: R
        \\}
    ;

    const module2_filename = "module2.gotyno";
    const module2_name = "module2";
    const module2_buffer =
        \\import module1
        \\
        \\struct HoldsSomething <T>{
        \\    holdingField: T
        \\}
        \\
        \\struct PlainStruct {
        \\    normalField: String
        \\}
        \\
        \\struct Two {
        \\    fieldHolding: HoldsSomething<module1.Maybe<module1.Either<String, PlainStruct>>>
        \\}
    ;

    var plain_struct_applied_name = AppliedOpenName{
        .reference = Type{
            .reference = TypeReference{
                .definition = Definition{
                    .structure = Structure{
                        .plain = PlainStructure{
                            .name = DefinitionName{
                                .value = "PlainStruct",
                                .location = Location{
                                    .filename = "module2.gotyno",
                                    .line = 7,
                                    .column = 8,
                                },
                            },
                            .fields = &[_]Field{
                                .{
                                    .name = "normalField",
                                    .@"type" = Type{
                                        .reference = TypeReference{ .builtin = Builtin.String },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    };

    var string_applied_name = AppliedOpenName{
        .reference = Type{
            .reference = TypeReference{ .builtin = Builtin.String },
        },
    };

    var either_reference = TypeReference{
        .imported_definition = ImportedDefinition{
            .import_name = "module1",
            .definition = Definition{
                .@"union" = Union{
                    .generic = GenericUnion{
                        .tag_field = "type",
                        .open_names = &[_][]const u8{ "L", "R" },
                        .name = DefinitionName{
                            .value = "Either",
                            .location = Location{
                                .filename = "module1.gotyno",
                                .line = 6,
                                .column = 7,
                            },
                        },
                        .constructors = &[_]Constructor{
                            .{
                                .tag = "Left",
                                .parameter = Type{
                                    .reference = TypeReference{ .open = "L" },
                                },
                            },
                            .{
                                .tag = "Right",
                                .parameter = Type{
                                    .reference = TypeReference{ .open = "R" },
                                },
                            },
                        },
                    },
                },
            },
        },
    };

    var either_applied_name = AppliedOpenName{
        .reference = Type{
            .reference = TypeReference{
                .applied_name = AppliedName{
                    .reference = &either_reference,
                    .open_names = &[_]AppliedOpenName{ string_applied_name, plain_struct_applied_name },
                },
            },
        },
    };

    var maybe_reference = TypeReference{
        .imported_definition = ImportedDefinition{
            .import_name = "module1",
            .definition = Definition{
                .@"union" = Union{
                    .generic = GenericUnion{
                        .tag_field = "type",
                        .open_names = &[_][]const u8{"T"},
                        .name = DefinitionName{
                            .value = "Maybe",
                            .location = Location{
                                .filename = "module1.gotyno",
                                .line = 1,
                                .column = 7,
                            },
                        },
                        .constructors = &[_]Constructor{
                            .{
                                .tag = "Nothing",
                                .parameter = Type.empty,
                            },
                            .{
                                .tag = "Just",
                                .parameter = Type{
                                    .reference = TypeReference{ .open = "T" },
                                },
                            },
                        },
                    },
                },
            },
        },
    };

    var maybe_applied_name = AppliedOpenName{
        .reference = Type{
            .reference = TypeReference{
                .applied_name = AppliedName{
                    .reference = &maybe_reference,
                    .open_names = &[_]AppliedOpenName{either_applied_name},
                },
            },
        },
    };

    var holds_something_reference = TypeReference{
        .definition = Definition{
            .structure = Structure{
                .generic = GenericStructure{
                    .name = DefinitionName{
                        .value = "HoldsSomething",
                        .location = Location{
                            .filename = "module2.gotyno",
                            .line = 3,
                            .column = 8,
                        },
                    },
                    .open_names = &[_][]const u8{"T"},
                    .fields = &[_]Field{
                        .{
                            .name = "holdingField",
                            .@"type" = Type{
                                .reference = TypeReference{ .open = "T" },
                            },
                        },
                    },
                },
            },
        },
    };

    var holds_something_applied_name = AppliedName{
        .reference = &holds_something_reference,
        .open_names = &[_]AppliedOpenName{maybe_applied_name},
    };

    const expected_two_struct = Definition{
        .structure = Structure{
            .plain = PlainStructure{
                .name = DefinitionName{
                    .value = "Two",
                    .location = Location{
                        .filename = "module2.gotyno",
                        .line = 11,
                        .column = 8,
                    },
                },
                .fields = &[_]Field{
                    .{
                        .name = "fieldHolding",
                        .@"type" = Type{
                            .reference = TypeReference{
                                .applied_name = holds_something_applied_name,
                            },
                        },
                    },
                },
            },
        },
    };

    var buffers = [_]BufferData{
        .{ .filename = module1_filename, .buffer = module1_buffer },
        .{ .filename = module2_filename, .buffer = module2_buffer },
    };

    var compiled_modules = try parser.parseModulesWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        &buffers,
        &parsing_error,
    );

    const maybe_module1 = compiled_modules.get(module1_name);
    testing.expect(maybe_module1 != null);
    var module1 = maybe_module1.?;

    const maybe_module2 = compiled_modules.get(module2_name);
    testing.expect(maybe_module2 != null);
    var module2 = maybe_module2.?;

    const parsed_two_struct = module2.definitions[3];

    parser_testing_utilities.expectEqualDefinitions(&[_]Definition{parsed_two_struct}, &[_]Definition{expected_two_struct});

    compiled_modules.deinit();
    testing_utilities.expectNoLeaks(&allocator);
}

test "Parsing an imported definition without importing it errors out" {
    var allocator = TestingAllocator{};

    const module1_filename = "module1.gotyno";
    const module1_name = "module1";
    const module1_buffer =
        \\struct Plain {
        \\    name: String
        \\}
    ;

    const module2_filename = "module2.gotyno";
    const module2_name = "module2";
    const module2_buffer =
        \\struct HasMaybe {
        \\    field: module1.Plain
        \\}
    ;

    const buffers = [_]BufferData{
        .{ .filename = module1_filename, .buffer = module1_buffer },
        .{ .filename = module2_filename, .buffer = module2_buffer },
    };

    var parsing_error: ParsingError = undefined;

    var modules = parser.parseModules(
        &allocator.allocator,
        &allocator.allocator,
        &buffers,
        &parsing_error,
    );
    testing.expectError(error.UnknownModule, modules);

    switch (parsing_error) {
        .unknown_module => |d| {
            testing.expectEqualStrings("module1", d.name);
            testing.expectEqualStrings("module2.gotyno", d.location.filename);
            testing.expectEqual(d.location.line, 2);
            testing.expectEqual(d.location.column, 12);
        },
        else => unreachable,
    }
}

test "Parsing a slice type of an imported definition without importing it errors out" {
    var allocator = TestingAllocator{};

    const module1_filename = "module1.gotyno";
    const module1_name = "module1";
    const module1_buffer =
        \\struct Plain {
        \\    name: String
        \\}
    ;

    const module2_filename = "module2.gotyno";
    const module2_name = "module2";
    const module2_buffer =
        \\union Maybe <T>{
        \\    Nothing
        \\    Just: T
        \\}
        \\
        \\struct HasMaybe {
        \\    field: Maybe<[]module1.Plain>
        \\}
    ;

    const buffers = [_]BufferData{
        .{ .filename = module1_filename, .buffer = module1_buffer },
        .{ .filename = module2_filename, .buffer = module2_buffer },
    };

    var parsing_error: ParsingError = undefined;

    var modules = parser.parseModules(
        &allocator.allocator,
        &allocator.allocator,
        &buffers,
        &parsing_error,
    );
    testing.expectError(error.UnknownModule, modules);

    switch (parsing_error) {
        .unknown_module => |d| {
            testing.expectEqualStrings("module1", d.name);
            testing.expectEqualStrings("module2.gotyno", d.location.filename);
            testing.expectEqual(d.location.line, 7);
            testing.expectEqual(d.location.column, 20);
        },
        else => unreachable,
    }
}

test "Parsing a slice type of an imported definition in an already imported applied name without importing it errors out" {
    var allocator = TestingAllocator{};

    const module1_filename = "module1.gotyno";
    const module1_name = "module1";
    const module1_buffer =
        \\union Maybe <T>{
        \\    Nothing
        \\    Just: T
        \\}
        \\
        \\union Either <L, R>{
        \\    Left: L
        \\    Right: R
        \\}
    ;

    const module2_filename = "module2.gotyno";
    const module2_name = "module2";
    const module2_buffer =
        \\import module1
        \\
        \\struct HoldsSomething <T>{
        \\    holdingField: T
        \\}
        \\
        \\struct PlainStruct {
        \\    normalField: String
        \\}
        \\
        \\struct Two {
        \\    fieldHolding: HoldsSomething<module1.Maybe<module3.Either<String, PlainStruct>>>
        \\}
    ;

    const buffers = [_]BufferData{
        .{ .filename = module1_filename, .buffer = module1_buffer },
        .{ .filename = module2_filename, .buffer = module2_buffer },
    };

    var parsing_error: ParsingError = undefined;

    var modules = parser.parseModules(
        &allocator.allocator,
        &allocator.allocator,
        &buffers,
        &parsing_error,
    );
    testing.expectError(error.UnknownModule, modules);

    switch (parsing_error) {
        .unknown_module => |d| {
            testing.expectEqualStrings("module3", d.name);
            testing.expectEqualStrings("module2.gotyno", d.location.filename);
            testing.expectEqual(d.location.line, 12);
            testing.expectEqual(d.location.column, 48);
        },
        else => unreachable,
    }
}

test "Using an applied name with less open names than it requires errors out" {
    var allocator = TestingAllocator{};

    const module1_filename = "module1.gotyno";
    const module1_name = "module1";
    const module1_buffer =
        \\union Either <L, R>{
        \\    Left: L
        \\    Right: R
        \\}
        \\
        \\struct Plain {
        \\    either: Either<String>
        \\}
    ;

    const buffers = [_]BufferData{
        .{ .filename = module1_filename, .buffer = module1_buffer },
    };

    var parsing_error: ParsingError = undefined;

    var modules = parser.parseModules(
        &allocator.allocator,
        &allocator.allocator,
        &buffers,
        &parsing_error,
    );
    testing.expectError(error.AppliedNameCount, modules);

    switch (parsing_error) {
        .applied_name_count => |d| {
            testing.expectEqual(d.expected, 2);
            testing.expectEqual(d.actual, 1);
        },
        else => unreachable,
    }
}

test "Using an imported applied name with less open names than it requires errors out" {
    var allocator = TestingAllocator{};

    const module1_filename = "module1.gotyno";
    const module1_name = "module1";
    const module1_buffer =
        \\union Either <L, R>{
        \\    Left: L
        \\    Right: R
        \\}
    ;

    const module2_filename = "module2.gotyno";
    const module2_name = "module2";
    const module2_buffer =
        \\import module1
        \\
        \\struct Plain {
        \\    either: module1.Either<String>
        \\}
    ;

    const buffers = [_]BufferData{
        .{ .filename = module1_filename, .buffer = module1_buffer },
        .{ .filename = module2_filename, .buffer = module2_buffer },
    };

    var parsing_error: ParsingError = undefined;

    var modules = parser.parseModules(
        &allocator.allocator,
        &allocator.allocator,
        &buffers,
        &parsing_error,
    );
    testing.expectError(error.AppliedNameCount, modules);

    switch (parsing_error) {
        .applied_name_count => |d| {
            testing.expectEqualStrings("module2.gotyno", d.location.filename);
            testing.expectEqual(d.location.line, 4);
            testing.expectEqual(d.location.column, 21);
            testing.expectEqual(d.expected, 2);
            testing.expectEqual(d.actual, 1);
        },
        else => unreachable,
    }
}

test "Parsing an applied name that doesn't exist gives correct error" {
    var allocator = TestingAllocator{};
    var parsing_error: ParsingError = undefined;

    const module1_filename = "module1.gotyno";
    const module1_name = "module1";
    const module1_buffer =
        \\struct One {
        \\    field1: Either<String, F32>
        \\}
    ;

    var buffers = [_]BufferData{
        .{ .filename = module1_filename, .buffer = module1_buffer },
    };

    const compiled_modules = parser.parseModules(
        &allocator.allocator,
        &allocator.allocator,
        &buffers,
        &parsing_error,
    );
    testing.expectError(error.UnknownReference, compiled_modules);

    switch (parsing_error) {
        .unknown_reference => |d| {
            testing.expectEqualStrings("Either", d.name);
            testing.expectEqualStrings("module1.gotyno", d.location.filename);
            testing.expectEqual(d.location.line, 2);
            testing.expectEqual(d.location.column, 13);
        },
        else => unreachable,
    }
}

test "Parsing an imported applied name that doesn't exist gives correct error" {
    var allocator = TestingAllocator{};
    var parsing_error: ParsingError = undefined;

    const module1_filename = "module1.gotyno";
    const module1_name = "module1";
    const module1_buffer =
        \\union Either <L, R>{
        \\    Left: L
        \\    Right: R
        \\}
    ;

    const module2_filename = "module2.gotyno";
    const module2_name = "module2";
    const module2_buffer =
        \\import module1
        \\
        \\struct One {
        \\    field1: module1.Eithe<String, F32>
        \\}
    ;

    var buffers = [_]BufferData{
        .{ .filename = module1_filename, .buffer = module1_buffer },
        .{ .filename = module2_filename, .buffer = module2_buffer },
    };

    const compiled_modules = parser.parseModules(
        &allocator.allocator,
        &allocator.allocator,
        &buffers,
        &parsing_error,
    );
    testing.expectError(error.UnknownReference, compiled_modules);

    switch (parsing_error) {
        .unknown_reference => |d| {
            testing.expectEqualStrings("Eithe", d.name);
            testing.expectEqualStrings("module2.gotyno", d.location.filename);
            testing.expectEqual(d.location.line, 4);
            testing.expectEqual(d.location.column, 21);
        },
        else => unreachable,
    }
}
