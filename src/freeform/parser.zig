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
const TokenTag = tokenizer.TokenTag;
const ExpectError = tokenizer.ExpectError;
const TokenIterator = tokenizer.TokenIterator;
const ArrayList = std.ArrayList;

pub const Definition = union(enum) {
    const Self = @This();

    structure: Structure,
    @"union": Union,
    enumeration: Enumeration,
    untagged_union: UntaggedUnion,
    import: Import,

    pub fn isEqual(self: Self, other: Self) bool {
        return switch (self) {
            .structure => |s| meta.activeTag(other) == .structure and s.isEqual(other.structure),
            .@"union" => |u| meta.activeTag(other) == .@"union" and u.isEqual(other.@"union"),
            .enumeration => |e| meta.activeTag(other) == .enumeration and
                e.isEqual(other.enumeration),
            .untagged_union => |u| meta.activeTag(other) == .untagged_union and
                u.isEqual(other.untagged_union),
            .import => |i| meta.activeTag(other) == .import and i.isEqual(other.import),
        };
    }
};

pub const Import = struct {
    const Self = @This();

    name: []const u8,
    alias: []const u8,

    pub fn isEqual(self: Self, other: Self) bool {
        return mem.eql(u8, self.name, other.name) and mem.eql(u8, self.alias, other.alias);
    }
};

pub const UntaggedUnion = struct {
    const Self = @This();

    name: []const u8,
    values: []UntaggedUnionValue,

    pub fn isEqual(self: Self, other: Self) bool {
        if (!mem.eql(u8, self.name, other.name)) return false;

        if (self.values.len != other.values.len) return false;

        for (self.values) |value, i| {
            if (!value.isEqual(other.values[i])) return false;
        }

        return true;
    }
};

pub const UntaggedUnionValue = union(enum) {
    const Self = @This();

    name: []const u8,

    pub fn isEqual(self: Self, other: Self) bool {
        return switch (self) {
            .name => |n| meta.activeTag(other) == .name and mem.eql(u8, n, other.name),
        };
    }
};

pub const Enumeration = struct {
    const Self = @This();

    name: []const u8,
    fields: []EnumerationField,

    pub fn isEqual(self: Self, other: Self) bool {
        if (!mem.eql(u8, self.name, other.name)) return false;

        if (self.fields.len != other.fields.len) return false;

        for (self.fields) |field, i| {
            if (!field.isEqual(other.fields[i])) return false;
        }

        return true;
    }
};

pub const EnumerationField = struct {
    const Self = @This();

    tag: []const u8,
    value: EnumerationValue,

    pub fn isEqual(self: Self, other: Self) bool {
        return mem.eql(u8, self.tag, other.tag) and self.value.isEqual(other.value);
    }
};

pub const EnumerationValue = union(enum) {
    const Self = @This();

    string: []const u8,
    unsigned_integer: u64,

    pub fn isEqual(self: Self, other: Self) bool {
        return switch (self) {
            .string => |s| meta.activeTag(other) == .string and mem.eql(u8, s, other.string),
            .unsigned_integer => |ui| meta.activeTag(other) == .unsigned_integer and
                ui == other.unsigned_integer,
        };
    }
};

pub const Structure = union(enum) {
    const Self = @This();

    plain: PlainStructure,
    generic: GenericStructure,

    pub fn isEqual(self: Self, other: Self) bool {
        switch (self) {
            .plain => |plain| {
                return meta.activeTag(other) == .plain and plain.isEqual(other.plain);
            },
            .generic => |generic| {
                return meta.activeTag(other) == .generic and generic.isEqual(other.generic);
            },
        }
    }

    pub fn name(self: Self) []const u8 {
        return switch (self) {
            .plain => |plain| plain.name,
            .generic => |generic| generic.name,
        };
    }
};

pub const PlainStructure = struct {
    const Self = @This();

    name: []const u8,
    fields: []Field,

    pub fn isEqual(self: Self, other: Self) bool {
        if (!mem.eql(u8, self.name, other.name)) {
            return false;
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
    open_names: []const []const u8,

    pub fn isEqual(self: Self, other: Self) bool {
        if (!mem.eql(u8, self.name, other.name)) {
            return false;
        } else {
            for (self.open_names) |name, i| {
                if (!mem.eql(u8, name, other.open_names[i])) return false;
            }

            for (self.fields) |field, i| {
                if (!field.isEqual(other.fields[i])) return false;
            }

            return true;
        }
    }
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

    empty,
    string: []const u8,
    name: []const u8,
    array: Array,
    slice: Slice,
    pointer: Pointer,
    optional: Optional,
    applied_name: AppliedName,

    pub fn isEqual(self: Self, other: Self) bool {
        return switch (self) {
            .empty => meta.activeTag(other) == .empty,
            .string => meta.activeTag(other) == .string and mem.eql(u8, self.string, other.string),
            .name => meta.activeTag(other) == .name and mem.eql(u8, self.name, other.name),
            .array => |array| meta.activeTag(other) == .array and array.isEqual(other.array),
            .slice => |slice| meta.activeTag(other) == .slice and slice.isEqual(other.slice),
            .pointer => |pointer| meta.activeTag(other) == .pointer and pointer.isEqual(other.pointer),
            .optional => |optional| meta.activeTag(other) == .optional and
                optional.isEqual(other.optional),
            .applied_name => |applied_name| meta.activeTag(other) == .applied_name and
                applied_name.isEqual(other.applied_name),
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

pub const Pointer = struct {
    const Self = @This();

    @"type": *Type,

    pub fn isEqual(self: Self, other: Self) bool {
        return self.@"type".isEqual(other.@"type".*);
    }
};

pub const Optional = struct {
    const Self = @This();

    @"type": *Type,

    pub fn isEqual(self: Self, other: Self) bool {
        return self.@"type".isEqual(other.@"type".*);
    }
};

pub const AppliedName = struct {
    const Self = @This();

    name: []const u8,
    open_names: []const []const u8,

    pub fn isEqual(self: Self, other: Self) bool {
        if (!mem.eql(u8, self.name, other.name)) return false;

        for (self.open_names) |open_name, i| {
            if (!mem.eql(u8, open_name, other.open_names[i])) return false;
        }

        return true;
    }
};

pub const Union = union(enum) {
    const Self = @This();

    plain: PlainUnion,
    generic: GenericUnion,
    // @TODO: add `UnionWithEmbeddedTag` or the like here, make it so it cannot be constructed
    // without also passing a structure to it, meaning we'll have to actually have a struct we can
    // refer to when we create the definition itself. That way we'll guarantee that we have
    // something we can output.
    // @NOTE: This will likely mean we have to keep a "so far" array of definitions that can be
    // referenced when definitions are created, which will mean we can then reach into it to pull
    // out an *already parsed* definition for a struct that will have the tag embedded in it.

    pub fn isEqual(self: Self, other: Self) bool {
        return switch (self) {
            .plain => |plain| meta.activeTag(other) == .plain and plain.isEqual(other.plain),
            .generic => |generic| meta.activeTag(other) == .generic and
                generic.isEqual(other.generic),
        };
    }

    pub fn name(self: Self) []const u8 {
        return switch (self) {
            .plain => |plain| plain.name,
            .generic => |generic| generic.name,
        };
    }
};

pub const UnionOptions = struct {
    tag_field: []const u8,
    embedded: bool,
};

pub const PlainUnion = struct {
    const Self = @This();

    name: []const u8,
    constructors: []Constructor,
    tag_field: []const u8,

    pub fn isEqual(self: Self, other: Self) bool {
        if (!mem.eql(u8, self.name, other.name)) return false;
        if (!mem.eql(u8, self.tag_field, other.tag_field)) return false;

        for (self.constructors) |constructor, i| {
            if (!constructor.isEqual(other.constructors[i])) return false;
        }

        return true;
    }
};

pub const GenericUnion = struct {
    const Self = @This();

    name: []const u8,
    constructors: []Constructor,
    open_names: []const []const u8,
    tag_field: []const u8,

    pub fn isEqual(self: Self, other: Self) bool {
        if (!mem.eql(u8, self.name, other.name)) return false;
        if (!mem.eql(u8, self.tag_field, other.tag_field)) return false;

        for (self.constructors) |constructor, i| {
            if (!constructor.isEqual(other.constructors[i])) return false;
        }

        for (self.open_names) |open_name, i| {
            if (!mem.eql(u8, open_name, other.open_names[i])) return false;
        }

        return true;
    }
};

pub const Constructor = struct {
    const Self = @This();

    tag: []const u8,
    parameter: Type,

    pub fn isEqual(self: Self, other: Self) bool {
        return mem.eql(u8, self.tag, other.tag) and self.parameter.isEqual(other.parameter);
    }
};

const TestingAllocator = heap.GeneralPurposeAllocator(.{});

pub fn parse(
    allocator: *mem.Allocator,
    error_allocator: *mem.Allocator,
    buffer: []const u8,
    expect_error: *ExpectError,
) ![]Definition {
    var definitions = ArrayList(Definition).init(allocator);
    var definition_iterator = DefinitionIterator.init(allocator, buffer, expect_error);
    while (try definition_iterator.next()) |definition| {
        try definitions.append(definition);
    }

    return definitions.items;
}

pub fn parseWithDescribedError(
    allocator: *mem.Allocator,
    error_allocator: *mem.Allocator,
    buffer: []const u8,
    expect_error: *ExpectError,
) ![]Definition {
    return parse(allocator, error_allocator, buffer, expect_error) catch |e| {
        switch (e) {
            error.UnexpectedToken => {
                switch (expect_error.*) {
                    .token => |token| {
                        debug.panic(
                            "Unexpected token at {}:{}:\n\tExpected: {}\n\tGot: {}",
                            .{ token.line, token.column, token.expectation, token.got },
                        );
                    },
                    .one_of => |one_of| {
                        debug.print(
                            "Unexpected token at {}:{}:\n\tExpected one of: {}",
                            .{ one_of.line, one_of.column, one_of.expectations[0] },
                        );
                        for (one_of.expectations[1..]) |expectation| {
                            debug.print(", {}", .{expectation});
                        }
                        debug.panic("\n\tGot: {}\n", .{one_of.got});
                    },
                }
            },
            else => return e,
        }
    };
}

/// `DefinitionIterator` is iterator that attempts to return the next definition in a source, based
/// on a `TokenIterator` that it holds inside of its instance. It's an unapologetically stateful
/// thing; most of what is going on in here depends entirely on the order methods are called and it
/// keeps whatever state it needs in the object itself.
pub const DefinitionIterator = struct {
    const Self = @This();

    token_iterator: TokenIterator,
    allocator: *mem.Allocator,
    expect_error: *ExpectError,

    pub fn init(
        allocator: *mem.Allocator,
        buffer: []const u8,
        expect_error: *ExpectError,
    ) Self {
        var token_iterator = tokenizer.TokenIterator.init(buffer);

        return DefinitionIterator{
            .token_iterator = token_iterator,
            .allocator = allocator,
            .expect_error = expect_error,
        };
    }

    pub fn next(self: *Self) !?Definition {
        const tokens = &self.token_iterator;

        while (try tokens.next(.{})) |token| {
            switch (token) {
                .symbol => |s| {
                    if (mem.eql(u8, s, "struct")) {
                        _ = try tokens.expect(Token.space, self.expect_error);

                        return Definition{ .structure = try self.parseStructureDefinition() };
                    } else if (mem.eql(u8, s, "union")) {
                        const space_or_left_parenthesis = try tokens.expectOneOf(
                            &[_]TokenTag{ .space, .left_parenthesis },
                            self.expect_error,
                        );

                        switch (space_or_left_parenthesis) {
                            .space => return Definition{
                                .@"union" = try self.parseUnionDefinition(
                                    UnionOptions{ .tag_field = "type", .embedded = false },
                                ),
                            },
                            .left_parenthesis => return Definition{
                                .@"union" = try self.parseUnionDefinition(
                                    try self.parseUnionOptions(),
                                ),
                            },
                            else => unreachable,
                        }
                    } else if (mem.eql(u8, s, "enum")) {
                        _ = try tokens.expect(Token.space, self.expect_error);

                        return Definition{ .enumeration = try self.parseEnumerationDefinition() };
                    } else if (mem.eql(u8, s, "untagged")) {
                        _ = try tokens.expect(Token.space, self.expect_error);
                        const union_keyword = (try tokens.expect(
                            Token.symbol,
                            self.expect_error,
                        )).symbol;
                        debug.assert(mem.eql(u8, union_keyword, "union"));
                        _ = try tokens.expect(Token.space, self.expect_error);

                        return Definition{
                            .untagged_union = try self.parseUntaggedUnionDefinition(),
                        };
                    } else if (mem.eql(u8, s, "import")) {
                        _ = try tokens.expect(Token.space, self.expect_error);

                        const import_name = switch (try tokens.expectOneOf(
                            &[_]TokenTag{ .symbol, .name },
                            self.expect_error,
                        )) {
                            .symbol => |symbol| symbol,
                            .name => |name| name,
                            else => unreachable,
                        };

                        switch (try tokens.expectOneOf(
                            &[_]TokenTag{ .newline, .space },
                            self.expect_error,
                        )) {
                            .newline => return Definition{
                                .import = Import{ .name = import_name, .alias = import_name },
                            },
                            .space => {
                                _ = try tokens.expect(Token.equals, self.expect_error);
                                _ = try tokens.expect(Token.space, self.expect_error);

                                const import_alias = switch (try tokens.expectOneOf(
                                    &[_]TokenTag{ .symbol, .name },
                                    self.expect_error,
                                )) {
                                    .symbol => |symbol| symbol,
                                    .name => |name| name,
                                    else => unreachable,
                                };

                                return Definition{
                                    .import = Import{ .name = import_name, .alias = import_alias },
                                };
                            },
                            else => unreachable,
                        }
                    }
                },
                else => {},
            }
        }

        return null;
    }

    fn parseUnionOptions(self: *Self) !UnionOptions {
        const tokens = &self.token_iterator;

        var options = UnionOptions{ .tag_field = "type", .embedded = false };

        var done_parsing_options = false;
        while (!done_parsing_options) {
            const symbol = (try tokens.expect(Token.symbol, self.expect_error)).symbol;
            if (mem.eql(u8, symbol, "tag")) {
                _ = try tokens.expect(Token.space, self.expect_error);
                _ = try tokens.expect(Token.equals, self.expect_error);
                _ = try tokens.expect(Token.space, self.expect_error);
                options.tag_field = (try tokens.expect(Token.symbol, self.expect_error)).symbol;
            } else if (mem.eql(u8, symbol, "embedded")) {
                options.embedded = true;
            }
            if (try tokens.peek()) |t| {
                switch (t) {
                    .right_parenthesis => done_parsing_options = true,
                    else => {
                        _ = try tokens.expect(Token.comma, self.expect_error);
                        _ = try tokens.expect(Token.space, self.expect_error);
                    },
                }
            }
        }
        _ = try tokens.expect(Token.right_parenthesis, self.expect_error);
        _ = try tokens.expect(Token.space, self.expect_error);

        return options;
    }

    fn parseUntaggedUnionDefinition(self: *Self) !UntaggedUnion {
        const tokens = &self.token_iterator;

        const name = (try tokens.expect(Token.name, self.expect_error)).name;

        _ = try tokens.expect(Token.space, self.expect_error);
        _ = try tokens.expect(Token.left_brace, self.expect_error);
        _ = try tokens.expect(Token.newline, self.expect_error);

        var values = ArrayList(UntaggedUnionValue).init(self.allocator);
        var done_parsing_values = false;
        while (!done_parsing_values) {
            try tokens.skipMany(Token.space, 4, self.expect_error);
            const value_name = (try tokens.expect(Token.name, self.expect_error)).name;

            _ = try tokens.expect(Token.newline, self.expect_error);

            if (try tokens.peek()) |t| {
                switch (t) {
                    .right_brace => done_parsing_values = true,
                    else => {},
                }
            }

            try values.append(UntaggedUnionValue{ .name = value_name });
        }

        return UntaggedUnion{ .name = name, .values = values.items };
    }

    fn parseEnumerationDefinition(self: *Self) !Enumeration {
        const tokens = &self.token_iterator;

        const name = (try tokens.expect(Token.name, self.expect_error)).name;

        _ = try tokens.expect(Token.space, self.expect_error);
        _ = try tokens.expect(Token.left_brace, self.expect_error);
        _ = try tokens.expect(Token.newline, self.expect_error);

        var fields = ArrayList(EnumerationField).init(self.allocator);
        var done_parsing_fields = false;
        while (!done_parsing_fields) {
            try tokens.skipMany(Token.space, 4, self.expect_error);
            const tag = switch (try tokens.expectOneOf(
                &[_]TokenTag{ .symbol, .name },
                self.expect_error,
            )) {
                .symbol => |s| s,
                .name => |n| n,
                else => unreachable,
            };

            _ = try tokens.expect(Token.space, self.expect_error);
            _ = try tokens.expect(Token.equals, self.expect_error);
            _ = try tokens.expect(Token.space, self.expect_error);

            const value = switch (try tokens.expectOneOf(
                &[_]TokenTag{ .string, .unsigned_integer },
                self.expect_error,
            )) {
                .string => |s| EnumerationValue{ .string = s },
                .unsigned_integer => |ui| EnumerationValue{ .unsigned_integer = ui },
                else => unreachable,
            };

            _ = try tokens.expect(Token.newline, self.expect_error);
            if (try tokens.peek()) |t| {
                switch (t) {
                    .right_brace => done_parsing_fields = true,
                    else => {},
                }
            }

            try fields.append(EnumerationField{ .tag = tag, .value = value });
        }

        return Enumeration{ .name = name, .fields = fields.items };
    }

    pub fn parseStructureDefinition(self: *Self) !Structure {
        var tokens = &self.token_iterator;
        const definition_name = (try tokens.expect(Token.name, self.expect_error)).name;

        _ = try tokens.expect(Token.space, self.expect_error);

        const left_angle_or_left_brace = try tokens.expectOneOf(
            &[_]TokenTag{ .left_angle, .left_brace },
            self.expect_error,
        );

        return switch (left_angle_or_left_brace) {
            .left_brace => Structure{
                .plain = try self.parsePlainStructureDefinition(definition_name),
            },
            .left_angle => Structure{
                .generic = try self.parseGenericStructureDefinition(definition_name),
            },
            else => debug.panic(
                "Invalid follow-up token after `struct` keyword: {}\n",
                .{left_angle_or_left_brace},
            ),
        };
    }

    pub fn parsePlainStructureDefinition(
        self: *Self,
        definition_name: []const u8,
    ) !PlainStructure {
        var fields = ArrayList(Field).init(self.allocator);
        const tokens = &self.token_iterator;

        _ = try tokens.expect(Token.newline, self.expect_error);
        var done_parsing_fields = false;
        while (!done_parsing_fields) {
            if (try tokens.peek()) |t| {
                switch (t) {
                    .right_brace => done_parsing_fields = true,
                    else => {},
                }
            }
            if (!done_parsing_fields) {
                try fields.append(try self.parseStructureField());
            }
        }
        _ = try tokens.expect(Token.right_brace, self.expect_error);

        return PlainStructure{
            .name = try self.allocator.dupe(u8, definition_name),
            .fields = fields.items,
        };
    }

    fn parseOpenNames(self: *Self) ![][]const u8 {
        const tokens = &self.token_iterator;

        var open_names = ArrayList([]const u8).init(self.allocator);

        const p = try tokens.peek();
        const first_name = try tokens.expect(Token.name, self.expect_error);
        try open_names.append(first_name.name);
        var open_names_done = false;
        while (!open_names_done) {
            const right_angle_or_comma = try tokens.expectOneOf(
                &[_]TokenTag{ .right_angle, .comma },
                self.expect_error,
            );
            switch (right_angle_or_comma) {
                .right_angle => open_names_done = true,
                .comma => try open_names.append(try self.parseAdditionalName()),
                else => unreachable,
            }
        }

        return open_names.items;
    }

    pub fn parseGenericStructureDefinition(
        self: *Self,
        definition_name: []const u8,
    ) !GenericStructure {
        var fields = ArrayList(Field).init(self.allocator);
        const tokens = &self.token_iterator;

        const open_names = try self.parseOpenNames();

        _ = try tokens.expect(Token.left_brace, self.expect_error);
        _ = try tokens.expect(Token.newline, self.expect_error);
        var done_parsing_fields = false;
        while (!done_parsing_fields) {
            if (try tokens.peek()) |t| {
                switch (t) {
                    .right_brace => done_parsing_fields = true,
                    else => {},
                }
            }
            if (!done_parsing_fields) {
                try fields.append(try self.parseStructureField());
            }
        }
        _ = try tokens.expect(Token.right_brace, self.expect_error);

        return GenericStructure{
            .name = try self.allocator.dupe(u8, definition_name),
            .fields = fields.items,
            .open_names = open_names,
        };
    }

    fn parseUnionDefinition(self: *Self, options: UnionOptions) !Union {
        const tokens = &self.token_iterator;

        const definition_name = (try tokens.expect(Token.name, self.expect_error)).name;

        _ = try tokens.expect(Token.space, self.expect_error);

        const left_angle_or_left_brace = try tokens.expectOneOf(
            &[_]TokenTag{ .left_angle, .left_brace },
            self.expect_error,
        );

        return switch (left_angle_or_left_brace) {
            .left_brace => Union{
                .plain = try self.parsePlainUnionDefinition(definition_name, options),
            },
            .left_angle => Union{
                .generic = try self.parseGenericUnionDefinition(definition_name, options),
            },
            else => debug.panic(
                "Invalid follow-up token after `union` keyword: {}\n",
                .{left_angle_or_left_brace},
            ),
        };
    }

    pub fn parsePlainUnionDefinition(
        self: *Self,
        definition_name: []const u8,
        options: UnionOptions,
    ) !PlainUnion {
        var constructors = ArrayList(Constructor).init(self.allocator);
        const tokens = &self.token_iterator;

        _ = try tokens.expect(Token.newline, self.expect_error);
        var done_parsing_constructors = false;
        while (!done_parsing_constructors) {
            if (try tokens.peek()) |t| {
                switch (t) {
                    .right_brace => done_parsing_constructors = true,
                    else => {},
                }
            }
            if (!done_parsing_constructors) {
                try constructors.append(try self.parseConstructor());
            }
        }
        _ = try tokens.expect(Token.right_brace, self.expect_error);

        return PlainUnion{
            .name = try self.allocator.dupe(u8, definition_name),
            .constructors = constructors.items,
            .tag_field = options.tag_field,
        };
    }

    pub fn parseGenericUnionDefinition(
        self: *Self,
        definition_name: []const u8,
        options: UnionOptions,
    ) !GenericUnion {
        var constructors = ArrayList(Constructor).init(self.allocator);
        var open_names = ArrayList([]const u8).init(self.allocator);
        const tokens = &self.token_iterator;

        const first_name = try tokens.expect(Token.name, self.expect_error);
        try open_names.append(first_name.name);
        var open_names_done = false;
        while (!open_names_done) {
            const right_angle_or_comma = try tokens.expectOneOf(
                &[_]TokenTag{ .right_angle, .comma },
                self.expect_error,
            );
            switch (right_angle_or_comma) {
                .right_angle => open_names_done = true,
                .comma => try open_names.append(try self.parseAdditionalName()),
                else => unreachable,
            }
        }

        _ = try tokens.expect(Token.left_brace, self.expect_error);
        _ = try tokens.expect(Token.newline, self.expect_error);

        var done_parsing_constructors = false;
        while (!done_parsing_constructors) {
            if (try tokens.peek()) |t| {
                switch (t) {
                    .right_brace => done_parsing_constructors = true,
                    else => {},
                }
            }
            if (!done_parsing_constructors) {
                try constructors.append(try self.parseConstructor());
            }
        }
        _ = try tokens.expect(Token.right_brace, self.expect_error);

        return GenericUnion{
            .name = try self.allocator.dupe(u8, definition_name),
            .constructors = constructors.items,
            .open_names = open_names.items,
            .tag_field = options.tag_field,
        };
    }

    fn parseConstructor(self: *Self) !Constructor {
        const tokens = &self.token_iterator;

        _ = try tokens.skipMany(Token.space, 4, self.expect_error);

        const tag = switch (try tokens.expectOneOf(
            &[_]TokenTag{ .name, .symbol },
            self.expect_error,
        )) {
            .name => |n| n,
            .symbol => |s| s,
            else => unreachable,
        };

        const colon_or_newline = try tokens.expectOneOf(
            &[_]TokenTag{ .colon, .newline },
            self.expect_error,
        );

        if (colon_or_newline == Token.newline) {
            return Constructor{ .tag = tag, .parameter = Type.empty };
        }

        _ = try tokens.expect(Token.space, self.expect_error);

        const parameter = try self.parseFieldType();

        return Constructor{ .tag = tag, .parameter = parameter };
    }

    fn parseAdditionalName(self: *Self) ![]const u8 {
        const tokens = &self.token_iterator;
        _ = try tokens.expect(Token.space, self.expect_error);
        const name = try tokens.expect(Token.name, self.expect_error);

        return try self.allocator.dupe(u8, name.name);
    }

    fn parseStructureField(self: *Self) !Field {
        var tokens = &self.token_iterator;
        _ = try tokens.skipMany(Token.space, 4, self.expect_error);
        const field_name = (try tokens.expect(Token.symbol, self.expect_error)).symbol;
        _ = try tokens.expect(Token.colon, self.expect_error);
        _ = try tokens.expect(Token.space, self.expect_error);

        const field_type = try self.parseFieldType();

        return Field{ .name = field_name, .@"type" = field_type };
    }

    fn parseMaybeAppliedName(self: *Self, name: []const u8) !?AppliedName {
        const tokens = &self.token_iterator;

        const maybe_left_angle_token = try tokens.peek();
        if (maybe_left_angle_token) |maybe_left_angle| {
            switch (maybe_left_angle) {
                // we have an applied name
                .left_angle => {
                    _ = try tokens.expect(Token.left_angle, self.expect_error);
                    var names = ArrayList([]const u8).init(self.allocator);
                    const open_names = try self.parseOpenNames();

                    return AppliedName{ .name = name, .open_names = open_names };
                },
                else => {},
            }
        }

        return null;
    }

    fn parseFieldType(self: *Self) !Type {
        const tokens = &self.token_iterator;

        const field_type_start_token = try tokens.expectOneOf(
            &[_]TokenTag{ .string, .name, .left_bracket, .asterisk, .question_mark },
            self.expect_error,
        );

        const field = switch (field_type_start_token) {
            .string => |s| Type{ .string = s },
            .name => |name| field_type: {
                if (try self.parseMaybeAppliedName(name)) |applied_name| {
                    break :field_type Type{ .applied_name = applied_name };
                } else {
                    break :field_type Type{ .name = name };
                }
            },

            .left_bracket => field_type: {
                const right_bracket_or_number = try tokens.expectOneOf(
                    &[_]TokenTag{ .right_bracket, .unsigned_integer },
                    self.expect_error,
                );

                switch (right_bracket_or_number) {
                    .right_bracket => {
                        var slice_type = try self.allocator.create(Type);
                        slice_type.* = Type{
                            .name = (try tokens.expect(Token.name, self.expect_error)).name,
                        };

                        break :field_type Type{ .slice = Slice{ .@"type" = slice_type } };
                    },
                    .unsigned_integer => |ui| {
                        _ = try tokens.expect(Token.right_bracket, self.expect_error);
                        var array_type = try self.allocator.create(Type);
                        const array_type_name = (try tokens.expect(Token.name, self.expect_error)).name;
                        array_type.* = Type{ .name = array_type_name };
                        break :field_type Type{ .array = Array{ .@"type" = array_type, .size = ui } };
                    },
                    else => {
                        debug.panic(
                            "Unknown slice/array component, expecting closing bracket or unsigned integer plus closing bracket. Got: {}\n",
                            .{right_bracket_or_number},
                        );
                    },
                }
            },

            .asterisk => field_type: {
                var field_type = try self.allocator.create(Type);
                const name = (try tokens.expect(Token.name, self.expect_error)).name;
                field_type.* = if (try self.parseMaybeAppliedName(name)) |applied_name|
                    Type{ .applied_name = applied_name }
                else
                    Type{ .name = name };

                break :field_type Type{ .pointer = Pointer{ .@"type" = field_type } };
            },

            .question_mark => field_type: {
                var field_type = try self.allocator.create(Type);
                const name = (try tokens.expect(Token.name, self.expect_error)).name;
                field_type.* = if (try self.parseMaybeAppliedName(name)) |applied_name|
                    Type{ .applied_name = applied_name }
                else
                    Type{ .name = name };

                break :field_type Type{ .optional = Optional{ .@"type" = field_type } };
            },

            else => {
                debug.panic(
                    "Unexpected token in place of field value/type: {}",
                    .{field_type_start_token},
                );
            },
        };
        const p = try tokens.peek();
        _ = try tokens.expect(Token.newline, self.expect_error);

        return field;
    }
};

test "Parsing `Person` structure" {
    var allocator = TestingAllocator{};
    var hobbies_slice_type = Type{ .name = "String" };
    var comments_array_type = Type{ .name = "String" };
    var recruiter_pointer_type = Type{ .name = "Person" };

    const expected_definitions = [_]Definition{.{
        .structure = Structure{
            .plain = PlainStructure{
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
                    .{
                        .name = "recruiter",
                        .@"type" = Type{ .pointer = Pointer{ .@"type" = &recruiter_pointer_type } },
                    },
                },
            },
        },
    }};

    var expect_error: ExpectError = undefined;
    const definitions = try parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        type_examples.person_structure,
        &expect_error,
    );
    expectEqualDefinitions(&expected_definitions, definitions);
}

test "Parsing basic generic structure" {
    var allocator = TestingAllocator{};

    var fields = [_]Field{
        .{ .name = "data", .@"type" = Type{ .name = "T" } },
    };

    const expected_definitions = [_]Definition{.{
        .structure = Structure{
            .generic = GenericStructure{
                .name = "Node",
                .fields = &fields,
                .open_names = &[_][]const u8{"T"},
            },
        },
    }};

    var expect_error: ExpectError = undefined;
    const definitions = try parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        type_examples.node_structure,
        &expect_error,
    );

    expectEqualDefinitions(&expected_definitions, definitions);
}

test "Parsing basic plain union" {
    var allocator = TestingAllocator{};

    var channels_slice_type = Type{ .name = "Channel" };
    var set_emails_array_type = Type{ .name = "Email" };
    var expected_constructors = [_]Constructor{
        .{ .tag = "LogIn", .parameter = Type{ .name = "LogInData" } },
        .{ .tag = "LogOut", .parameter = Type{ .name = "UserId" } },
        .{
            .tag = "JoinChannels",
            .parameter = Type{ .slice = Slice{ .@"type" = &channels_slice_type } },
        },
        .{
            .tag = "SetEmails",
            .parameter = Type{ .array = Array{ .@"type" = &set_emails_array_type, .size = 5 } },
        },
    };

    const expected_definitions = [_]Definition{.{
        .@"union" = Union{
            .plain = PlainUnion{
                .name = "Event",
                .constructors = &expected_constructors,
                .tag_field = "type",
            },
        },
    }};

    var expect_error: ExpectError = undefined;
    const definitions = try parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        type_examples.event_union,
        &expect_error,
    );

    expectEqualDefinitions(&expected_definitions, definitions);
}

test "Parsing `Maybe` union" {
    var allocator = TestingAllocator{};

    var expected_constructors = [_]Constructor{
        .{ .tag = "just", .parameter = Type{ .name = "T" } },
        .{ .tag = "nothing", .parameter = Type.empty },
    };

    const expected_definitions = [_]Definition{.{
        .@"union" = Union{
            .generic = GenericUnion{
                .name = "Maybe",
                .constructors = &expected_constructors,
                .open_names = &[_][]const u8{"T"},
                .tag_field = "type",
            },
        },
    }};

    var expect_error: ExpectError = undefined;
    const definitions = try parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        type_examples.maybe_union,
        &expect_error,
    );

    expectEqualDefinitions(&expected_definitions, definitions);
}

test "Parsing `Either` union" {
    var allocator = TestingAllocator{};

    var expected_constructors = [_]Constructor{
        .{ .tag = "Left", .parameter = Type{ .name = "E" } },
        .{ .tag = "Right", .parameter = Type{ .name = "T" } },
    };

    const expected_definitions = [_]Definition{.{
        .@"union" = Union{
            .generic = GenericUnion{
                .name = "Either",
                .constructors = &expected_constructors,
                .open_names = &[_][]const u8{ "E", "T" },
                .tag_field = "type",
            },
        },
    }};

    var expect_error: ExpectError = undefined;
    const definitions = try parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        type_examples.either_union,
        &expect_error,
    );

    expectEqualDefinitions(&expected_definitions, definitions);
}

test "Parsing `List` union" {
    var allocator = TestingAllocator{};

    var applied_pointer_type = Type{
        .applied_name = AppliedName{ .name = "List", .open_names = &[_][]const u8{"T"} },
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
                .name = "List",
                .constructors = &expected_constructors,
                .open_names = &[_][]const u8{"T"},
                .tag_field = "type",
            },
        },
    }};

    var expect_error: ExpectError = undefined;
    const definitions = try parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        type_examples.list_union,
        &expect_error,
    );

    expectEqualDefinitions(&expected_definitions, definitions);
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
            .name = "BackdropSize",
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

    var expect_error: ExpectError = undefined;
    const definitions = try parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        definition_buffer,
        &expect_error,
    );

    expectEqualDefinitions(&expected_definitions, definitions);
}

test "Parsing untagged union" {
    var allocator = TestingAllocator{};

    var expected_values = [_]UntaggedUnionValue{
        .{ .name = "KnownForShow" },
        .{ .name = "KnownForMovie" },
    };

    const expected_definitions = [_]Definition{.{
        .untagged_union = UntaggedUnion{
            .name = "KnownFor",
            .values = &expected_values,
        },
    }};

    const definition_buffer =
        \\untagged union KnownFor {
        \\    KnownForShow
        \\    KnownForMovie
        \\}
    ;

    var expect_error: ExpectError = undefined;
    const definitions = try parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        definition_buffer,
        &expect_error,
    );

    expectEqualDefinitions(&expected_definitions, definitions);
}

test "Parsing imports, without and with alias, respectively" {
    var allocator = TestingAllocator{};

    const expected_definitions = [_]Definition{
        .{
            .import = Import{
                .name = "other",
                .alias = "other",
            },
        },
        .{
            .import = Import{
                .name = "importName",
                .alias = "aliasedName",
            },
        },
    };

    const definition_buffer =
        \\import other
        \\import importName = aliasedName
        \\
    ;

    var expect_error: ExpectError = undefined;
    const definitions = try parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        definition_buffer,
        &expect_error,
    );

    expectEqualDefinitions(&expected_definitions, definitions);
}

test "Parsing unions with options" {
    var allocator = TestingAllocator{};

    const definition_buffer =
        \\union(tag = kind) WithModifiedTag {
        \\    one: Value
        \\}
        \\
        \\union(embedded, tag = other_kind) EmbeddedWithModifiedTag {
        \\    one: Value
        \\}
        \\
    ;

    var expected_constructors = [_]Constructor{
        .{ .tag = "one", .parameter = Type{ .name = "Value" } },
    };

    const expected_definitions = [_]Definition{
        .{
            .@"union" = Union{
                .plain = PlainUnion{
                    .name = "WithModifiedTag",
                    .constructors = &expected_constructors,
                    .tag_field = "kind",
                },
            },
        },
        .{
            .@"union" = Union{
                .plain = PlainUnion{
                    .name = "EmbeddedWithModifiedTag",
                    .constructors = &expected_constructors,
                    .tag_field = "other_kind",
                },
            },
        },
    };

    var expect_error: ExpectError = undefined;
    const definitions = try parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        definition_buffer,
        &expect_error,
    );

    expectEqualDefinitions(&expected_definitions, definitions);
}

test "Parsing invalid normal structure" {
    var allocator = TestingAllocator{};
    var expect_error: ExpectError = undefined;
    _ = parse(
        &allocator.allocator,
        &allocator.allocator,
        "struct Container T{",
        &expect_error,
    ) catch |e| {
        switch (e) {
            error.UnexpectedEndOfTokenStream,
            error.OutOfMemory,
            error.Overflow,
            error.InvalidCharacter,
            => unreachable,
            error.UnexpectedToken => {
                switch (expect_error) {
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
                            .{expect_error},
                        );
                    },
                }
            },
        }
    };
}

test "Parsing multiple definitions works as it should" {
    var allocator = TestingAllocator{};
    var expect_error: ExpectError = undefined;

    const definitions = try parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        type_examples.person_structure_and_event_union,
        &expect_error,
    );

    var hobbies_slice_type = Type{ .name = "String" };
    var comments_array_type = Type{ .name = "String" };
    var recruiter_pointer_type = Type{ .name = "Person" };
    var channels_slice_type = Type{ .name = "Channel" };
    var set_emails_array_type = Type{ .name = "Email" };
    var expected_constructors = [_]Constructor{
        .{ .tag = "LogIn", .parameter = Type{ .name = "LogInData" } },
        .{ .tag = "LogOut", .parameter = Type{ .name = "UserId" } },
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
        .{
            .structure = Structure{
                .plain = PlainStructure{
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
                        .{
                            .name = "recruiter",
                            .@"type" = Type{ .pointer = Pointer{ .@"type" = &recruiter_pointer_type } },
                        },
                    },
                },
            },
        },
        .{
            .@"union" = Union{
                .plain = PlainUnion{
                    .name = "Event",
                    .constructors = &expected_constructors,
                    .tag_field = "type",
                },
            },
        },
    };

    expectEqualDefinitions(&expected_definitions, definitions);
}

pub fn expectEqualDefinitions(as: []const Definition, bs: []const Definition) void {
    const Names = struct {
        a: []const u8,
        b: []const u8,
    };

    const Fields = struct {
        a: []Field,
        b: []Field,
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
                    if (!mem.eql(u8, fields_and_names.names.a, fields_and_names.names.b)) {
                        debug.print(
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
                            if (!mem.eql(u8, plain.name, b.@"union".plain.name)) {
                                debug.print(
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
                            if (!mem.eql(u8, generic.name, b.@"union".generic.name)) {
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

fn expectEqualEnumerations(a: Enumeration, b: Enumeration) void {
    if (!mem.eql(u8, a.name, b.name)) {
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
    if (!mem.eql(u8, a.name, b.name)) {
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
    if (!mem.eql(u8, a.name, b.name)) {
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
