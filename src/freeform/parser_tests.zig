const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const debug = std.debug;

const parser = @import("./parser.zig");
const tokenizer = @import("./tokenizer.zig");
const testing_utilities = @import("./testing_utilities.zig");
const type_examples = @import("./type_examples.zig");

const Definition = parser.Definition;
const AppliedName = parser.AppliedName;
const ParsingError = parser.ParsingError;
const TokenTag = tokenizer.TokenTag;
const Token = tokenizer.Token;
const EnumerationField = parser.EnumerationField;
const EnumerationValue = parser.EnumerationValue;
const DefinitionName = parser.DefinitionName;
const BufferData = parser.BufferData;
const Import = parser.Import;
const Location = parser.Location;
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
                    .location = Location{ .line = 1, .column = 8 },
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
                        .@"type" = Type{ .pointer = Pointer{ .@"type" = &recruiter_pointer_type } },
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

    expectEqualDefinitions(&expected_definitions, definitions.definitions);

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
                    .location = Location{ .line = 1, .column = 8 },
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

    expectEqualDefinitions(&expected_definitions, definitions.definitions);

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
                    .location = Location{ .line = 1, .column = 8 },
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
                    .location = Location{ .line = 6, .column = 8 },
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
                    .location = Location{ .line = 10, .column = 8 },
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
                    .location = Location{ .line = 15, .column = 8 },
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
                        .location = Location{ .line = 19, .column = 7 },
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

    expectEqualDefinitions(&expected_definitions, definitions.definitions);

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
                    .location = Location{ .line = 1, .column = 7 },
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

    expectEqualDefinitions(&expected_definitions, definitions.definitions);

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
                    .location = Location{ .line = 1, .column = 7 },
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

    expectEqualDefinitions(&expected_definitions, definitions.definitions);

    definitions.deinit();
    testing_utilities.expectNoLeaks(&allocator);
}

test "Parsing `List` union" {
    var allocator = TestingAllocator{};

    var applied_reference = TypeReference{
        .loose = LooseReference{ .name = "List", .open_names = &[_][]const u8{} },
    };

    var applied_pointer_type = Type{
        .reference = TypeReference{
            .applied_name = AppliedName{
                .reference = &applied_reference,
                .open_names = &[_][]const u8{"T"},
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
                    .location = Location{ .line = 1, .column = 7 },
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

    expectEqualDefinitions(&expected_definitions, definitions.definitions);

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
                .location = Location{ .line = 1, .column = 6 },
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

    expectEqualDefinitions(&expected_definitions, definitions.definitions);

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
                    .location = Location{ .line = 1, .column = 8 },
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
                    .location = Location{ .line = 5, .column = 8 },
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
                    .location = Location{ .line = 9, .column = 16 },
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

    expectEqualDefinitions(&expected_definitions, definitions.definitions);

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
                    .location = Location{ .line = 1, .column = 8 },
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
                        .location = Location{ .line = 5, .column = 19 },
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

    expectEqualDefinitions(&expected_definitions, definitions.definitions);

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
            testing.expectEqual(unknown_reference.line, 7);
            testing.expectEqual(unknown_reference.column, 12);
            testing.expectEqualStrings(unknown_reference.name, "One");
        },

        .unknown_module, .invalid_payload, .expect, .duplicate_definition => unreachable,
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
                    .location = Location{ .line = 1, .column = 8 },
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
                    .location = Location{ .line = 5, .column = 8 },
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
            expectEqualDefinitions(
                &[_]Definition{recruiter_definition},
                &[_]Definition{d.existing_definition},
            );
            expectEqualDefinitions(
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
                .location = Location{ .line = 1, .column = 8 },
            },
            .fields = &expected_struct_one_fields,
        },
    };
    const expected_struct_two = Structure{
        .plain = PlainStructure{
            .name = DefinitionName{
                .value = "Two",
                .location = Location{ .line = 5, .column = 8 },
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
                        .location = Location{ .line = 9, .column = 34 },
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

    expectEqualDefinitions(&expected_definitions, definitions.definitions);

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
            .name = DefinitionName{ .value = "One", .location = Location{ .line = 1, .column = 8 } },
            .fields = &expected_struct_one_fields,
        },
    };
    const expected_struct_two = Structure{
        .plain = PlainStructure{
            .name = DefinitionName{ .value = "Two", .location = Location{ .line = 5, .column = 8 } },
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
                        .location = Location{ .line = 1, .column = 34 },
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

    expectEqualDefinitions(&expected_definitions, definitions.definitions);

    definitions.deinit();
    testing_utilities.expectNoLeaks(&allocator);
}

test "Parsing an import reference leads to two identical definitions in definition & reference" {
    var allocator = TestingAllocator{};
    var parsing_error: ParsingError = undefined;

    // @TODO: add testing for parsing applied names with imported references in them with nested
    // references: `fieldHolding: HoldsSomething<basic.Maybe<basic.Either<String, Plainstruct>>`

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
    const module2_field_reference = module2.definitions[0].structure.plain.fields[0].@"type".reference.imported_definition.definition;

    expectEqualDefinitions(&[_]Definition{module1_definition}, &[_]Definition{module2_field_reference});
}

pub fn expectEqualDefinitions(as: []const Definition, bs: []const Definition) void {
    const Names = struct {
        a: DefinitionName,
        b: DefinitionName,
    };

    const Fields = struct {
        a: []const Field,
        b: []const Field,
    };

    const FieldsAndNames = struct {
        names: Names,
        fields: Fields,
    };

    if (as.len == 0) {
        testing_utilities.testPanic("Definition slice `as` is zero length; invalid test\n", .{});
    }

    if (bs.len == 0) {
        testing_utilities.testPanic("Definition slice `bs` is zero length; invalid test\n", .{});
    }

    if (as.len != bs.len) {
        testing_utilities.testPanic(
            "Definition slices are different length: {} != {}\n",
            .{ as.len, bs.len },
        );
    }

    for (as) |a, i| {
        const b = bs[i];

        if (!a.isEqual(b)) {
            switch (a) {
                .structure => |structure| {
                    const fields_and_names = switch (structure) {
                        .plain => |plain| FieldsAndNames{
                            .names = Names{ .a = plain.name, .b = b.structure.plain.name },
                            .fields = Fields{ .a = plain.fields, .b = b.structure.plain.fields },
                        },
                        .generic => |generic| FieldsAndNames{
                            .names = Names{ .a = generic.name, .b = b.structure.generic.name },
                            .fields = Fields{ .a = generic.fields, .b = b.structure.generic.fields },
                        },
                    };

                    debug.print("Definition at index {} different\n", .{i});
                    if (!fields_and_names.names.a.isEqual(fields_and_names.names.b)) {
                        debug.panic(
                            "\tNames: {} != {}\n",
                            .{ fields_and_names.names.a, fields_and_names.names.b },
                        );
                    }

                    expectEqualFields(fields_and_names.fields.a, fields_and_names.fields.b);

                    switch (structure) {
                        .generic => |generic| {
                            expectEqualOpenNames(
                                generic.open_names,
                                b.structure.generic.open_names,
                            );
                        },
                        .plain => {},
                    }
                },

                .@"union" => |u| {
                    switch (u) {
                        .plain => |plain| {
                            if (!plain.name.isEqual(b.@"union".plain.name)) {
                                debug.panic(
                                    "\tNames: {} != {}\n",
                                    .{ plain.name, b.@"union".plain.name },
                                );
                            }

                            expectEqualConstructors(
                                plain.constructors,
                                b.@"union".plain.constructors,
                            );
                        },
                        .generic => |generic| {
                            if (!generic.name.isEqual(b.@"union".generic.name)) {
                                debug.print(
                                    "\tNames: {} != {}\n",
                                    .{ generic.name, b.@"union".generic.name },
                                );
                            }

                            expectEqualConstructors(
                                generic.constructors,
                                b.@"union".generic.constructors,
                            );

                            expectEqualOpenNames(generic.open_names, b.@"union".generic.open_names);
                        },
                        .embedded => |embedded| {
                            if (!embedded.name.isEqual(b.@"union".embedded.name)) {
                                debug.panic(
                                    "\tNames: {} != {}\n",
                                    .{ embedded.name, b.@"union".embedded.name },
                                );
                            }

                            expectEqualEmbeddedConstructors(
                                embedded.constructors,
                                b.@"union".embedded.constructors,
                            );

                            expectEqualOpenNames(
                                embedded.open_names,
                                b.@"union".embedded.open_names,
                            );
                        },
                    }
                },

                .enumeration => |e| {
                    expectEqualEnumerations(e, b.enumeration);
                },

                .untagged_union => |u| {
                    expectEqualUntaggedUnions(u, b.untagged_union);
                },

                .import => |import| {
                    expectEqualImports(import, b.import);
                },
            }
        }
    }
}

fn expectEqualFields(as: []const Field, bs: []const Field) void {
    if (as.len != bs.len) {
        testing_utilities.testPanic(
            "Different number of fields found: {} != {}\n",
            .{ as.len, bs.len },
        );
    }

    for (as) |a, i| {
        if (!a.isEqual(bs[i])) {
            testing_utilities.testPanic(
                "Different field at index {}:\n\tExpected: {}\n\tGot: {}\n",
                .{ i, a, bs[i] },
            );
        }
    }
}

fn expectEqualOpenNames(as: []const []const u8, bs: []const []const u8) void {
    if (as.len != bs.len) {
        testing_utilities.testPanic(
            "Different number of open names found: {} != {}\n",
            .{ as.len, bs.len },
        );
    }

    for (as) |a, i| {
        if (!mem.eql(u8, a, bs[i])) {
            testing_utilities.testPanic(
                "Different open name at index {}:\n\tExpected: {}\n\tGot: {}\n",
                .{ i, a, bs[i] },
            );
        }
    }
}

fn expectEqualConstructors(as: []const Constructor, bs: []const Constructor) void {
    if (as.len != bs.len) {
        testing_utilities.testPanic(
            "Different number of constructors found: {} != {}\n",
            .{ as.len, bs.len },
        );
    }

    for (as) |a, i| {
        const b = bs[i];
        if (!a.isEqual(b)) {
            testing_utilities.testPanic(
                "Different constructor at index {}:\n\tExpected: {}\n\tGot: {}\n",
                .{ i, a, b },
            );
        }
    }
}

fn expectEqualEmbeddedConstructors(
    as: []const ConstructorWithEmbeddedTypeTag,
    bs: []const ConstructorWithEmbeddedTypeTag,
) void {
    for (as) |a, i| {
        const b = bs[i];
        if (!a.isEqual(b)) {
            if (!mem.eql(u8, a.tag, b.tag)) {
                testing_utilities.testPanic(
                    "Embedded constructor tags do not match: {} != {}\n",
                    .{ a.tag, b.tag },
                );
            }

            if (a.parameter) |a_parameter| {
                if (b.parameter) |b_parameter| {
                    expectEqualFields(a_parameter.plain.fields, b_parameter.plain.fields);
                } else {
                    testing_utilities.testPanic(
                        "Embedded constructor {} ({}) has parameter whereas {} does not\n",
                        .{ i, a.tag, b.tag },
                    );
                }
            } else {
                if (b.parameter) |b_parameter| {
                    testing_utilities.testPanic(
                        "Embedded constructor {} ({}) has parameter whereas {} does not\n",
                        .{ i, b.tag, a.tag },
                    );
                }
            }

            testing_utilities.testPanic(
                "Different constructor at index {}:\n\tExpected: {}\n\tGot: {}\n",
                .{ i, a, b },
            );
        }
    }
}

fn expectEqualEnumerations(a: Enumeration, b: Enumeration) void {
    if (!a.name.isEqual(b.name)) {
        testing_utilities.testPanic(
            "Enumeration names do not match: {} != {}\n",
            .{ a.name, b.name },
        );
    }

    if (a.fields.len != b.fields.len) {
        testing_utilities.testPanic(
            "Different amount of fields for enumerations: {} != {}\n",
            .{ a.fields.len, b.fields.len },
        );
    }

    for (a.fields) |field, i| {
        if (!field.isEqual(b.fields[i])) {
            debug.print("Field at index {} is different:\n", .{i});
            debug.print("\tExpected: {}\n", .{field});
            testing_utilities.testPanic("\tGot: {}\n", .{b.fields[i]});
        }
    }
}

fn expectEqualUntaggedUnions(a: UntaggedUnion, b: UntaggedUnion) void {
    if (!a.name.isEqual(b.name)) {
        testing_utilities.testPanic(
            "Untagged union names do not match: {} != {}\n",
            .{ a.name, b.name },
        );
    }

    if (a.values.len != b.values.len) {
        testing_utilities.testPanic(
            "Different amount of values for untagged unions: {} != {}\n",
            .{ a.values.len, b.values.len },
        );
    }

    for (a.values) |field, i| {
        if (!field.isEqual(b.values[i])) {
            debug.print("Value at index {} is different:\n", .{i});
            debug.print("\tExpected: {}\n", .{field});
            testing_utilities.testPanic("\tGot: {}\n", .{b.values[i]});
        }
    }
}

fn expectEqualImports(a: Import, b: Import) void {
    if (!a.name.isEqual(b.name)) {
        testing_utilities.testPanic(
            "Import names do not match: {} != {}\n",
            .{ a.name, b.name },
        );
    }

    if (!mem.eql(u8, a.alias, b.alias)) {
        testing_utilities.testPanic(
            "Import aliases do not match: {} != {}\n",
            .{ a.alias, b.alias },
        );
    }
}
