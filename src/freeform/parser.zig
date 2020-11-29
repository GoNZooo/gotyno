const std = @import("std");
const debug = std.debug;
const mem = std.mem;
const heap = std.heap;
const testing = std.testing;
const fmt = std.fmt;

const type_examples = @import("./type_examples.zig");

pub const Definition = union(enum) {
    structure: Structure,
    @"union": Union,
};

pub const Structure = union(enum) {
    plain_structure: PlainStructure,
    generic_structure: GenericStructure,
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

pub const Union = union(enum) {
    plain_union: PlainUnion,
    generic_union: GenericUnion,
};
