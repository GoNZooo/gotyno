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

const ArrayList = std.ArrayList;

const TestingAllocator = heap.GeneralPurposeAllocator(.{});

pub const Token = union(enum) {
    const Self = @This();

    left_brace,
    right_brace,
    left_bracket,
    right_bracket,
    semicolon,
    colon,
    newline,
    space,
    keyword: []const u8,
    name: []const u8,
    symbol: []const u8,
    unsigned_integer: usize,
    string: []const u8,

    pub fn equal(self: Self, t: Self) bool {
        return switch (self) {
            // for these we only really need to check that the tag matches
            .left_brace,
            .right_brace,
            .left_bracket,
            .right_bracket,
            .semicolon,
            .colon,
            .newline,
            .space,
            => meta.activeTag(self) == meta.activeTag(t),

            // keywords/symbols have to also match
            .keyword => |k| meta.activeTag(t) == .keyword and isEqualString(k, t.keyword),
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
            .semicolon,
            .colon,
            .newline,
            .space,
            => 1,

            .keyword => |k| k.len,
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
    collapsed_space_size: ?u32 = 2,
};

pub fn tokenize(
    allocator: *mem.Allocator,
    buffer: []const u8,
    options: TokenizeOptions,
) !ArrayList(Token) {
    var tokens = ArrayList(Token).init(allocator);
    var token_iterator = tokenIterator(buffer);
    var token_index: usize = 0;
    var last_token: Token = Token.space;
    var spaces: u32 = 0;
    const collapse_spaces = options.collapsed_space_size != null;

    while (try token_iterator.next()) |token| {
        if (collapse_spaces and
            spaces >= options.collapsed_space_size.? and
            token == Token.space)
        {
            // skipping token because we currently have several continuous spaces
        } else {
            switch (token) {
                .space => spaces += 1,
                else => spaces = 0,
            }
            try tokens.append(token);
            if (options.print) debug.print("token {}: {}\n", .{ token_index, token });
            token_index += 1;
        }
        last_token = token;
    }

    return tokens;
}

const TokenIterator = struct {
    const Self = @This();
    const delimiters = ";:\" \t\n{}[]";

    buffer: []const u8,
    i: usize,
    line: usize,
    column: usize,

    pub fn next(self: *Self) !?Token {
        if (self.i >= self.buffer.len) return null;

        const c = self.buffer[self.i];
        const token = switch (c) {
            '{' => Token.left_brace,
            '}' => Token.right_brace,
            '[' => Token.left_bracket,
            ']' => Token.right_bracket,
            ';' => Token.semicolon,
            ':' => Token.colon,
            ' ' => Token.space,
            '\n' => token: {
                self.line += 1;
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

        self.i += token.size();
        self.column = if (meta.activeTag(token) != Token.newline) self.column + token.size() else 0;

        return token;
    }
};

fn tokenIterator(buffer: []const u8) TokenIterator {
    return TokenIterator{ .buffer = buffer, .i = 0, .line = 0, .column = 0 };
}

fn isKeyword(token: []const u8) bool {
    return isEqualString(token, "struct");
}

fn isEqualString(a: []const u8, b: []const u8) bool {
    return mem.eql(u8, a, b);
}

test "`tokenize`" {
    var allocator = TestingAllocator{};
    const tokens = try tokenize(&allocator.allocator, person_example, .{ .print = true });
    expectEqualTokenSlices(&expected_person_struct_tokens, tokens.items);
}

// @TODO: make this  token array match expected output for the `Person` example
const expected_person_struct_tokens = [_]Token{.{ .keyword = "struct" }};

const person_example =
    \\struct Person {
    \\    type: "Person";
    \\    name: String;
    \\    age: U8;
    \\    efficiency: F32;
    \\    on_vacation: Boolean;
    \\    last_five_comments: [11]String;
    \\}
;

fn expectEqualTokenSlices(a: []const Token, b: []const Token) void {
    if (a.len != b.len) {
        testPanic("Differing token slice lengths: {} != {}\n", .{ a.len, b.len });
    } else if (indexOfDifferentToken(a, b)) |different_index| {
        testPanic(
            "Index {} different between token slices:\n\tExpected: {}\n\tGot: {}\n",
            .{ different_index, a[different_index], b[different_index] },
        );
    }
}

fn indexOfDifferentToken(a: []const Token, b: []const Token) ?usize {
    for (a) |t, i| {
        if (!t.equal(b[i])) return i;
    }

    return null;
}

fn testPanic(comptime format: []const u8, arguments: anytype) noreturn {
    debug.print(format, arguments);

    @panic("test failure");
}
