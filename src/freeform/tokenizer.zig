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
    quotation_mark,
    semicolon,
    keyword: []const u8,

    pub fn equal(self: Self, t: Self) bool {
        return switch (self) {
            .left_brace,
            .right_brace,
            .quotation_mark,
            .semicolon,
            => meta.activeTag(self) == meta.activeTag(t),
            .keyword => |k| meta.activeTag(t) == .keyword and isEqualString(k, t.keyword),
        };
    }
};

pub fn tokenize(allocator: *mem.Allocator, buffer: []const u8) !ArrayList(Token) {
    var tokens = ArrayList(Token).init(allocator);
    var token_iterator = mem.tokenize(buffer, " ");
    while (token_iterator.next()) |token| {
        if (isKeyword(token)) {
            try tokens.append(Token{ .keyword = token });
        }
        debug.print("token: {}\n", .{token});
    }

    return tokens;
}

fn isKeyword(token: []const u8) bool {
    return isEqualString(token, "struct");
}

fn isEqualString(a: []const u8, b: []const u8) bool {
    return mem.eql(u8, a, b);
}

test "`tokenize`" {
    var allocator = TestingAllocator{};
    const tokens = try tokenize(&allocator.allocator, person_example);
    const expected_tokens = [_]Token{.{ .keyword = "struct" }};
    testing.expect(tokens.items[0].equal(expected_tokens[0]));
}

const person_example =
    \\struct Person {
    \\    type: "Person";
    \\    name: string;
    \\    age: u8;
    \\    efficiency: f32;
    \\    on_vacation: boolean;
    \\    last_five_comments: [5]string;
    \\}
;
