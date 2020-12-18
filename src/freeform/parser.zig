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

pub const ParsingError = union(enum) {
    expect: ExpectError,
    reference: ReferenceError,
};

pub const ReferenceError = union(enum) {
    invalid_payload_type: InvalidPayload,
    unknown_reference: UnknownReference,
};

pub const InvalidPayload = struct {
    payload: Definition,
    line: usize,
    column: usize,
};

pub const UnknownReference = struct {
    name: []const u8,
    line: usize,
    column: usize,
};

pub const Definition = union(enum) {
    const Self = @This();

    structure: Structure,
    @"union": Union,
    enumeration: Enumeration,
    untagged_union: UntaggedUnion,
    import: Import,

    pub fn free(self: *Self, allocator: *mem.Allocator) void {
        switch (self.*) {
            .structure => |*s| s.free(allocator),
            .@"union" => |*u| u.free(allocator),
            .enumeration => |*e| e.free(allocator),
            .untagged_union => |*u| u.free(allocator),
            .import => |*i| i.free(allocator),
        }
    }

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

    pub fn free(self: *Self, allocator: *mem.Allocator) void {
        if (self.name.ptr == self.alias.ptr) {
            allocator.free(self.name);
        } else {
            allocator.free(self.name);
            allocator.free(self.alias);
        }
    }

    pub fn isEqual(self: Self, other: Self) bool {
        return mem.eql(u8, self.name, other.name) and mem.eql(u8, self.alias, other.alias);
    }
};

pub const UntaggedUnion = struct {
    const Self = @This();

    name: []const u8,
    values: []UntaggedUnionValue,

    pub fn free(self: *Self, allocator: *mem.Allocator) void {
        allocator.free(self.name);
        for (self.values) |*value| value.free(allocator);
        allocator.free(self.values);
    }

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

    pub fn free(self: *Self, allocator: *mem.Allocator) void {
        allocator.free(self.name);
    }

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

    pub fn free(self: *Self, allocator: *mem.Allocator) void {
        allocator.free(self.name);
        for (self.fields) |*field| field.free(allocator);
        allocator.free(self.fields);
    }

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

    pub fn free(self: *Self, allocator: *mem.Allocator) void {
        allocator.free(self.tag);
        self.value.free(allocator);
    }

    pub fn isEqual(self: Self, other: Self) bool {
        return mem.eql(u8, self.tag, other.tag) and self.value.isEqual(other.value);
    }
};

pub const EnumerationValue = union(enum) {
    const Self = @This();

    string: []const u8,
    unsigned_integer: u64,

    pub fn free(self: *Self, allocator: *mem.Allocator) void {
        switch (self.*) {
            .string => |s| allocator.free(s),
            .unsigned_integer => {},
        }
    }

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

    pub fn free(self: *Self, allocator: *mem.Allocator) void {
        switch (self.*) {
            .plain => |*p| p.free(allocator),
            .generic => |*g| g.free(allocator),
        }
    }

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

    pub fn free(self: *Self, allocator: *mem.Allocator) void {
        allocator.free(self.name);
        for (self.fields) |*f| f.free(allocator);
        allocator.free(self.fields);
    }

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

    pub fn free(self: *Self, allocator: *mem.Allocator) void {
        allocator.free(self.name);
        for (self.fields) |*f| f.free(allocator);
        allocator.free(self.fields);
        for (self.open_names) |n| allocator.free(n);
        allocator.free(self.open_names);
    }

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

    pub fn free(self: *Self, allocator: *mem.Allocator) void {
        allocator.free(self.name);
        self.@"type".free(allocator);
    }

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

    pub fn free(self: *Self, allocator: *mem.Allocator) void {
        switch (self.*) {
            .name => |n| allocator.free(n),
            .string => |s| allocator.free(s),
            .array => |*a| {
                a.*.@"type".free(allocator);
                allocator.destroy(a.*.@"type");
            },
            .slice => |*s| {
                s.*.@"type".free(allocator);
                allocator.destroy(s.*.@"type");
            },
            .optional => |*o| {
                o.*.@"type".free(allocator);
                allocator.destroy(o.*.@"type");
            },
            .pointer => |*p| {
                p.*.@"type".free(allocator);
                allocator.destroy(p.*.@"type");
            },
            .applied_name => |a| {
                allocator.free(a.name);
                for (a.open_names) |name| allocator.free(name);

                allocator.free(a.open_names);
            },
            .empty => {},
        }
    }

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
    embedded: EmbeddedUnion,

    pub fn free(self: *Self, allocator: *mem.Allocator) void {
        switch (self.*) {
            .plain => |*p| p.free(allocator),
            .generic => |*g| g.free(allocator),
            .embedded => |*e| e.free(allocator),
        }
    }

    pub fn isEqual(self: Self, other: Self) bool {
        return switch (self) {
            .plain => |p| meta.activeTag(other) == .plain and p.isEqual(other.plain),
            .generic => |g| meta.activeTag(other) == .generic and g.isEqual(other.generic),
            .embedded => |e| meta.activeTag(other) == .embedded and e.isEqual(other.embedded),
        };
    }

    pub fn name(self: Self) []const u8 {
        return switch (self) {
            .plain => |plain| plain.name,
            .generic => |generic| generic.name,
            .embedded => |embedded| embedded.name,
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

    pub fn free(self: *Self, allocator: *mem.Allocator) void {
        allocator.free(self.name);
        for (self.constructors) |*c| c.free(allocator);
        allocator.free(self.constructors);
        allocator.free(self.tag_field);
    }

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

    pub fn free(self: *Self, allocator: *mem.Allocator) void {
        allocator.free(self.name);
        for (self.constructors) |*c| c.free(allocator);
        allocator.free(self.constructors);
        allocator.free(self.tag_field);
        for (self.open_names) |n| allocator.free(n);
        allocator.free(self.open_names);
    }

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

pub const EmbeddedUnion = struct {
    const Self = @This();

    name: []const u8,
    constructors: []ConstructorWithEmbeddedTypeTag,
    open_names: []const []const u8,
    tag_field: []const u8,

    pub fn free(self: *Self, allocator: *mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.tag_field);
        for (self.constructors) |*c| c.free(allocator);
        allocator.free(self.constructors);
        for (self.open_names) |n| allocator.free(n);
    }

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

pub const ConstructorWithEmbeddedTypeTag = struct {
    const Self = @This();

    tag: []const u8,
    parameter: ?Structure,

    pub fn free(self: *Self, allocator: *mem.Allocator) void {
        allocator.free(self.tag);
    }

    pub fn isEqual(self: Self, other: Self) bool {
        if (self.parameter) |parameter| {
            if (other.parameter == null or !parameter.isEqual(other.parameter.?)) return false;
        } else {
            if (other.parameter != null) return false;
        }

        return mem.eql(u8, self.tag, other.tag);
    }
};

pub const Constructor = struct {
    const Self = @This();

    tag: []const u8,
    parameter: Type,

    pub fn free(self: *Self, allocator: *mem.Allocator) void {
        allocator.free(self.tag);
        self.*.parameter.free(allocator);
    }

    pub fn isEqual(self: Self, other: Self) bool {
        return mem.eql(u8, self.tag, other.tag) and self.parameter.isEqual(other.parameter);
    }
};

const TestingAllocator = heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 20 });

pub const ParsedDefinitions = struct {
    const Self = @This();

    definitions: []Definition,
    definition_iterator: DefinitionIterator,
    allocator: *mem.Allocator,

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.definitions);
        self.definition_iterator.deinit();
    }
};

pub fn parse(
    allocator: *mem.Allocator,
    error_allocator: *mem.Allocator,
    buffer: []const u8,
    parsing_error: *ParsingError,
) !ParsedDefinitions {
    var definitions = ArrayList(Definition).init(allocator);
    var expect_error: ExpectError = undefined;
    var definition_iterator = DefinitionIterator.init(
        allocator,
        buffer,
        parsing_error,
        &expect_error,
    );

    while (definition_iterator.next() catch |e| switch (e) {
        error.UnexpectedToken => {
            definition_iterator.parsing_error.* = ParsingError{ .expect = expect_error };

            return e;
        },
        else => return e,
    }) |definition| {
        try definitions.append(definition);
    }

    return ParsedDefinitions{
        .definitions = definitions.items,
        .definition_iterator = definition_iterator,
        .allocator = allocator,
    };
}

pub fn parseWithDescribedError(
    allocator: *mem.Allocator,
    error_allocator: *mem.Allocator,
    buffer: []const u8,
    parsing_error: *ParsingError,
) !ParsedDefinitions {
    return parse(allocator, error_allocator, buffer, parsing_error) catch |e| {
        switch (e) {
            error.UnexpectedToken,
            error.UnknownReference,
            error.InvalidPayload,
            error.UnexpectedEndOfTokenStream,
            error.DuplicateDefinitions,
            => {
                switch (parsing_error.*) {
                    .expect => |expect| switch (expect) {
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
                    },
                    .reference => |reference| switch (reference) {
                        .invalid_payload_type => |invalid_payload| {
                            debug.panic(
                                "Invalid payload found at {}:{}, payload: {}\n",
                                .{
                                    invalid_payload.line,
                                    invalid_payload.column,
                                    invalid_payload.payload,
                                },
                            );
                        },
                        .unknown_reference => |unknown_reference| {
                            debug.panic(
                                "Unknown reference found at {}:{}, name: {}\n",
                                .{
                                    unknown_reference.line,
                                    unknown_reference.column,
                                    unknown_reference.name,
                                },
                            );
                        },
                    },
                }
            },
            else => return e,
        }
    };
}

const DefinitionMap = std.StringHashMap(Definition);

/// `DefinitionIterator` is iterator that attempts to return the next definition in a source, based
/// on a `TokenIterator` that it holds inside of its instance. It's an unapologetically stateful
/// thing; most of what is going on in here depends entirely on the order methods are called and it
/// keeps whatever state it needs in the object itself.
pub const DefinitionIterator = struct {
    const Self = @This();

    token_iterator: TokenIterator,
    allocator: *mem.Allocator,
    parsing_error: *ParsingError,
    expect_error: *ExpectError,

    /// Holds all of the named definitions that have been parsed and is filled in each time a
    /// definition is successfully parsed, making it possible to refer to already parsed definitions
    /// when parsing later ones.
    named_definitions: DefinitionMap,

    /// We hold a list to the imports such that we can also free them properly.
    imports: ArrayList(Import),

    pub fn init(
        allocator: *mem.Allocator,
        buffer: []const u8,
        parsing_error: *ParsingError,
        expect_error: *ExpectError,
    ) Self {
        var token_iterator = tokenizer.TokenIterator.init(buffer);

        return DefinitionIterator{
            .token_iterator = token_iterator,
            .allocator = allocator,
            .parsing_error = parsing_error,
            .named_definitions = DefinitionMap.init(allocator),
            .imports = ArrayList(Import).init(allocator),
            .expect_error = expect_error,
        };
    }

    pub fn deinit(self: *Self) void {
        var definition_iterator = self.named_definitions.iterator();

        for (self.imports.items) |*i| i.free(self.allocator);
        self.imports.deinit();

        //     .plain => |p| {
        //         for (p.constructors) |*constructor| {
        //             constructor.free(self.allocator);
        //         }

        //         self.allocator.free(p.constructors);
        //         self.allocator.free(p.name);
        //         self.allocator.free(p.tag_field);
        //     },
        //     .embedded => |e| {
        //         self.allocator.free(e.constructors);
        //         self.allocator.free(e.open_names);
        //         self.allocator.free(e.tag_field);
        //         self.allocator.free(e.name);
        //     },
        // },
        // switch (s) {
        //                     .plain => |p| {
        //                         for (p.fields) |*field| {
        //                             field.free(self.allocator);
        //                         }

        //                         self.allocator.free(p.fields);
        //                         self.allocator.free(p.name);
        //                     },
        //                     .generic => |g| {
        //                         for (g.fields) |*field| {
        //                             field.free(self.allocator);
        //                         }

        //                         for (g.open_names) |name| self.allocator.free(name);

        //                         self.allocator.free(g.open_names);
        //                         self.allocator.free(g.fields);
        //                         self.allocator.free(g.name);
        //                     },
        //                 }

        while (definition_iterator.next()) |entry| {
            entry.*.value.free(self.allocator);
            // switch (entry.*.value) {
            //     .@"union" => |*u| u.free(self.allocator),
            //     .structure => |*s| s.free(self.allocator),
            //     .enumeration => |*enumeration| enumeration.free(self.allocator),
            //     .untagged_union => |*u| u.free(self.allocator),

            //     .import => unreachable,
            // }
        }

        self.named_definitions.deinit();
    }

    pub fn next(self: *Self) !?Definition {
        const tokens = &self.token_iterator;

        while (try tokens.next(.{})) |token| {
            switch (token) {
                .symbol => |s| {
                    if (mem.eql(u8, s, "struct")) {
                        _ = try tokens.expect(Token.space, self.expect_error);

                        const definition = Definition{
                            .structure = try self.parseStructureDefinition(),
                        };
                        try self.addDefinition(definition.structure.name(), definition);

                        return definition;
                    } else if (mem.eql(u8, s, "union")) {
                        const space_or_left_parenthesis = try tokens.expectOneOf(
                            &[_]TokenTag{ .space, .left_parenthesis },
                            self.expect_error,
                        );

                        switch (space_or_left_parenthesis) {
                            .space => {
                                const definition = Definition{
                                    .@"union" = try self.parseUnionDefinition(
                                        UnionOptions{
                                            .tag_field = try self.allocator.dupe(u8, "type"),
                                            .embedded = false,
                                        },
                                    ),
                                };
                                try self.addDefinition(definition.@"union".name(), definition);

                                return definition;
                            },
                            .left_parenthesis => {
                                const options = try self.parseUnionOptions();

                                const definition = if (options.embedded)
                                    Definition{
                                        .@"union" = Union{
                                            .embedded = try self.parseEmbeddedUnionDefinition(options),
                                        },
                                    }
                                else
                                    Definition{ .@"union" = try self.parseUnionDefinition(options) };

                                try self.addDefinition(definition.@"union".name(), definition);

                                return definition;
                            },
                            else => unreachable,
                        }
                    } else if (mem.eql(u8, s, "enum")) {
                        _ = try tokens.expect(Token.space, self.expect_error);

                        const definition = Definition{
                            .enumeration = try self.parseEnumerationDefinition(),
                        };
                        try self.addDefinition(definition.enumeration.name, definition);

                        return definition;
                    } else if (mem.eql(u8, s, "untagged")) {
                        _ = try tokens.expect(Token.space, self.expect_error);
                        const union_keyword = (try tokens.expect(
                            Token.symbol,
                            self.expect_error,
                        )).symbol;
                        debug.assert(mem.eql(u8, union_keyword, "union"));
                        _ = try tokens.expect(Token.space, self.expect_error);

                        const definition = Definition{
                            .untagged_union = try self.parseUntaggedUnionDefinition(),
                        };
                        try self.addDefinition(definition.untagged_union.name, definition);

                        return definition;
                    } else if (mem.eql(u8, s, "import")) {
                        _ = try tokens.expect(Token.space, self.expect_error);

                        const import = try self.parseImport();
                        try self.imports.append(import);
                        const definition = Definition{ .import = import };

                        return definition;
                    }
                },
                else => {},
            }
        }

        return null;
    }

    fn parseImport(self: *Self) !Import {
        const tokens = &self.token_iterator;

        const import_name = switch (try tokens.expectOneOf(
            &[_]TokenTag{ .symbol, .name },
            self.expect_error,
        )) {
            .symbol => |symbol| try self.allocator.dupe(u8, symbol),
            .name => |name| try self.allocator.dupe(u8, name),
            else => unreachable,
        };

        return switch (try tokens.expectOneOf(
            &[_]TokenTag{ .newline, .space },
            self.expect_error,
        )) {
            .newline => Import{ .name = import_name, .alias = import_name },
            .space => with_alias: {
                _ = try tokens.expect(Token.equals, self.expect_error);
                _ = try tokens.expect(Token.space, self.expect_error);

                const import_alias = switch (try tokens.expectOneOf(
                    &[_]TokenTag{ .symbol, .name },
                    self.expect_error,
                )) {
                    .symbol => |symbol| try self.allocator.dupe(u8, symbol),
                    .name => |name| try self.allocator.dupe(u8, name),
                    else => unreachable,
                };

                break :with_alias Import{ .name = import_name, .alias = import_alias };
            },
            else => unreachable,
        };
    }

    fn parseUnionOptions(self: *Self) !UnionOptions {
        const tokens = &self.token_iterator;

        var options = UnionOptions{
            .tag_field = try self.allocator.dupe(u8, "type"),
            .embedded = false,
        };

        var done_parsing_options = false;
        while (!done_parsing_options) {
            const symbol = (try tokens.expect(Token.symbol, self.expect_error)).symbol;
            if (mem.eql(u8, symbol, "tag")) {
                _ = try tokens.expect(Token.space, self.expect_error);
                _ = try tokens.expect(Token.equals, self.expect_error);
                _ = try tokens.expect(Token.space, self.expect_error);
                self.allocator.free(options.tag_field);
                options.tag_field = try self.allocator.dupe(
                    u8,
                    (try tokens.expect(Token.symbol, self.expect_error)).symbol,
                );
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

        const name = try self.allocator.dupe(
            u8,
            (try tokens.expect(Token.name, self.expect_error)).name,
        );

        _ = try tokens.expect(Token.space, self.expect_error);
        _ = try tokens.expect(Token.left_brace, self.expect_error);
        _ = try tokens.expect(Token.newline, self.expect_error);

        var values = ArrayList(UntaggedUnionValue).init(self.allocator);
        defer values.deinit();
        var done_parsing_values = false;
        while (!done_parsing_values) {
            try tokens.skipMany(Token.space, 4, self.expect_error);
            const value_name = try self.allocator.dupe(
                u8,
                (try tokens.expect(Token.name, self.expect_error)).name,
            );

            _ = try tokens.expect(Token.newline, self.expect_error);

            if (try tokens.peek()) |t| {
                switch (t) {
                    .right_brace => done_parsing_values = true,
                    else => {},
                }
            }

            try values.append(UntaggedUnionValue{ .name = value_name });
        }

        return UntaggedUnion{ .name = name, .values = values.toOwnedSlice() };
    }

    fn parseEnumerationDefinition(self: *Self) !Enumeration {
        const tokens = &self.token_iterator;

        const name = try self.allocator.dupe(
            u8,
            (try tokens.expect(Token.name, self.expect_error)).name,
        );

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
                .symbol => |s| try self.allocator.dupe(u8, s),
                .name => |n| try self.allocator.dupe(u8, n),
                else => unreachable,
            };

            _ = try tokens.expect(Token.space, self.expect_error);
            _ = try tokens.expect(Token.equals, self.expect_error);
            _ = try tokens.expect(Token.space, self.expect_error);

            const value = switch (try tokens.expectOneOf(
                &[_]TokenTag{ .string, .unsigned_integer },
                self.expect_error,
            )) {
                .string => |s| EnumerationValue{ .string = try self.allocator.dupe(u8, s) },
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
        const definition_name = try self.allocator.dupe(
            u8,
            (try tokens.expect(Token.name, self.expect_error)).name,
        );

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

        return PlainStructure{ .name = definition_name, .fields = fields.items };
    }

    fn parseOpenNames(self: *Self) ![][]const u8 {
        const tokens = &self.token_iterator;

        var open_names = ArrayList([]const u8).init(self.allocator);
        defer open_names.deinit();

        const first_name = try self.allocator.dupe(
            u8,
            (try tokens.expect(Token.name, self.expect_error)).name,
        );
        try open_names.append(first_name);
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

        return open_names.toOwnedSlice();
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
            .name = definition_name,
            .fields = fields.items,
            .open_names = open_names,
        };
    }

    fn parseUnionDefinition(self: *Self, options: UnionOptions) !Union {
        const tokens = &self.token_iterator;

        const definition_name = try self.allocator.dupe(
            u8,
            (try tokens.expect(Token.name, self.expect_error)).name,
        );

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

    fn parseEmbeddedUnionDefinition(self: *Self, options: UnionOptions) !EmbeddedUnion {
        const tokens = &self.token_iterator;

        const definition_name = try self.allocator.dupe(
            u8,
            (try tokens.expect(Token.name, self.expect_error)).name,
        );

        _ = try tokens.expect(Token.space, self.expect_error);

        var open_names = try self.allocator.alloc([]const u8, 0);
        const left_angle_or_left_brace = try tokens.expectOneOf(
            &[_]TokenTag{ .left_angle, .left_brace },
            self.expect_error,
        );
        switch (left_angle_or_left_brace) {
            .left_angle => {
                open_names = try self.parseOpenNames();
                _ = try tokens.expect(Token.left_brace, self.expect_error);
            },
            .left_brace => {},
            else => unreachable,
        }

        _ = try tokens.expect(Token.newline, self.expect_error);

        var constructors = ArrayList(ConstructorWithEmbeddedTypeTag).init(self.allocator);
        var done_parsing_constructors = false;
        while (!done_parsing_constructors) {
            try tokens.skipMany(Token.space, 4, self.expect_error);
            const tag = switch (try tokens.expectOneOf(
                &[_]TokenTag{ .name, .symbol },
                self.expect_error,
            )) {
                .name => |n| try self.allocator.dupe(u8, n),
                .symbol => |s| try self.allocator.dupe(u8, s),
                else => unreachable,
            };

            switch (try tokens.expectOneOf(&[_]TokenTag{ .colon, .newline }, self.expect_error)) {
                .newline => try constructors.append(ConstructorWithEmbeddedTypeTag{
                    .tag = tag,
                    .parameter = null,
                }),
                .colon => {
                    _ = try tokens.expect(Token.space, self.expect_error);

                    const parameter_name = (try tokens.expect(Token.name, self.expect_error)).name;
                    const definition_for_name = self.getDefinition(parameter_name);
                    if (definition_for_name) |definition| {
                        const parameter = switch (definition) {
                            .structure => |s| s,
                            else => {
                                self.parsing_error.* = ParsingError{
                                    .reference = ReferenceError{
                                        .invalid_payload_type = InvalidPayload{
                                            .line = self.token_iterator.line,
                                            .column = self.token_iterator.column,
                                            .payload = definition,
                                        },
                                    },
                                };

                                return error.InvalidPayload;
                            },
                        };

                        try constructors.append(ConstructorWithEmbeddedTypeTag{
                            .tag = tag,
                            .parameter = parameter,
                        });

                        _ = try tokens.expect(Token.newline, self.expect_error);
                    } else {
                        const line = self.token_iterator.line;
                        const column = self.token_iterator.column;
                        const name = parameter_name;

                        self.parsing_error.* = ParsingError{
                            .reference = ReferenceError{
                                .unknown_reference = UnknownReference{
                                    .line = line,
                                    .column = column,
                                    .name = name,
                                },
                            },
                        };

                        return error.UnknownReference;
                    }
                },
                else => unreachable,
            }

            if (try tokens.peek()) |t| {
                switch (t) {
                    .right_brace => done_parsing_constructors = true,
                    else => {},
                }
            }
        }

        _ = try tokens.expect(Token.right_brace, self.expect_error);

        return EmbeddedUnion{
            .name = definition_name,
            .constructors = constructors.items,
            .open_names = open_names,
            .tag_field = options.tag_field,
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
            .name = definition_name,
            .constructors = constructors.items,
            .tag_field = options.tag_field,
        };
    }

    pub fn parseGenericUnionDefinition(
        self: *Self,
        definition_name: []const u8,
        options: UnionOptions,
    ) !GenericUnion {
        const tokens = &self.token_iterator;
        var constructors = ArrayList(Constructor).init(self.allocator);
        var open_names = try self.parseOpenNames();

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
            .name = definition_name,
            .constructors = constructors.items,
            .open_names = open_names,
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
            .name => |n| try self.allocator.dupe(u8, n),
            .symbol => |s| try self.allocator.dupe(u8, s),
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
        const name = (try tokens.expect(Token.name, self.expect_error)).name;

        return try self.allocator.dupe(u8, name);
    }

    fn parseStructureField(self: *Self) !Field {
        var tokens = &self.token_iterator;
        _ = try tokens.skipMany(Token.space, 4, self.expect_error);
        const field_name = try self.allocator.dupe(
            u8,
            (try tokens.expect(Token.symbol, self.expect_error)).symbol,
        );
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
            .string => |s| Type{ .string = try self.allocator.dupe(u8, s) },
            .name => |name| field_type: {
                if (try self.parseMaybeAppliedName(name)) |applied_name| {
                    break :field_type Type{ .applied_name = applied_name };
                } else {
                    break :field_type Type{ .name = try self.allocator.dupe(u8, name) };
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
                            .name = try self.allocator.dupe(
                                u8,
                                (try tokens.expect(Token.name, self.expect_error)).name,
                            ),
                        };

                        break :field_type Type{ .slice = Slice{ .@"type" = slice_type } };
                    },
                    .unsigned_integer => |ui| {
                        _ = try tokens.expect(Token.right_bracket, self.expect_error);
                        var array_type = try self.allocator.create(Type);
                        const array_type_name = try self.allocator.dupe(
                            u8,
                            (try tokens.expect(
                                Token.name,
                                self.expect_error,
                            )).name,
                        );
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
                const name = try self.allocator.dupe(
                    u8,
                    (try tokens.expect(Token.name, self.expect_error)).name,
                );
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

    fn addDefinition(self: *Self, name: []const u8, definition: Definition) !void {
        const result = try self.named_definitions.getOrPut(name);

        if (result.found_existing)
            return error.DuplicateDefinitions
        else
            result.entry.*.value = definition;
    }

    fn getDefinition(self: Self, name: []const u8) ?Definition {
        return if (self.named_definitions.getEntry(name)) |definition|
            definition.value
        else
            null;
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

    var parsing_error: ParsingError = undefined;
    var definitions = try parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        type_examples.person_structure,
        &parsing_error,
    );

    expectEqualDefinitions(&expected_definitions, definitions.definitions);

    definitions.deinit();
    _ = allocator.detectLeaks();
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

    var parsing_error: ParsingError = undefined;
    var definitions = try parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        type_examples.node_structure,
        &parsing_error,
    );

    expectEqualDefinitions(&expected_definitions, definitions.definitions);

    definitions.deinit();
    _ = allocator.detectLeaks();
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

    var parsing_error: ParsingError = undefined;
    var definitions = try parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        type_examples.event_union,
        &parsing_error,
    );

    expectEqualDefinitions(&expected_definitions, definitions.definitions);

    definitions.deinit();
    _ = allocator.detectLeaks();
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

    var parsing_error: ParsingError = undefined;
    var definitions = try parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        type_examples.maybe_union,
        &parsing_error,
    );

    expectEqualDefinitions(&expected_definitions, definitions.definitions);

    definitions.deinit();
    _ = allocator.detectLeaks();
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

    var parsing_error: ParsingError = undefined;
    var definitions = try parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        type_examples.either_union,
        &parsing_error,
    );

    expectEqualDefinitions(&expected_definitions, definitions.definitions);

    definitions.deinit();
    _ = allocator.detectLeaks();
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

    var parsing_error: ParsingError = undefined;
    var definitions = try parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        type_examples.list_union,
        &parsing_error,
    );

    expectEqualDefinitions(&expected_definitions, definitions.definitions);

    definitions.deinit();
    _ = allocator.detectLeaks();
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

    var parsing_error: ParsingError = undefined;
    var definitions = try parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        definition_buffer,
        &parsing_error,
    );

    expectEqualDefinitions(&expected_definitions, definitions.definitions);

    definitions.deinit();
    _ = allocator.detectLeaks();
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

    var parsing_error: ParsingError = undefined;
    var definitions = try parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        definition_buffer,
        &parsing_error,
    );

    expectEqualDefinitions(&expected_definitions, definitions.definitions);

    definitions.deinit();
    _ = allocator.detectLeaks();
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

    var parsing_error: ParsingError = undefined;
    var definitions = try parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        definition_buffer,
        &parsing_error,
    );

    expectEqualDefinitions(&expected_definitions, definitions.definitions);

    definitions.deinit();
    _ = allocator.detectLeaks();
}

test "Parsing unions with options" {
    var allocator = TestingAllocator{};

    const definition_buffer =
        \\union(tag = kind) WithModifiedTag {
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
    };

    var parsing_error: ParsingError = undefined;
    var definitions = try parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        definition_buffer,
        &parsing_error,
    );

    expectEqualDefinitions(&expected_definitions, definitions.definitions);

    definitions.deinit();
    _ = allocator.detectLeaks();
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
    var definitions = parse(
        &allocator.allocator,
        &allocator.allocator,
        definition_buffer,
        &parsing_error,
    );

    testing.expectError(error.UnknownReference, definitions);
    switch (parsing_error) {
        .reference => |reference| switch (reference) {
            .unknown_reference => |unknown_reference| {
                testing.expectEqual(unknown_reference.line, 6);
                testing.expectEqual(unknown_reference.column, 14);
                testing.expectEqualStrings(unknown_reference.name, "One");
            },

            .invalid_payload_type => unreachable,
        },
        .expect => unreachable,
    }
}

test "Parsing invalid normal structure" {
    var allocator = TestingAllocator{};
    var parsing_error: ParsingError = undefined;
    const definitions = parse(
        &allocator.allocator,
        &allocator.allocator,
        "struct Container T{",
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

test "Parsing multiple definitions works as it should" {
    var allocator = TestingAllocator{};
    var parsing_error: ParsingError = undefined;

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

    var definitions = try parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        type_examples.person_structure_and_event_union,
        &parsing_error,
    );

    expectEqualDefinitions(&expected_definitions, definitions.definitions);

    definitions.deinit();
    _ = allocator.detectLeaks();
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
        .{ .name = "field1", .@"type" = Type{ .name = "String" } },
    };
    var expected_struct_two_fields = [_]Field{
        .{ .name = "field2", .@"type" = Type{ .name = "F32" } },
    };

    const expected_struct_one = Structure{
        .plain = PlainStructure{
            .name = "One",
            .fields = &expected_struct_one_fields,
        },
    };
    const expected_struct_two = Structure{
        .plain = PlainStructure{
            .name = "Two",
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
                    .name = "Embedded",
                    .constructors = &expected_constructors,
                    .tag_field = "media_type",
                    .open_names = &[_][]u8{},
                },
            },
        },
    };

    var definitions = try parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        definition_buffer,
        &parsing_error,
    );

    expectEqualDefinitions(&expected_definitions, definitions.definitions);

    definitions.deinit();
    _ = allocator.detectLeaks();
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
                        .embedded => |embedded| {
                            if (!mem.eql(u8, embedded.name, b.@"union".embedded.name)) {
                                debug.print(
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
