const std = @import("std");
const debug = std.debug;
const mem = std.mem;
const heap = std.heap;
const testing = std.testing;
const fmt = std.fmt;
const meta = std.meta;

const tokenizer = @import("./tokenizer.zig");
const type_examples = @import("./type_examples.zig");
const testing_utilities = @import("./testing_utilities.zig");

const Token = tokenizer.Token;
const TokenIterator = tokenizer.TokenIterator;
const ArrayList = std.ArrayList;

pub const Definition = union(enum) {
    const Self = @This();

    structure: Structure,
    // @"union": Union,

    pub fn isEqual(self: Self, other: Self) bool {
        switch (self) {
            .structure => |structure| {
                return meta.activeTag(other) == .structure and
                    self.structure.isEqual(other.structure);
            },
        }

        return true;
    }
};

pub const Structure = struct {
    const Self = @This();

    name: []const u8,
    fields: []Field,

    pub fn isEqual(self: Self, other: Self) bool {
        if (mem.eql(u8, self.name, other.name)) {
            return true;
        } else {
            for (self.fields) |sf, i| {
                if (!sf.isEqual(other.fields[i])) return false;
            }

            return true;
        }
    }
};

pub const GenericStructure = struct {
    const Self = @This();

    name: []const u8,
    fields: []Field,
    open_names: []OpenName,
};

pub const Field = struct {
    const Self = @This();

    name: []const u8,
    @"type": Type,

    pub fn isEqual(self: Self, other: Self) bool {
        return self.@"type".isEqual(other.@"type") and mem.eql(u8, self.name, other.name);
    }
};

pub const Type = union(enum) {
    const Self = @This();

    string: []const u8,
    name: []const u8,
    array: Array,
    slice: Slice,

    pub fn isEqual(self: Self, other: Self) bool {
        return switch (self) {
            .string => meta.activeTag(other) == .string and mem.eql(u8, self.string, other.string),
            .name => meta.activeTag(other) == .name and mem.eql(u8, self.name, other.name),
            .array => |array| meta.activeTag(other) == .array and array.isEqual(other.array),
            .slice => |slice| meta.activeTag(other) == .slice and slice.isEqual(other.slice),
        };
    }
};

pub const Array = struct {
    const Self = @This();

    size: usize,
    @"type": *Type,

    pub fn isEqual(self: Self, other: Self) bool {
        return self.size == other.size and self.@"type".isEqual(other.@"type".*);
    }
};

pub const Slice = struct {
    const Self = @This();

    @"type": *Type,

    pub fn isEqual(self: Self, other: Self) bool {
        return self.@"type".isEqual(other.@"type".*);
    }
};

pub const Union = union(enum) {
    const Self = @This();

    plain_union: PlainUnion,
    generic_union: GenericUnion,
};

pub const ParseResult = union(enum) {
    success: ParseSuccess,
    // failure: ParseFailure,
};

pub const ParseSuccess = struct {
    definitions: []Definition,
    token_iterator: TokenIterator,
};

const TestingAllocator = heap.GeneralPurposeAllocator(.{});

pub fn parse(allocator: *mem.Allocator, buffer: []const u8) !ParseResult {
    var definitions = ArrayList(Definition).init(allocator);
    var definition_iterator = definitionIterator(allocator, buffer);
    while (try definition_iterator.next()) |definition| {
        try definitions.append(definition);
    }

    return ParseResult{
        .success = ParseSuccess{
            .definitions = definitions.items,
            .token_iterator = definition_iterator.token_iterator,
        },
    };
}

pub const DefinitionIterator = struct {
    const Self = @This();

    token_iterator: TokenIterator,
    allocator: *mem.Allocator,

    pub fn next(self: *Self) !?Definition {
        while (try self.token_iterator.next(.{})) |token| {
            switch (token) {
                .symbol => |s| {
                    if (mem.eql(u8, s, "struct")) {
                        _ = try self.token_iterator.expect(Token.space);

                        return Definition{ .structure = try self.parseStructureDefinition() };
                    }
                },
                else => {},
            }
        }

        return null;
    }

    pub fn parseStructureDefinition(self: *Self) !Structure {
        var tokens = &self.token_iterator;
        var fields = ArrayList(Field).init(self.allocator);
        const definition_name = (try tokens.expect(Token.name)).name;

        _ = try tokens.expect(Token.space);
        _ = try tokens.expect(Token.left_brace);
        _ = try tokens.expect(Token.newline);
        var done_parsing_fields = false;
        while (!done_parsing_fields) {
            if (try tokens.peek()) |t| {
                switch (t) {
                    .right_brace => done_parsing_fields = true,
                    else => {},
                }
            }
            if (!done_parsing_fields) {
                if (try self.parseStructureField()) |field| {
                    try fields.append(field);
                }
            }
        }
        _ = try tokens.expect(Token.right_brace);

        return Structure{
            .name = try self.allocator.dupe(u8, definition_name),
            .fields = fields.items,
        };
    }

    pub fn parseStructureField(self: *Self) !?Field {
        var tokens = &self.token_iterator;
        _ = try tokens.skipMany(Token.space, 4);
        const field_name = (try tokens.expect(Token.symbol)).symbol;
        _ = try tokens.expect(Token.colon);
        _ = try tokens.expect(Token.space);

        const maybe_field_value = try tokens.next(.{});
        if (maybe_field_value) |field_value| {
            const field = switch (field_value) {
                // valid as field values/types
                .string => |s| Field{ .@"type" = Type{ .string = s }, .name = field_name },
                .name => |n| Field{ .@"type" = Type{ .name = n }, .name = field_name },
                .left_bracket => field: {
                    const maybe_brackets_or_numbers = try tokens.next(.{});
                    if (maybe_brackets_or_numbers) |brackets_or_numbers| {
                        switch (brackets_or_numbers) {
                            .right_bracket => {
                                var slice_type = try self.allocator.create(Type);
                                slice_type.* = Type{ .name = (try tokens.expect(Token.name)).name };

                                break :field Field{
                                    .@"type" = Type{ .slice = Slice{ .@"type" = slice_type } },
                                    .name = field_name,
                                };
                            },
                            .unsigned_integer => |ui| {
                                _ = try tokens.expect(Token.right_bracket);
                                var array_type = try self.allocator.create(Type);
                                const array_type_name = (try tokens.expect(Token.name)).name;
                                array_type.* = Type{ .name = array_type_name };
                                break :field Field{
                                    .@"type" = Type{
                                        .array = Array{ .@"type" = array_type, .size = ui },
                                    },
                                    .name = field_name,
                                };
                            },
                            else => {
                                debug.panic(
                                    "Unknown slice/array component, expecting closing bracket or unsigned integer plus closing bracket. Got: {}\n",
                                    .{brackets_or_numbers},
                                );
                            },
                        }
                    } else {
                        debug.panic(
                            "Unexpected end of stream, expecting closing bracket or unsigned integer plus closing bracket.",
                            .{},
                        );
                    }
                },

                // invalid
                .symbol,
                .unsigned_integer,
                .left_brace,
                .right_brace,
                .right_bracket,
                .left_angle,
                .right_angle,
                .semicolon,
                .colon,
                .newline,
                .question_mark,
                .asterisk,
                .space,
                .comma,
                => {
                    debug.panic(
                        "Unexpected token in place of field value/type: {}",
                        .{field_value},
                    );
                },
            };
            _ = try tokens.expect(Token.semicolon);
            _ = try tokens.expect(Token.newline);

            return field;
        } else {
            debug.panic("Unexpected end of stream when expecting field value/type.", .{});
        }
    }
};

pub fn definitionIterator(allocator: *mem.Allocator, buffer: []const u8) DefinitionIterator {
    var token_iterator = tokenizer.tokenIterator(buffer);

    return DefinitionIterator{ .token_iterator = token_iterator, .allocator = allocator };
}

test "parsing `Person` struct" {
    var allocator = TestingAllocator{};
    var hobbies_slice_type = Type{ .name = "String" };
    var comments_array_type = Type{ .name = "String" };
    const expected_definitions = [_]Definition{.{
        .structure = Structure{
            .name = "Person",
            .fields = &[_]Field{
                .{ .name = "type", .@"type" = Type{ .string = "Person" } },
                .{ .name = "name", .@"type" = Type{ .name = "String" } },
                .{ .name = "age", .@"type" = Type{ .name = "U8" } },
                .{ .name = "efficiency", .@"type" = Type{ .name = "F32" } },
                .{ .name = "on_vacation", .@"type" = Type{ .name = "Boolean" } },
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
            },
        },
    }};
    const parsed_definition = try parse(&allocator.allocator, type_examples.person_structure);
    switch (parsed_definition) {
        .success => |parsed| expectEqualDefinitions(&expected_definitions, parsed.definitions),
    }
}

pub fn expectEqualDefinitions(as: []const Definition, bs: []const Definition) void {
    for (as) |a, i| {
        if (!a.isEqual(bs[i])) {
            const b = bs[i];
            debug.print("Definition at index {} different\n", .{i});
            debug.print("\tNames: {} & {}\n", .{ a.structure.name, b.structure.name });
            for (a.structure.fields) |f, fi| {
                if (!f.isEqual(b.structure.fields[fi])) {
                    testing_utilities.testPanic(
                        "Different field at index {}:\n\tExpected: {}\n\tGot: {}\n",
                        .{ fi, f, b.structure.fields[fi] },
                    );
                }
            }
        }
    }
}
