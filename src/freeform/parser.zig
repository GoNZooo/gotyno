const std = @import("std");
const debug = std.debug;
const mem = std.mem;
const heap = std.heap;
const testing = std.testing;
const fmt = std.fmt;
const meta = std.meta;

const tokenizer = @import("./tokenizer.zig");
const type_examples = @import("./type_examples.zig");

pub const Definition = union(enum) {
    structure: Structure,
    // @"union": Union,
};

pub const Structure = union(enum) {
    plain_structure: PlainStructure,
    // generic_structure: GenericStructure,
};

pub const PlainStructure = struct {
    name: []const u8,
    fields: []Field,
};

pub const GenericStructure = struct {
    name: []const u8,
    fields: []Field,
    open_names: []OpenName,
};

pub const Field = struct {
    name: []const u8,
    @"type": Type,
};

pub const Type = union(enum) {
    string: []const u8,
    name: []const u8,
    array: Array,
    slice: Slice,
};

pub const Array = struct {
    size: usize,
    @"type": *Type,
};

pub const Slice = struct {
    @"type": *Type,
};

pub const Union = union(enum) {
    plain_union: PlainUnion,
    generic_union: GenericUnion,
};

pub const ParseResult = union(enum) {
    success: ParseSuccess,
    // failure: ParseFailure,
};

pub const ParseSuccess = struct {
    definition: Definition,
    remaining_tokens: []tokenizer.Token,
};

const TestingAllocator = heap.GeneralPurposeAllocator(.{});

pub fn parseTokens(tokens: []tokenizer.Token) !ParseResult {
    const first_token = tokens[0];
    const is_definition_symbol = switch (first_token) {
        .symbol => |s| mem.eql(u8, s, "struct") or mem.eql(u8, s, "union"),
        else => false,
    };
    var i: usize = 1;
    var consumed_tokens: usize = 1;
    while (i < tokens.len) : (consumed_tokens = 1) {
        i += consumed_tokens;
    }

    return ParseResult{
        .success = ParseSuccess{
            .definition = Definition{
                .structure = Structure{
                    .plain_structure = PlainStructure{
                        .name = "Plain",
                        .fields = &[_]Field{},
                    },
                },
            },
            .remaining_tokens = tokens,
        },
    };
}

test "parsing `Person` struct" {
    var allocator = TestingAllocator{};
    const tokens = try tokenizer.tokenize(&allocator.allocator, type_examples.person_struct, .{});
    const parsed_person = try parseTokens(tokens.items);
}
