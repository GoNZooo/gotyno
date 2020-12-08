const std = @import("std");
const debug = std.debug;
const mem = std.mem;
const heap = std.heap;
const testing = std.testing;
const fmt = std.fmt;
const process = std.process;
const io = std.io;
const fs = std.fs;
const meta = std.meta;

const type_examples = @import("./type_examples.zig");
const testing_utilities = @import("./testing_utilities.zig");

const ArrayList = std.ArrayList;

const TestingAllocator = heap.GeneralPurposeAllocator(.{});

pub const TokenTag = @TagType(Token);

pub const Token = union(enum) {
    const Self = @This();

    left_brace,
    right_brace,
    left_bracket,
    right_bracket,
    left_angle,
    right_angle,
    semicolon,
    comma,
    colon,
    newline,
    space,
    question_mark,
    asterisk,
    name: []const u8,
    symbol: []const u8,
    unsigned_integer: usize,
    string: []const u8,

    pub fn isEqual(self: Self, t: Self) bool {
        return switch (self) {
            // for these we only really need to check that the tag matches
            .left_brace,
            .right_brace,
            .left_bracket,
            .right_bracket,
            .left_angle,
            .right_angle,
            .semicolon,
            .comma,
            .colon,
            .newline,
            .space,
            .question_mark,
            .asterisk,
            => meta.activeTag(self) == meta.activeTag(t),

            // keywords/symbols have to also match
            .symbol => |s| meta.activeTag(t) == .symbol and isEqualString(s, t.symbol),
            .name => |s| meta.activeTag(t) == .name and
                isEqualString(s, t.name),
            .unsigned_integer => |n| meta.activeTag(t) == .unsigned_integer and
                n == t.unsigned_integer,
            .string => |s| meta.activeTag(t) == .string and mem.eql(u8, s, t.string),
        };
    }

    pub fn size(self: Self) usize {
        return switch (self) {
            // one-character tokens
            .left_brace,
            .right_brace,
            .left_bracket,
            .right_bracket,
            .left_angle,
            .right_angle,
            .semicolon,
            .colon,
            .comma,
            .newline,
            // @TODO: add CRLF/\r\n token?
            .space,
            .question_mark,
            .asterisk,
            => 1,

            .symbol => |s| s.len,
            .name => |n| n.len,
            // +2 because of the quotes
            .string => |s| s.len + 2,
            .unsigned_integer => |n| size: {
                var remainder: usize = n;
                var digits: usize = 1;
                while (remainder > 10) : (remainder = @mod(remainder, 10)) {
                    digits += 1;
                }

                break :size digits;
            },
        };
    }
};

pub const TokenizeOptions = struct {
    print: bool = false,
};

pub fn tokenize(
    allocator: *mem.Allocator,
    error_allocator: *mem.Allocator,
    buffer: []const u8,
    options: TokenizeOptions,
) !ArrayList(Token) {
    var tokens = ArrayList(Token).init(allocator);
    var token_iterator = TokenIterator.init(buffer);
    var token_index: usize = 0;
    var last_token: Token = Token.space;

    while (try token_iterator.next(.{})) |token| {
        try tokens.append(token);
        if (options.print) debug.print("token {}: {}\n", .{ token_index, token });
        token_index += 1;
        last_token = token;
    }

    return tokens;
}

pub const ExpectTokenError = struct {
    expectation: TokenTag,
    got: Token,
    line: usize,
    column: usize,
};

pub const ExpectOneOfError = struct {
    expectations: []const TokenTag,
    got: Token,
    line: usize,
    column: usize,
};

pub const ExpectError = union(enum) {
    token: ExpectTokenError,
    one_of: ExpectOneOfError,
};

pub const TokenIterator = struct {
    const Self = @This();
    const delimiters = ";:\" \t\n{}[]<>,";

    buffer: []const u8,
    i: usize,
    line: usize,
    column: usize,

    pub const NextOptions = struct {
        peek: bool = false,
    };

    pub fn init(buffer: []const u8) Self {
        return Self{
            .buffer = buffer,
            .i = 0,
            .line = 0,
            .column = 0,
        };
    }

    pub fn next(self: *Self, options: NextOptions) !?Token {
        if (self.i >= self.buffer.len) return null;

        const c = self.buffer[self.i];
        const token = switch (c) {
            '{' => Token.left_brace,
            '}' => Token.right_brace,
            '[' => Token.left_bracket,
            ']' => Token.right_bracket,
            '<' => Token.left_angle,
            '>' => Token.right_angle,
            ';' => Token.semicolon,
            ',' => Token.comma,
            ':' => Token.colon,
            '?' => Token.question_mark,
            '*' => Token.asterisk,
            ' ' => Token.space,
            '\n' => token: {
                if (!options.peek) self.line += 1;
                break :token Token.newline;
            },

            'A'...'Z' => token: {
                if (mem.indexOfAny(u8, self.buffer[self.i..], delimiters)) |delimiter_index| {
                    const name_end = self.i + delimiter_index;
                    break :token Token{ .name = self.buffer[self.i..name_end] };
                } else {
                    @panic("unexpected endless pascal symbol");
                }
            },

            'a'...'z' => token: {
                if (mem.indexOfAny(u8, self.buffer[self.i..], delimiters)) |delimiter_index| {
                    const symbol_end = self.i + delimiter_index;
                    break :token Token{ .symbol = self.buffer[self.i..symbol_end] };
                } else {
                    @panic("unexpected endless pascal symbol");
                }
            },

            '0'...'9' => token: {
                if (mem.indexOfAny(u8, self.buffer[self.i..], delimiters)) |delimiter_index| {
                    const unsigned_integer_end = self.i + delimiter_index;
                    const unsigned_integer = try fmt.parseInt(
                        usize,
                        self.buffer[self.i..unsigned_integer_end],
                        10,
                    );
                    break :token Token{ .unsigned_integer = unsigned_integer };
                } else {
                    @panic("unexpected endless pascal symbol");
                }
            },

            '"' => token: {
                const string_start = self.i + 1;
                if (mem.indexOf(u8, self.buffer[string_start..], "\"")) |quote_index| {
                    const string_end = string_start + quote_index;
                    break :token Token{ .string = self.buffer[string_start..string_end] };
                } else {
                    @panic("unexpected endless string");
                }
            },
            else => debug.panic("unknown token at {}:{}: {c}\n", .{ self.line, self.column, c }),
        };

        if (!options.peek) {
            self.i += token.size();
            self.column = if (meta.activeTag(token) != Token.newline) self.column + token.size() else 0;
        }

        return token;
    }

    pub fn expect(self: *Self, expected_token: TokenTag, expect_error: *ExpectError) !Token {
        const token = try self.next(.{});

        if (token) |t| {
            if (meta.activeTag(t) == expected_token) return t;

            expect_error.* = ExpectError{
                .token = .{
                    .expectation = expected_token,
                    .got = t,
                    .line = self.line,
                    .column = self.column,
                },
            };

            return error.UnexpectedToken;
        } else {
            return error.UnexpectedEndOfTokenStream;
        }
    }

    pub fn expectOneOf(
        self: *Self,
        comptime token_tags: []const TokenTag,
        expect_error: *ExpectError,
    ) !Token {
        debug.assert(token_tags.len > 0);

        if (try self.next(.{})) |token| {
            for (token_tags) |t| {
                if (meta.activeTag(token) == t) return token;
            }

            expect_error.* = ExpectError{
                .one_of = .{
                    .expectations = token_tags,
                    .got = token,
                    .line = self.line,
                    .column = self.column,
                },
            };
            return error.UnexpectedToken;
        } else {
            return error.UnexpectedEndOfTokenStream;
        }
    }

    pub fn skipMany(
        self: *Self,
        token_type: TokenTag,
        n: usize,
        expect_error: *ExpectError,
    ) !void {
        var i: usize = 0;
        while (i < n) : (i += 1) {
            _ = try self.expect(token_type, expect_error);
        }
    }

    pub fn peek(self: *Self) !?Token {
        return try self.next(.{ .peek = true });
    }
};

fn isKeyword(token: []const u8) bool {
    return isEqualString(token, "struct");
}

fn isEqualString(a: []const u8, b: []const u8) bool {
    return mem.eql(u8, a, b);
}

test "Tokenize `Person` struct" {
    var allocator = TestingAllocator{};
    const tokens = try tokenize(
        &allocator.allocator,
        &allocator.allocator,
        type_examples.person_structure,
        .{},
    );
    expectEqualTokenSlices(&expected_person_struct_tokens, tokens.items);
}

test "`expect` for `Person` struct" {
    var allocator = TestingAllocator{};
    try testTokenIteratorExpect(
        &allocator.allocator,
        type_examples.person_structure,
        &expected_person_struct_tokens,
    );
}

test "Tokenize `Maybe` union" {
    var allocator = TestingAllocator{};
    const tokens = try tokenize(
        &allocator.allocator,
        &allocator.allocator,
        type_examples.maybe_union,
        .{},
    );
    expectEqualTokenSlices(&expected_maybe_union_tokens, tokens.items);
}

test "`expect` for `Maybe` union" {
    var allocator = TestingAllocator{};
    try testTokenIteratorExpect(
        &allocator.allocator,
        type_examples.maybe_union,
        &expected_maybe_union_tokens,
    );
}

test "Tokenize `Either` union" {
    var allocator = TestingAllocator{};
    const tokens = try tokenize(
        &allocator.allocator,
        &allocator.allocator,
        type_examples.either_union,
        .{},
    );
    expectEqualTokenSlices(&expected_either_union_tokens, tokens.items);
}

test "`expect` for `Either` union" {
    var allocator = TestingAllocator{};
    try testTokenIteratorExpect(
        &allocator.allocator,
        type_examples.either_union,
        &expected_either_union_tokens,
    );
}

test "Tokenize `List` union" {
    var allocator = TestingAllocator{};
    const tokens = try tokenize(
        &allocator.allocator,
        &allocator.allocator,
        type_examples.list_union,
        .{},
    );
    expectEqualTokenSlices(&expected_list_union_tokens, tokens.items);
}

test "`expect` for `List` union" {
    var allocator = TestingAllocator{};
    try testTokenIteratorExpect(
        &allocator.allocator,
        type_examples.list_union,
        &expected_list_union_tokens,
    );
}

const expected_person_struct_tokens = [_]Token{
    .{ .symbol = "struct" },
    Token.space,
    .{ .name = "Person" },
    Token.space,
    Token.left_brace,
    Token.newline,
    Token.space,
    Token.space,
    Token.space,
    Token.space,
    .{ .symbol = "name" },
    Token.colon,
    Token.space,
    .{ .name = "String" },
    Token.semicolon,
    Token.newline,
    Token.space,
    Token.space,
    Token.space,
    Token.space,
    .{ .symbol = "age" },
    Token.colon,
    Token.space,
    .{ .name = "U8" },
    Token.semicolon,
    Token.newline,
    Token.space,
    Token.space,
    Token.space,
    Token.space,
    .{ .symbol = "efficiency" },
    Token.colon,
    Token.space,
    .{ .name = "F32" },
    Token.semicolon,
    Token.newline,
    Token.space,
    Token.space,
    Token.space,
    Token.space,
    .{ .symbol = "on_vacation" },
    Token.colon,
    Token.space,
    .{ .name = "Boolean" },
    Token.semicolon,
    Token.newline,
    Token.space,
    Token.space,
    Token.space,
    Token.space,
    .{ .symbol = "hobbies" },
    Token.colon,
    Token.space,
    Token.left_bracket,
    Token.right_bracket,
    .{ .name = "String" },
    Token.semicolon,
    Token.newline,
    Token.space,
    Token.space,
    Token.space,
    Token.space,
    .{ .symbol = "last_fifteen_comments" },
    Token.colon,
    Token.space,
    Token.left_bracket,
    .{ .unsigned_integer = 15 },
    Token.right_bracket,
    .{ .name = "String" },
    Token.semicolon,
    Token.newline,
    Token.space,
    Token.space,
    Token.space,
    Token.space,
    .{ .symbol = "recruiter" },
    Token.colon,
    Token.space,
    Token.asterisk,
    .{ .name = "Person" },
    Token.semicolon,
    Token.newline,
    Token.right_brace,
};

const expected_maybe_union_tokens = [_]Token{
    .{ .symbol = "union" },
    Token.space,
    .{ .name = "Maybe" },
    Token.space,
    Token.left_angle,
    .{ .name = "T" },
    Token.right_angle,
    Token.left_brace,
    Token.newline,
    Token.space,
    Token.space,
    Token.space,
    Token.space,
    .{ .name = "Just" },
    Token.colon,
    Token.space,
    .{ .name = "T" },
    Token.semicolon,
    Token.newline,
    Token.space,
    Token.space,
    Token.space,
    Token.space,
    .{ .name = "Nothing" },
    Token.semicolon,
    Token.newline,
    Token.right_brace,
};

const expected_either_union_tokens = [_]Token{
    .{ .symbol = "union" },
    Token.space,
    .{ .name = "Either" },
    Token.space,
    Token.left_angle,
    .{ .name = "E" },
    Token.comma,
    Token.space,
    .{ .name = "T" },
    Token.right_angle,
    Token.left_brace,
    Token.newline,
    Token.space,
    Token.space,
    Token.space,
    Token.space,
    .{ .name = "Left" },
    Token.colon,
    Token.space,
    .{ .name = "E" },
    Token.semicolon,
    Token.newline,
    Token.space,
    Token.space,
    Token.space,
    Token.space,
    .{ .name = "Right" },
    Token.colon,
    Token.space,
    .{ .name = "T" },
    Token.semicolon,
    Token.newline,
    Token.right_brace,
};

const expected_list_union_tokens = [_]Token{
    .{ .symbol = "union" },
    Token.space,
    .{ .name = "List" },
    Token.space,
    Token.left_angle,
    .{ .name = "T" },
    Token.right_angle,
    Token.left_brace,
    Token.newline,
    Token.space,
    Token.space,
    Token.space,
    Token.space,
    .{ .name = "Empty" },
    Token.semicolon,
    Token.newline,
    Token.space,
    Token.space,
    Token.space,
    Token.space,
    .{ .name = "Cons" },
    Token.colon,
    Token.space,
    Token.asterisk,
    .{ .name = "List" },
    Token.left_angle,
    .{ .name = "T" },
    Token.right_angle,
    Token.semicolon,
    Token.newline,
    Token.right_brace,
};

fn expectEqualTokenSlices(a: []const Token, b: []const Token) void {
    if (indexOfDifferentToken(a, b)) |different_index| {
        testing_utilities.testPanic(
            "Index {} different between token slices:\n\tExpected: {}\n\tGot: {}\n",
            .{ different_index, a[different_index], b[different_index] },
        );
    } else if (a.len != b.len) {
        testing_utilities.testPanic(
            "Slices are of different lengths:\n\tExpected: {}\n\tGot: {}\n",
            .{ a.len, b.len },
        );
    }
}

fn testTokenIteratorExpect(
    allocator: *mem.Allocator,
    buffer: []const u8,
    expected_tokens: []const Token,
) !void {
    var token_iterator = TokenIterator.init(buffer);
    var expect_error: ExpectError = undefined;
    for (expected_tokens) |expected_token| {
        _ = try token_iterator.expect(expected_token, &expect_error);
    }
}

fn indexOfDifferentToken(a: []const Token, b: []const Token) ?usize {
    for (a) |t, i| {
        if (!t.isEqual(b[i])) return i;
    }

    return null;
}
