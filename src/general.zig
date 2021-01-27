const std = @import("std");
const mem = std.mem;
const parser = @import("./freeform/parser.zig");

const Type = parser.Type;
const Definition = parser.Definition;
const AppliedOpenName = parser.AppliedOpenName;

const ArrayList = std.ArrayList;

pub fn openNamesFromType(
    allocator: *mem.Allocator,
    t: Type,
    open_names: []const []const u8,
) error{OutOfMemory}!ArrayList([]const u8) {
    return switch (t) {
        .pointer => |p| try openNamesFromType(allocator, p.@"type".*, open_names),
        .array => |a| try openNamesFromType(allocator, a.@"type".*, open_names),
        .slice => |s| try openNamesFromType(allocator, s.@"type".*, open_names),
        .optional => |o| try openNamesFromType(allocator, o.@"type".*, open_names),

        .reference => |r| reference: {
            var open_name_list = ArrayList([]const u8).init(allocator);

            switch (r) {
                .builtin => {},
                .imported_definition => |id| try open_name_list.appendSlice(
                    try openNamesFromDefinition(allocator, id.definition),
                ),
                .applied_name => |applied| break :reference try commonOpenNames(
                    allocator,
                    open_names,
                    applied.open_names,
                ),

                .definition => |d| try open_name_list.appendSlice(
                    try openNamesFromDefinition(allocator, d),
                ),
                .loose => |l| try open_name_list.appendSlice(
                    try allocator.dupe([]const u8, l.open_names),
                ),
                .open => |n| try open_name_list.append(try allocator.dupe(u8, n)),
            }

            break :reference open_name_list;
        },

        .string, .empty => ArrayList([]const u8).init(allocator),
    };
}

fn openNamesFromDefinition(
    allocator: *mem.Allocator,
    d: Definition,
) ![]const []const u8 {
    return switch (d) {
        .structure => |s| switch (s) {
            .generic => |g| g.open_names,
            .plain => &[_][]const u8{},
        },
        .@"union" => |u| switch (u) {
            .generic => |g| g.open_names,
            .plain, .embedded => &[_][]const u8{},
        },
        .untagged_union, .import, .enumeration => &[_][]const u8{},
    };
}

pub fn commonOpenNames(
    allocator: *mem.Allocator,
    as: []const []const u8,
    applied_open_names: []const AppliedOpenName,
) !ArrayList([]const u8) {
    var common_names = ArrayList([]const u8).init(allocator);

    for (as) |a| {
        for (applied_open_names) |applied_open_name| {
            switch (applied_open_name) {
                .open => |o| if (mem.eql(u8, a, o) and !isTranslatedName(a)) {
                    try common_names.append(try allocator.dupe(u8, a));
                },
                .reference => {},
            }
        }
    }

    return common_names;
}

pub fn isNumberType(name: []const u8) bool {
    return isStringEqualToOneOf(name, &[_][]const u8{
        "U8",
        "U16",
        "U32",
        "U64",
        "U128",
        "I8",
        "I16",
        "I32",
        "I64",
        "I128",
        "F32",
        "F64",
        "F128",
    });
}

pub fn isTranslatedName(name: []const u8) bool {
    return isNumberType(name) or
        isStringEqualToOneOf(name, &[_][]const u8{ "String", "Boolean" });
}

pub fn isStringEqualToOneOf(value: []const u8, compared_values: []const []const u8) bool {
    for (compared_values) |compared_value| {
        if (mem.eql(u8, value, compared_value)) return true;
    }

    return false;
}
