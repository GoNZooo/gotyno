const std = @import("std");
const debug = std.debug;
const mem = std.mem;
const heap = std.heap;
const testing = std.testing;
const fmt = std.fmt;
const process = std.process;
const io = std.io;
const fs = std.fs;

const ArrayList = std.ArrayList;

pub const Location = struct {
    const Self = @This();

    filename: []const u8,
    line: usize,
    column: usize,

    pub fn isEqual(self: Self, other: Self) bool {
        return self.line == other.line and self.column == other.column and
            mem.eql(u8, self.filename, other.filename);
    }
};

pub fn isStringEqualToOneOf(value: []const u8, compared_values: []const []const u8) bool {
    for (compared_values) |compared_value| {
        if (mem.eql(u8, value, compared_value)) return true;
    }

    return false;
}

pub fn deepCopySlice(
    comptime T: type,
    allocator: mem.Allocator,
    slice: []const []const T,
) ![]const []const T {
    const ts = try allocator.alloc([]T, slice.len);

    for (ts, 0..) |*t, i| t.* = try allocator.dupe(T, slice[i]);

    return ts;
}

pub fn freeStringList(strings: ArrayList([]const u8)) void {
    for (strings.items) |s| strings.allocator.free(s);
    strings.deinit();
}

pub fn freeStringArray(allocator: mem.Allocator, strings: []const []const u8) void {
    for (strings) |s| allocator.free(s);
    allocator.free(strings);
}

pub fn titleCaseWord(allocator: mem.Allocator, word: []const u8) ![]const u8 {
    return fmt.allocPrint(allocator, "{c}{s}", .{ std.ascii.toUpper(word[0]), word[1..] });
}

pub fn camelCaseWord(allocator: mem.Allocator, word: []const u8) ![]const u8 {
    return fmt.allocPrint(allocator, "{c}{s}", .{ std.ascii.toLower(word[0]), word[1..] });
}

pub fn withoutExtension(allocator: mem.Allocator, path: []const u8) ![]const u8 {
    return if (mem.lastIndexOf(u8, path, ".")) |index|
        try allocator.dupe(u8, path[0..index])
    else
        try allocator.dupe(u8, path);
}
