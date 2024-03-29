const std = @import("std");
const debug = std.debug;
const mem = std.mem;
const heap = std.heap;
const testing = std.testing;
const fmt = std.fmt;
const meta = std.meta;

const tokenizer = @import("tokenizer.zig");
const utilities = @import("utilities.zig");

const Token = tokenizer.Token;
const TokenTag = tokenizer.TokenTag;
const ExpectError = tokenizer.ExpectError;
const TokenIterator = tokenizer.TokenIterator;
const ArrayList = std.ArrayList;
const Location = utilities.Location;

pub const ParsingError = union(enum) {
    /// Represents errors from the tokenizer, which involve expectations on what upcoming tokens
    /// should be.
    expect: ExpectError,
    invalid_payload: InvalidPayload,
    unknown_reference: UnknownReference,
    unknown_module: UnknownModule,
    duplicate_definition: DuplicateDefinition,
    applied_name_count: AppliedNameCount,
};

/// Indicates that we've passed the wrong number of type parameters to an applied name.
pub const AppliedNameCount = struct {
    name: []const u8,
    expected: u32,
    actual: u32,
    location: Location,
};

/// Indicates that we are defining a name twice, which is invalid.
pub const DuplicateDefinition = struct {
    definition: Definition,
    existing_definition: Definition,
    location: Location,
    previous_location: Location,
};

/// Indicates that the payload that we are trying to use in an embedded union isn't valid, i.e.
/// it's not a type we can embed the type tag in.
pub const InvalidPayload = struct {
    payload: Definition,
    location: Location,
};

/// Indicates that we've referenced an unknown name, meaning one that hasn't been defined yet.
pub const UnknownReference = struct {
    name: []const u8,
    location: Location,
};

/// Indicates that we've referenced an unknown module, meaning one that hasn't been defined yet.
pub const UnknownModule = struct {
    name: []const u8,
    location: Location,
};

pub const BufferData = struct {
    filename: []const u8,
    buffer: []const u8,
};

pub const DefinitionName = struct {
    const Self = @This();

    value: []const u8,
    location: Location,

    pub fn isEqual(self: Self, other: Self) bool {
        return mem.eql(u8, self.value, other.value) and self.location.isEqual(other.location);
    }

    pub fn format(
        self: Self,
        comptime format_string: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = format_string;
        try fmt.format(
            writer,
            "{s}({}:{})",
            .{ self.value, self.location.line, self.location.column },
        );
    }
};

pub const Definition = union(enum) {
    const Self = @This();

    structure: Structure,
    @"union": Union,
    enumeration: Enumeration,
    untagged_union: UntaggedUnion,
    import: Import,

    pub fn free(self: *Self, allocator: mem.Allocator) void {
        switch (self.*) {
            .structure => |*s| s.free(allocator),
            .@"union" => |*u| u.free(allocator),
            .enumeration => |*e| e.free(allocator),
            .untagged_union => |*u| u.free(allocator),
            .import => |*i| i.free(allocator),
        }
    }

    pub fn openNames(self: Self) []const []const u8 {
        return switch (self) {
            .structure => |s| switch (s) {
                .generic => |g| g.open_names,
                .plain => &[_][]const u8{},
            },
            .@"union" => |u| switch (u) {
                .generic => |g| g.open_names,
                .plain, .embedded => &[_][]const u8{},
            },
            .enumeration, .untagged_union, .import => &[_][]const u8{},
        };
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

    pub fn name(self: Self) DefinitionName {
        return switch (self) {
            .structure => |s| s.name(),
            .@"union" => |u| u.name(),
            .enumeration => |e| e.name,
            .untagged_union => |u| u.name,
            .import => |i| i.name,
        };
    }

    pub fn format(
        self: Self,
        comptime format_string: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = format_string;
        return switch (self) {
            .structure => |s| try fmt.format(writer, "{}", .{s}),
            .@"union" => |u| try fmt.format(writer, "{}", .{u}),
            .enumeration => |e| try fmt.format(writer, "{}", .{e}),
            .untagged_union => |u| try fmt.format(writer, "{}", .{u}),
            .import => |i| try fmt.format(writer, "{}", .{i}),
        };
    }
};

pub const ImportedDefinition = struct {
    const Self = @This();

    import_name: []const u8,
    definition: Definition,

    pub fn format(
        self: Self,
        comptime format_string: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = format_string;
        try fmt.format(writer, "{s}.{}", .{ self.import_name, self.definition });
    }
};

pub const Import = struct {
    const Self = @This();

    name: DefinitionName,
    alias: []const u8,

    pub fn free(self: Self, allocator: mem.Allocator) void {
        // Check if the alias is the same string as the value, in which case we free one instance
        if (self.name.value.ptr == self.alias.ptr) {
            allocator.free(self.name.value);
        } else {
            allocator.free(self.name.value);
            allocator.free(self.alias);
        }
    }

    pub fn isEqual(self: Self, other: Self) bool {
        return self.name.isEqual(other.name) and mem.eql(u8, self.alias, other.alias);
    }
};

pub const UntaggedUnion = struct {
    const Self = @This();

    name: DefinitionName,
    values: []const UntaggedUnionValue,

    pub fn free(self: Self, allocator: mem.Allocator) void {
        allocator.free(self.name.value);
        for (self.values) |*value| value.free(allocator);
        allocator.free(self.values);
    }

    pub fn isEqual(self: Self, other: Self) bool {
        if (!self.name.isEqual(other.name)) return false;

        if (self.values.len != other.values.len) return false;

        for (self.values, 0..) |value, i| {
            if (!value.isEqual(other.values[i])) return false;
        }

        return true;
    }
};

pub const UntaggedUnionValue = union(enum) {
    const Self = @This();

    reference: TypeReference,

    pub fn toString(self: Self, allocator: mem.Allocator) ![]const u8 {
        return try self.reference.toString(allocator);
    }

    pub fn free(self: Self, allocator: mem.Allocator) void {
        self.reference.free(allocator);
    }

    pub fn isEqual(self: Self, other: Self) bool {
        return switch (self) {
            .reference => |r| meta.activeTag(other) == .reference and r.isEqual(other.reference),
        };
    }
};

pub const Enumeration = struct {
    const Self = @This();

    name: DefinitionName,
    fields: []const EnumerationField,

    pub fn free(self: *Self, allocator: mem.Allocator) void {
        allocator.free(self.name.value);
        for (self.fields) |*field| field.free(allocator);
        allocator.free(self.fields);
    }

    pub fn isEqual(self: Self, other: Self) bool {
        if (!self.name.isEqual(other.name)) return false;

        if (self.fields.len != other.fields.len) return false;

        for (self.fields, 0..) |field, i| {
            if (!field.isEqual(other.fields[i])) return false;
        }

        return true;
    }
};

pub const EnumerationField = struct {
    const Self = @This();

    tag: []const u8,
    value: EnumerationValue,

    pub fn free(self: Self, allocator: mem.Allocator) void {
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

    pub fn toString(self: Self, allocator: mem.Allocator) ![]const u8 {
        return switch (self) {
            .string => |s| try fmt.allocPrint(allocator, "\"{s}\"", .{s}),
            .unsigned_integer => |ui| try fmt.allocPrint(allocator, "{}", .{ui}),
        };
    }

    pub fn free(self: Self, allocator: mem.Allocator) void {
        switch (self) {
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

    pub fn free(self: Self, allocator: mem.Allocator) void {
        switch (self) {
            .plain => |p| p.free(allocator),
            .generic => |g| g.free(allocator),
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

    pub fn name(self: Self) DefinitionName {
        return switch (self) {
            .plain => |plain| plain.name,
            .generic => |generic| generic.name,
        };
    }

    pub fn format(
        self: Self,
        comptime format_string: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = format_string;
        return switch (self) {
            .plain => |p| try fmt.format(writer, "{}", .{p}),
            .generic => |g| try fmt.format(writer, "{}", .{g}),
        };
    }
};

pub const PlainStructure = struct {
    const Self = @This();

    name: DefinitionName,
    fields: []const Field,

    pub fn free(self: Self, allocator: mem.Allocator) void {
        allocator.free(self.name.value);
        for (self.fields) |f| f.free(allocator);
        allocator.free(self.fields);
    }

    pub fn isEqual(self: Self, other: Self) bool {
        if (!self.name.isEqual(other.name))
            return false
        else {
            for (self.fields, 0..) |sf, i| {
                if (!sf.isEqual(other.fields[i])) return false;
            }

            return true;
        }
    }

    pub fn format(
        self: Self,
        comptime format_string: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = format_string;
        try fmt.format(writer, "{}{{ ", .{self.name});
        for (self.fields) |f| {
            try fmt.format(writer, "{}", .{f});
        }
        try fmt.format(writer, " }}", .{});
    }
};

pub const GenericStructure = struct {
    const Self = @This();

    name: DefinitionName,
    fields: []const Field,
    open_names: []const []const u8,

    pub fn free(self: Self, allocator: mem.Allocator) void {
        allocator.free(self.name.value);
        for (self.fields) |f| f.free(allocator);
        allocator.free(self.fields);
        for (self.open_names) |n| allocator.free(n);
        allocator.free(self.open_names);
    }

    pub fn isEqual(self: Self, other: Self) bool {
        if (!self.name.isEqual(other.name))
            return false
        else {
            for (self.open_names, 0..) |name, i| {
                if (!mem.eql(u8, name, other.open_names[i])) return false;
            }

            for (self.fields, 0..) |field, i| {
                if (!field.isEqual(other.fields[i])) return false;
            }

            return true;
        }
    }

    pub fn format(
        self: Self,
        comptime format_string: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = format_string;
        if (self.fields.len > 0) {
            try fmt.format(writer, "{}{{ {}", .{ self.name, self.fields[0] });
            for (self.fields[1..]) |f| {
                try fmt.format(writer, ", {}", .{f});
            }
            try fmt.format(writer, " }}", .{});
        } else {
            try fmt.format(writer, "{}{{ }}", .{self.name});
        }
    }
};

pub const Field = struct {
    const Self = @This();

    name: []const u8,
    type: Type,

    pub fn free(self: Self, allocator: mem.Allocator) void {
        allocator.free(self.name);
        self.type.free(allocator);
    }

    pub fn isEqual(self: Self, other: Self) bool {
        return self.type.isEqual(other.type) and mem.eql(u8, self.name, other.name);
    }

    pub fn format(
        self: Self,
        comptime format_string: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = format_string;
        try fmt.format(writer, "{s}: {}", .{ self.name, self.type });
    }
};

pub const Type = union(enum) {
    const Self = @This();

    empty,
    string: []const u8,
    reference: TypeReference,
    array: Array,
    slice: Slice,
    pointer: Pointer,
    optional: Optional,

    pub fn free(self: Self, allocator: mem.Allocator) void {
        switch (self) {
            .string => |s| allocator.free(s),
            .array => |*a| {
                a.*.type.free(allocator);
                allocator.destroy(a.*.type);
            },
            .slice => |*s| {
                s.*.type.free(allocator);
                allocator.destroy(s.*.type);
            },
            .optional => |*o| {
                o.*.type.free(allocator);
                allocator.destroy(o.*.type);
            },
            .pointer => |*p| {
                p.*.type.free(allocator);
                allocator.destroy(p.*.type);
            },
            .reference => |*r| r.free(allocator),
            .empty => {},
        }
    }

    pub fn isEqual(self: Self, other: Self) bool {
        return switch (self) {
            .empty => meta.activeTag(other) == .empty,
            .string => meta.activeTag(other) == .string and mem.eql(u8, self.string, other.string),
            .reference => |r| meta.activeTag(other) == .reference and
                r.isEqual(other.reference),
            .array => |array| meta.activeTag(other) == .array and array.isEqual(other.array),
            .slice => |slice| meta.activeTag(other) == .slice and slice.isEqual(other.slice),
            .pointer => |pointer| meta.activeTag(other) == .pointer and
                pointer.isEqual(other.pointer),
            .optional => |optional| meta.activeTag(other) == .optional and
                optional.isEqual(other.optional),
        };
    }

    pub fn format(
        self: Self,
        comptime format_string: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = format_string;
        return switch (self) {
            .empty => try fmt.format(writer, ".empty", .{}),
            .reference => |r| fmt.format(writer, "{}", .{r}),
            .string => |s| fmt.format(writer, "{s}", .{s}),
            .array => |array| fmt.format(writer, "[{}]{}", .{ array.size, array.type }),
            .slice => |slice| fmt.format(writer, "[]{}", .{slice.type}),
            .pointer => |pointer| fmt.format(writer, "*{}", .{pointer.type}),
            .optional => |optional| fmt.format(writer, "?{}", .{optional.type}),
        };
    }

    pub fn openNames(self: Self) []const []const u8 {
        return switch (self) {
            .empty => &[_][]const u8{},
            .string => &[_][]const u8{},
            .reference => |r| r.openNames(),
            .array => |array| array.type.openNames(),
            .slice => |slice| slice.type.openNames(),
            .pointer => |pointer| pointer.type.openNames(),
            .optional => |optional| optional.type.openNames(),
        };
    }
};

pub const TypeReference = union(enum) {
    const Self = @This();

    builtin: Builtin,
    definition: Definition,
    imported_definition: ImportedDefinition,
    loose: LooseReference,
    open: []const u8,
    applied_name: AppliedName,

    pub fn toString(self: Self, allocator: mem.Allocator) ![]const u8 {
        return switch (self) {
            .builtin => |b| try allocator.dupe(u8, b.toString()),
            .definition => |d| try allocator.dupe(u8, d.name().value),
            .imported_definition => |id| try fmt.allocPrint(
                allocator,
                "{s}.{s}",
                .{ id.import_name, id.definition.name().value },
            ),
            .applied_name => |a| try allocator.dupe(u8, a.reference.name()),
            .loose => |l| try allocator.dupe(u8, l.name),
            .open => |o| try allocator.dupe(u8, o),
        };
    }

    pub fn openNames(self: Self) []const []const u8 {
        return switch (self) {
            .builtin => &[_][]const u8{},
            .loose => |l| l.open_names,
            .definition => |d| d.openNames(),
            .imported_definition => |id| id.definition.openNames(),
            .applied_name => |a| a.reference.openNames(),
            .open => |n| &[_][]const u8{n},
        };
    }

    pub fn free(self: Self, allocator: mem.Allocator) void {
        switch (self) {
            .loose => |*l| l.free(allocator),
            .open => |n| allocator.free(n),
            .applied_name => |*a| {
                a.reference.free(allocator);
                allocator.destroy(a.reference);

                for (a.open_names) |n| {
                    n.free(allocator);
                }
                allocator.free(a.open_names);
            },
            .builtin, .imported_definition, .definition => {},
        }
    }

    pub fn isEqual(self: Self, other: Self) bool {
        return switch (self) {
            .builtin => |b| meta.activeTag(other) == .builtin and b == other.builtin,
            .loose => |l| meta.activeTag(other) == .loose and l.isEqual(other.loose),
            .definition => |d| meta.activeTag(other) == .definition and d.isEqual(other.definition),
            .imported_definition => |id| meta.activeTag(other) == .imported_definition and
                mem.eql(
                u8,
                id.import_name,
                other.imported_definition.import_name,
            ) and
                id.definition.isEqual(other.imported_definition.definition),
            .applied_name => |a| meta.activeTag(other) == .applied_name and
                a.isEqual(other.applied_name),
            .open => |n| meta.activeTag(other) == .open and mem.eql(u8, n, other.open),
        };
    }

    pub fn name(self: Self) []const u8 {
        return switch (self) {
            .builtin => |b| b.toString(),
            .definition => |d| d.name().value,
            .imported_definition => |id| id.definition.name().value,
            .applied_name => |a| a.reference.name(),
            .loose => |l| l.name,
            .open => |n| n,
        };
    }

    pub fn format(
        self: Self,
        comptime format_string: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = format_string;
        return switch (self) {
            .builtin => |b| try fmt.format(writer, "{s}", .{b.toString()}),
            .definition => |d| try fmt.format(writer, "{}", .{d}),
            .imported_definition => |id| fmt.format(writer, "{}", .{id}),
            .applied_name => |a| try fmt.format(writer, "{}", .{a}),
            .loose => |l| try fmt.format(writer, "{}", .{l}),
            .open => |o| try fmt.format(writer, "{s}", .{o}),
        };
    }
};

pub const Builtin = enum {
    const Self = @This();

    String,
    Boolean,
    U8,
    U16,
    U32,
    U64,
    U128,
    I8,
    I16,
    I32,
    I64,
    I128,
    F32,
    F64,
    F128,

    pub fn toString(self: Self) []const u8 {
        return switch (self) {
            .String => "String",
            .Boolean => "Boolean",
            .U8 => "U8",
            .U16 => "U16",
            .U32 => "U32",
            .U64 => "U64",
            .U128 => "U128",
            .I8 => "I8",
            .I16 => "I16",
            .I32 => "I32",
            .I64 => "I64",
            .I128 => "I128",
            .F32 => "F32",
            .F64 => "F64",
            .F128 => "F128",
        };
    }

    /// This is partial; use after checking with `isBuiltin`
    pub fn fromString(string: []const u8) Builtin {
        return if (mem.eql(u8, string, "String"))
            Builtin.String
        else if (mem.eql(u8, string, "Boolean"))
            Builtin.Boolean
        else if (mem.eql(u8, string, "U8"))
            Builtin.U8
        else if (mem.eql(u8, string, "U16"))
            Builtin.U16
        else if (mem.eql(u8, string, "U32"))
            Builtin.U32
        else if (mem.eql(u8, string, "U64"))
            Builtin.U64
        else if (mem.eql(u8, string, "U128"))
            Builtin.U128
        else if (mem.eql(u8, string, "I8"))
            Builtin.I8
        else if (mem.eql(u8, string, "I16"))
            Builtin.I16
        else if (mem.eql(u8, string, "I32"))
            Builtin.I32
        else if (mem.eql(u8, string, "I64"))
            Builtin.I64
        else if (mem.eql(u8, string, "I128"))
            Builtin.I128
        else if (mem.eql(u8, string, "F32"))
            Builtin.F32
        else if (mem.eql(u8, string, "F64"))
            Builtin.F64
        else if (mem.eql(u8, string, "F128"))
            Builtin.F128
        else
            debug.panic("Invalid builtin referenced; check with `isBuiltin`", .{});
    }
};

pub const LooseReference = struct {
    const Self = @This();

    name: []const u8,
    open_names: []const []const u8,

    pub fn free(self: Self, allocator: mem.Allocator) void {
        allocator.free(self.name);
        for (self.open_names) |n| allocator.free(n);
        allocator.free(self.open_names);
    }

    pub fn isEqual(self: Self, other: Self) bool {
        if (!mem.eql(u8, self.name, other.name)) return false;

        for (self.open_names, 0..) |name, i| {
            if (!mem.eql(u8, name, other.open_names[i])) return false;
        }

        return true;
    }

    pub fn format(
        self: Self,
        comptime format_string: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = format_string;
        if (self.open_names.len > 0) {
            try fmt.format(writer, "(LOOSE){s}(<{s}", .{ self.name, self.open_names[0] });

            for (self.open_names[1..]) |n| {
                try fmt.format(writer, ", {s}", .{n});
            }

            try fmt.format(writer, ">)", .{});
        } else {
            try fmt.format(writer, "(LOOSE){s}(<>)", .{self.name});
        }
    }
};

pub const Array = struct {
    const Self = @This();

    size: usize,
    type: *Type,

    pub fn isEqual(self: Self, other: Self) bool {
        return self.size == other.size and self.type.isEqual(other.type.*);
    }
};

pub const Slice = struct {
    const Self = @This();

    type: *Type,

    pub fn isEqual(self: Self, other: Self) bool {
        return self.type.isEqual(other.type.*);
    }
};

pub const Pointer = struct {
    const Self = @This();

    type: *Type,

    pub fn isEqual(self: Self, other: Self) bool {
        return self.type.isEqual(other.type.*);
    }
};

pub const Optional = struct {
    const Self = @This();

    type: *Type,

    pub fn isEqual(self: Self, other: Self) bool {
        return self.type.isEqual(other.type.*);
    }
};

pub const AppliedName = struct {
    const Self = @This();

    reference: *TypeReference,
    open_names: []const AppliedOpenName,

    pub fn isEqual(self: Self, other: Self) bool {
        if (!self.reference.isEqual(other.reference.*)) return false;

        if (self.open_names.len != other.open_names.len) return false;

        for (self.open_names, 0..) |open_name, i| {
            const result = open_name.isEqual(other.open_names[i]);

            if (!result) return false;
        }

        return true;
    }

    pub fn format(
        self: Self,
        comptime format_string: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = format_string;
        if (self.open_names.len > 0) {
            try fmt.format(writer, "{}<{}>", .{ self.reference, self.open_names[0] });
            for (self.open_names[1..]) |n| {
                try fmt.format(writer, ", {}", .{n});
            }
        } else {
            try fmt.format(writer, "{}<>", .{self.reference});
        }
    }
};

pub const AppliedOpenName = struct {
    const Self = @This();

    reference: Type,

    pub fn free(self: Self, allocator: mem.Allocator) void {
        self.reference.free(allocator);
    }

    pub fn isEqual(self: Self, other: Self) bool {
        return self.reference.isEqual(other.reference);
    }

    pub fn format(
        self: Self,
        comptime format_string: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = format_string;
        return try fmt.format(writer, "{}", .{self.reference});
    }
};

pub const Union = union(enum) {
    const Self = @This();

    plain: PlainUnion,
    generic: GenericUnion,
    embedded: EmbeddedUnion,

    pub fn free(self: Self, allocator: mem.Allocator) void {
        switch (self) {
            .plain => |p| p.free(allocator),
            .generic => |g| g.free(allocator),
            .embedded => |e| e.free(allocator),
        }
    }

    pub fn isEqual(self: Self, other: Self) bool {
        return switch (self) {
            .plain => |p| meta.activeTag(other) == .plain and p.isEqual(other.plain),
            .generic => |g| meta.activeTag(other) == .generic and g.isEqual(other.generic),
            .embedded => |e| meta.activeTag(other) == .embedded and e.isEqual(other.embedded),
        };
    }

    pub fn name(self: Self) DefinitionName {
        return switch (self) {
            .plain => |plain| plain.name,
            .generic => |generic| generic.name,
            .embedded => |embedded| embedded.name,
        };
    }

    pub fn format(
        self: Self,
        comptime format_string: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = format_string;
        return switch (self) {
            .plain => |p| try fmt.format(writer, "{}", .{p}),
            .generic => |g| try fmt.format(writer, "{}", .{g}),
            .embedded => |e| try fmt.format(writer, "{}", .{e}),
        };
    }
};

pub const UnionOptions = struct {
    tag_field: []const u8,
    embedded: bool,
};

pub const PlainUnion = struct {
    const Self = @This();

    name: DefinitionName,
    constructors: []const Constructor,
    tag_field: []const u8,

    pub fn free(self: Self, allocator: mem.Allocator) void {
        allocator.free(self.name.value);
        for (self.constructors) |c| c.free(allocator);
        allocator.free(self.constructors);
        allocator.free(self.tag_field);
    }

    pub fn isEqual(self: Self, other: Self) bool {
        if (!self.name.isEqual(other.name)) return false;
        if (!mem.eql(u8, self.tag_field, other.tag_field)) return false;

        for (self.constructors, 0..) |constructor, i| {
            if (!constructor.isEqual(other.constructors[i])) return false;
        }

        return true;
    }
};

pub const GenericUnion = struct {
    const Self = @This();

    name: DefinitionName,
    constructors: []const Constructor,
    open_names: []const []const u8,
    tag_field: []const u8,

    pub fn free(self: Self, allocator: mem.Allocator) void {
        allocator.free(self.name.value);
        for (self.constructors) |c| c.free(allocator);
        allocator.free(self.constructors);
        allocator.free(self.tag_field);
        for (self.open_names) |n| allocator.free(n);
        allocator.free(self.open_names);
    }

    pub fn isEqual(self: Self, other: Self) bool {
        if (!self.name.isEqual(other.name)) return false;
        if (!mem.eql(u8, self.tag_field, other.tag_field)) return false;

        for (self.constructors, 0..) |constructor, i| {
            if (!constructor.isEqual(other.constructors[i])) return false;
        }

        for (self.open_names, 0..) |open_name, i| {
            if (!mem.eql(u8, open_name, other.open_names[i])) return false;
        }

        return true;
    }

    pub fn format(
        self: Self,
        comptime format_string: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = format_string;
        if (self.constructors.len > 0) {
            try fmt.format(writer, "{}<{s}>{{ {}", .{ self.name, self.open_names, self.constructors[0] });
            for (self.constructors[1..]) |c| {
                try fmt.format(writer, ", {}", .{c});
            }
            try fmt.format(writer, " }}", .{});
        } else {
            try fmt.format(writer, "{}<{s}>{{ }}", .{ self.name, self.open_names });
        }
    }
};

pub const EmbeddedUnion = struct {
    const Self = @This();

    name: DefinitionName,
    constructors: []const ConstructorWithEmbeddedTypeTag,
    open_names: []const []const u8,
    tag_field: []const u8,

    pub fn free(self: Self, allocator: mem.Allocator) void {
        allocator.free(self.name.value);
        allocator.free(self.tag_field);
        for (self.constructors) |*c| c.free(allocator);
        allocator.free(self.constructors);
        for (self.open_names) |n| allocator.free(n);
    }

    pub fn isEqual(self: Self, other: Self) bool {
        if (!mem.eql(u8, self.name.value, other.name.value)) return false;
        if (!mem.eql(u8, self.tag_field, other.tag_field)) return false;

        for (self.constructors, 0..) |constructor, i| {
            if (!constructor.isEqual(other.constructors[i])) return false;
        }

        for (self.open_names, 0..) |open_name, i| {
            if (!mem.eql(u8, open_name, other.open_names[i])) return false;
        }

        return true;
    }
};

pub const ConstructorWithEmbeddedTypeTag = struct {
    const Self = @This();

    tag: []const u8,
    parameter: ?Structure,

    pub fn free(self: Self, allocator: mem.Allocator) void {
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

    pub fn free(self: Self, allocator: mem.Allocator) void {
        allocator.free(self.tag);
        self.parameter.free(allocator);
    }

    pub fn isEqual(self: Self, other: Self) bool {
        return mem.eql(u8, self.tag, other.tag) and self.parameter.isEqual(other.parameter);
    }

    pub fn format(
        self: Self,
        comptime format_string: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = format_string;
        try fmt.format(writer, "{s}: {}", .{ self.tag, self.parameter });
    }
};

pub const Module = struct {
    const Self = @This();

    name: []const u8,
    filename: []const u8,
    definitions: []const Definition,
    definition_iterator: DefinitionIterator,
    allocator: mem.Allocator,

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.filename);
        self.allocator.free(self.definitions);
        self.definition_iterator.deinit();
    }
};

pub fn parse(
    allocator: mem.Allocator,
    error_allocator: mem.Allocator,
    filename: []const u8,
    buffer: []const u8,
    modules: ?ModuleMap,
    parsing_error: *ParsingError,
) !Module {
    _ = error_allocator;
    debug.assert(mem.endsWith(u8, filename, ".gotyno"));

    var split_iterator = mem.split(u8, filename, ".gotyno");
    const before_extension = split_iterator.next().?;

    const only_filename = if (mem.lastIndexOf(u8, before_extension, "/")) |index|
        before_extension[(index + 1)..]
    else
        before_extension;

    const module_name = only_filename;

    const copied_filename = try allocator.dupe(u8, filename);
    var definitions = ArrayList(Definition).init(allocator);
    var expect_error: ExpectError = undefined;
    var definition_iterator = DefinitionIterator.init(
        allocator,
        copied_filename,
        buffer,
        if (modules) |m| m else ModuleMap.init(allocator),
        parsing_error,
        &expect_error,
    );

    while (definition_iterator.next() catch |e| switch (e) {
        error.UnexpectedToken, error.UnexpectedEndOfTokenStream => {
            definition_iterator.parsing_error.* = ParsingError{ .expect = expect_error };

            return e;
        },
        else => return e,
    }) |definition| {
        try definitions.append(definition);
    }

    return Module{
        .name = module_name,
        .filename = copied_filename,
        .definitions = try definitions.toOwnedSlice(),
        .definition_iterator = definition_iterator,
        .allocator = allocator,
    };
}

pub fn parseWithDescribedError(
    allocator: mem.Allocator,
    error_allocator: mem.Allocator,
    filename: []const u8,
    buffer: []const u8,
    modules: ?ModuleMap,
    parsing_error: *ParsingError,
) !Module {
    return parse(allocator, error_allocator, filename, buffer, modules, parsing_error) catch |e| {
        switch (e) {
            error.UnexpectedToken,
            error.UnknownReference,
            error.UnknownModule,
            error.InvalidPayload,
            error.UnexpectedEndOfTokenStream,
            error.DuplicateDefinition,
            error.AppliedNameCount,
            => {
                switch (parsing_error.*) {
                    .expect => |expect| switch (expect) {
                        .token => |token| {
                            debug.panic(
                                "Unexpected token at {s}:{}:{}:\n\tExpected: {}\n\tGot: {}",
                                .{
                                    token.location.filename,
                                    token.location.line,
                                    token.location.column,
                                    token.expectation,
                                    token.got,
                                },
                            );
                        },
                        .one_of => |one_of| {
                            debug.print(
                                "Unexpected token at {s}:{}:{}:\n\tExpected one of: {}",
                                .{
                                    one_of.location.filename,
                                    one_of.location.line,
                                    one_of.location.column,
                                    one_of.expectations[0],
                                },
                            );
                            for (one_of.expectations[1..]) |expectation| {
                                debug.print(", {}", .{expectation});
                            }
                            debug.panic("\n\tGot: {}\n", .{one_of.got});
                        },
                    },

                    .invalid_payload => |invalid_payload| {
                        debug.panic(
                            "Invalid payload found at {s}:{}:{}, payload: {}\n",
                            .{
                                invalid_payload.location.filename,
                                invalid_payload.location.line,
                                invalid_payload.location.column,
                                invalid_payload.payload,
                            },
                        );
                    },

                    .unknown_reference => |unknown_reference| {
                        debug.panic(
                            "Unknown reference found at {s}:{}:{}, name: {s}\n",
                            .{
                                unknown_reference.location.filename,
                                unknown_reference.location.line,
                                unknown_reference.location.column,
                                unknown_reference.name,
                            },
                        );
                    },

                    .unknown_module => |unknown_module| {
                        debug.panic(
                            "Unknown module found at {s}:{}:{}, name: {s}\n",
                            .{
                                unknown_module.location.filename,
                                unknown_module.location.line,
                                unknown_module.location.column,
                                unknown_module.name,
                            },
                        );
                    },

                    .duplicate_definition => |d| {
                        debug.panic(
                            "Duplicate definition found at {s}:{}:{}, name: {s}, previously defined at {s}:{}:{}\n",
                            .{
                                d.location.filename,
                                d.location.line,
                                d.location.column,
                                d.definition.name().value,
                                d.previous_location.filename,
                                d.previous_location.line,
                                d.previous_location.column,
                            },
                        );
                    },

                    .applied_name_count => |d| {
                        debug.panic(
                            "Wrong number of type parameters for type {s} at {s}:{}:{}, expected: {}, got: {}\n",
                            .{
                                d.name,
                                d.location.filename,
                                d.location.line,
                                d.location.column,
                                d.expected,
                                d.actual,
                            },
                        );
                    },
                }
            },
            error.OutOfMemory, error.Overflow, error.InvalidCharacter => return e,
        }
    };
}

pub fn parseModules(
    allocator: mem.Allocator,
    error_allocator: mem.Allocator,
    buffers: []const BufferData,
    parsing_error: *ParsingError,
) !ModuleMap {
    var modules = ModuleMap.init(allocator);
    for (buffers) |b| {
        const module = try parse(
            allocator,
            error_allocator,
            b.filename,
            b.buffer,
            modules,
            parsing_error,
        );

        if (modules.get(module.name)) |_| {
            debug.panic("Multiple definitions of module with name '{s}'\n", .{b.filename});
        } else {
            try modules.add(module);
        }
    }

    return modules;
}

pub fn parseModulesWithDescribedError(
    allocator: mem.Allocator,
    error_allocator: mem.Allocator,
    buffers: []const BufferData,
    parsing_error: *ParsingError,
) !ModuleMap {
    var modules = ModuleMap.init(allocator);
    for (buffers) |b| {
        const module = try parseWithDescribedError(
            allocator,
            error_allocator,
            b.filename,
            b.buffer,
            modules,
            parsing_error,
        );

        if (modules.get(module.name)) |_| {
            debug.panic("Multiple definitions of module with name '{s}'\n", .{b.filename});
        } else {
            try modules.add(module);
        }
    }

    return modules;
}

const ModuleMap = struct {
    const Self = @This();

    modules: std.StringHashMap(Module),

    pub fn init(allocator: mem.Allocator) Self {
        return Self{ .modules = std.StringHashMap(Module).init(allocator) };
    }

    pub fn get(self: Self, name: []const u8) ?Module {
        return if (self.modules.get(name)) |module| module else null;
    }

    pub fn add(self: *Self, module: Module) !void {
        try self.modules.put(module.name, module);
    }

    pub fn deinit(self: *Self) void {
        var it = self.modules.iterator();

        while (it.next()) |entry| {
            entry.value.deinit();
        }

        self.modules.deinit();
    }
};
const DefinitionMap = std.StringHashMap(Definition);

/// `DefinitionIterator` is iterator that attempts to return the next definition in a source, based
/// on a `TokenIterator` that it holds inside of its instance. It's an unapologetically stateful
/// thing; most of what is going on in here depends entirely on the order methods are called and it
/// keeps whatever state it needs in the object itself.
pub const DefinitionIterator = struct {
    const Self = @This();

    token_iterator: TokenIterator,
    allocator: mem.Allocator,
    parsing_error: *ParsingError,
    expect_error: *ExpectError,

    /// Holds previously compiled modules.
    modules: ModuleMap,

    /// Holds all of the named definitions that have been parsed and is filled in each time a
    /// definition is successfully parsed, making it possible to refer to already parsed definitions
    /// when parsing later ones.
    named_definitions: DefinitionMap,

    /// We hold a list to the imports such that we can also free them properly.
    imports: ArrayList(Import),

    pub fn init(
        allocator: mem.Allocator,
        filename: []const u8,
        buffer: []const u8,
        modules: ModuleMap,
        parsing_error: *ParsingError,
        expect_error: *ExpectError,
    ) Self {
        const token_iterator = tokenizer.TokenIterator.init(filename, buffer);

        return DefinitionIterator{
            .token_iterator = token_iterator,
            .allocator = allocator,
            .parsing_error = parsing_error,
            .modules = modules,
            .named_definitions = DefinitionMap.init(allocator),
            .imports = ArrayList(Import).init(allocator),
            .expect_error = expect_error,
        };
    }

    pub fn deinit(self: *Self) void {
        var definition_iterator = self.named_definitions.iterator();

        for (self.imports.items) |i| i.free(self.allocator);
        self.imports.deinit();

        while (definition_iterator.next()) |entry| entry.*.value.free(self.allocator);

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
                                        try self.allocator.dupe(u8, "type"),
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
                                            .embedded = try self.parseEmbeddedUnionDefinition(
                                                options,
                                            ),
                                        },
                                    }
                                else
                                    Definition{
                                        .@"union" = try self.parseUnionDefinition(
                                            options.tag_field,
                                        ),
                                    };

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
                            .untagged_union = try self.parseUntaggedUnionDefinition(
                                &[_][]const u8{},
                            ),
                        };
                        try self.addDefinition(definition.untagged_union.name, definition);

                        return definition;
                    } else if (mem.eql(u8, s, "import")) {
                        _ = try tokens.expect(Token.space, self.expect_error);

                        const import = try self.parseImport();
                        try self.imports.append(import);
                        const definition = Definition{ .import = import };

                        return definition;
                    } else {
                        debug.panic(
                            "Expected one of `struct`, `union`, `enum`, `untagged` or `import`, got: `{s}`",
                            .{s},
                        );
                    }
                },
                else => {},
            }
        }

        return null;
    }

    fn parseDefinitionName(self: *Self) !DefinitionName {
        const name = switch (try self.token_iterator.expectOneOf(
            &[_]TokenTag{ .symbol, .name },
            self.expect_error,
        )) {
            .symbol => |symbol| try self.allocator.dupe(u8, symbol),
            .name => |name| try self.allocator.dupe(u8, name),
            else => unreachable,
        };

        return DefinitionName{
            .value = name,
            .location = Location{
                .filename = self.token_iterator.filename,
                .line = self.token_iterator.line,
                .column = self.token_iterator.column - name.len,
            },
        };
    }

    fn parsePascalDefinitionName(self: *Self) !DefinitionName {
        const name = try self.allocator.dupe(
            u8,
            (try self.token_iterator.expect(Token.name, self.expect_error)).name,
        );

        return DefinitionName{
            .value = name,
            .location = Location{
                .filename = self.token_iterator.filename,
                .line = self.token_iterator.line,
                .column = self.token_iterator.column - name.len,
            },
        };
    }

    fn parseImport(self: *Self) !Import {
        const tokens = &self.token_iterator;

        const import_name = try self.parseDefinitionName();

        return switch (try tokens.expectOneOf(
            &[_]TokenTag{ .newline, .crlf, .space },
            self.expect_error,
        )) {
            .newline, .crlf => Import{ .name = import_name, .alias = import_name.value },
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

        var maybe_tag_field: ?[]const u8 = null;
        var options = UnionOptions{
            .tag_field = undefined,
            .embedded = false,
        };

        var done_parsing_options = false;
        while (!done_parsing_options) {
            const symbol = (try tokens.expect(Token.symbol, self.expect_error)).symbol;
            if (mem.eql(u8, symbol, "tag")) {
                _ = try tokens.expect(Token.space, self.expect_error);
                _ = try tokens.expect(Token.equals, self.expect_error);
                _ = try tokens.expect(Token.space, self.expect_error);
                maybe_tag_field = try self.allocator.dupe(
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

        options.tag_field = if (maybe_tag_field) |tag_field|
            tag_field
        else
            try self.allocator.dupe(u8, "type");

        _ = try tokens.expect(Token.right_parenthesis, self.expect_error);
        _ = try tokens.expect(Token.space, self.expect_error);

        return options;
    }

    fn expectNewline(self: *Self) !void {
        _ = try self.token_iterator.expectOneOf(&[_]TokenTag{ .newline, .crlf }, self.expect_error);
    }

    fn parseUntaggedUnionDefinition(self: *Self, open_names: []const []const u8) !UntaggedUnion {
        const tokens = &self.token_iterator;

        const name = try self.parsePascalDefinitionName();

        _ = try tokens.expect(Token.space, self.expect_error);
        _ = try tokens.expect(Token.left_brace, self.expect_error);
        try self.expectNewline();

        var values = ArrayList(UntaggedUnionValue).init(self.allocator);
        defer values.deinit();
        var done_parsing_values = false;
        while (!done_parsing_values) {
            try tokens.skipMany(Token.space, 4, self.expect_error);
            const value_name = (try tokens.expect(Token.name, self.expect_error)).name;
            const value_location = Location{
                .filename = tokens.filename,
                .line = tokens.line,
                .column = tokens.column - value_name.len,
            };

            try values.append(UntaggedUnionValue{
                .reference = try self.getTypeReference(value_name, value_location, name, open_names),
            });

            try self.expectNewline();

            if (try tokens.peek()) |t| {
                switch (t) {
                    .right_brace => done_parsing_values = true,
                    else => {},
                }
            }
        }

        return UntaggedUnion{ .name = name, .values = try values.toOwnedSlice() };
    }

    fn parseEnumerationDefinition(self: *Self) !Enumeration {
        const tokens = &self.token_iterator;

        const name = try self.parsePascalDefinitionName();

        _ = try tokens.expect(Token.space, self.expect_error);
        _ = try tokens.expect(Token.left_brace, self.expect_error);
        try self.expectNewline();

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

            try self.expectNewline();
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

    fn parseStructureDefinition(self: *Self) !Structure {
        var tokens = &self.token_iterator;

        const definition_name = try self.parsePascalDefinitionName();

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

    fn parsePlainStructureDefinition(
        self: *Self,
        definition_name: DefinitionName,
    ) !PlainStructure {
        var fields = ArrayList(Field).init(self.allocator);
        const tokens = &self.token_iterator;

        try self.expectNewline();
        var done_parsing_fields = false;
        while (!done_parsing_fields) {
            if (try tokens.peek()) |t| {
                switch (t) {
                    .right_brace => done_parsing_fields = true,
                    else => {
                        try fields.append(
                            try self.parseStructureField(definition_name, &[_][]const u8{}),
                        );
                    },
                }
            }
        }
        _ = try tokens.expect(Token.right_brace, self.expect_error);

        return PlainStructure{ .name = definition_name, .fields = try fields.toOwnedSlice() };
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

        return try open_names.toOwnedSlice();
    }

    fn parseGenericStructureDefinition(
        self: *Self,
        definition_name: DefinitionName,
    ) !GenericStructure {
        var fields = ArrayList(Field).init(self.allocator);
        const tokens = &self.token_iterator;

        const open_names = try self.parseOpenNames();

        _ = try tokens.expect(Token.left_brace, self.expect_error);
        try self.expectNewline();
        var done_parsing_fields = false;
        while (!done_parsing_fields) {
            if (try tokens.peek()) |t| {
                switch (t) {
                    .right_brace => done_parsing_fields = true,
                    else => {},
                }
            }
            if (!done_parsing_fields) {
                try fields.append(try self.parseStructureField(definition_name, open_names));
            }
        }
        _ = try tokens.expect(Token.right_brace, self.expect_error);

        return GenericStructure{
            .name = definition_name,
            .fields = fields.items,
            .open_names = open_names,
        };
    }

    fn parseUnionDefinition(self: *Self, tag_field: []const u8) !Union {
        const tokens = &self.token_iterator;

        const definition_name = try self.parsePascalDefinitionName();

        _ = try tokens.expect(Token.space, self.expect_error);

        const left_angle_or_left_brace = try tokens.expectOneOf(
            &[_]TokenTag{ .left_angle, .left_brace },
            self.expect_error,
        );

        return switch (left_angle_or_left_brace) {
            .left_brace => Union{
                .plain = try self.parsePlainUnionDefinition(definition_name, tag_field),
            },
            .left_angle => Union{
                .generic = try self.parseGenericUnionDefinition(definition_name, tag_field),
            },
            else => debug.panic(
                "Invalid follow-up token after `union` keyword: {}\n",
                .{left_angle_or_left_brace},
            ),
        };
    }

    fn parseEmbeddedUnionDefinition(self: *Self, options: UnionOptions) !EmbeddedUnion {
        const tokens = &self.token_iterator;

        const definition_name = try self.parsePascalDefinitionName();

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

        try self.expectNewline();

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

            switch (try tokens.expectOneOf(&[_]TokenTag{ .colon, .newline, .crlf }, self.expect_error)) {
                .newline, .crlf => try constructors.append(ConstructorWithEmbeddedTypeTag{
                    .tag = tag,
                    .parameter = null,
                }),
                .colon => {
                    _ = try tokens.expect(Token.space, self.expect_error);

                    const parameter_name = (try tokens.expect(Token.name, self.expect_error)).name;
                    const parameter_location = Location{
                        .filename = tokens.filename,
                        .line = tokens.line,
                        .column = tokens.column - parameter_name.len,
                    };
                    const definition_for_name = self.getDefinition(parameter_name);
                    if (definition_for_name) |definition| {
                        const parameter = switch (definition) {
                            .structure => |s| s,
                            else => {
                                self.parsing_error.* = ParsingError{
                                    .invalid_payload = InvalidPayload{
                                        .location = self.token_iterator.location(),
                                        .payload = definition,
                                    },
                                };

                                return error.InvalidPayload;
                            },
                        };

                        try constructors.append(ConstructorWithEmbeddedTypeTag{
                            .tag = tag,
                            .parameter = parameter,
                        });

                        try self.expectNewline();
                    } else {
                        try self.returnUnknownReferenceError(
                            void,
                            parameter_name,
                            parameter_location,
                        );
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

    fn parsePlainUnionDefinition(
        self: *Self,
        definition_name: DefinitionName,
        tag_field: []const u8,
    ) !PlainUnion {
        var constructors = ArrayList(Constructor).init(self.allocator);
        const tokens = &self.token_iterator;

        try self.expectNewline();
        var done_parsing_constructors = false;
        while (!done_parsing_constructors) {
            if (try tokens.peek()) |t| {
                switch (t) {
                    .right_brace => done_parsing_constructors = true,
                    else => {},
                }
            }
            if (!done_parsing_constructors) {
                try constructors.append(
                    try self.parseConstructor(definition_name, &[_][]const u8{}),
                );
            }
        }
        _ = try tokens.expect(Token.right_brace, self.expect_error);

        return PlainUnion{
            .name = definition_name,
            .constructors = constructors.items,
            .tag_field = tag_field,
        };
    }

    fn parseGenericUnionDefinition(
        self: *Self,
        definition_name: DefinitionName,
        tag_field: []const u8,
    ) !GenericUnion {
        const tokens = &self.token_iterator;
        var constructors = ArrayList(Constructor).init(self.allocator);
        const open_names = try self.parseOpenNames();

        _ = try tokens.expect(Token.left_brace, self.expect_error);
        try self.expectNewline();

        var done_parsing_constructors = false;
        while (!done_parsing_constructors) {
            if (try tokens.peek()) |t| {
                switch (t) {
                    .right_brace => done_parsing_constructors = true,
                    else => {
                        try constructors.append(
                            try self.parseConstructor(definition_name, open_names),
                        );
                    },
                }
            }
        }
        _ = try tokens.expect(Token.right_brace, self.expect_error);

        return GenericUnion{
            .name = definition_name,
            .constructors = try constructors.toOwnedSlice(),
            .open_names = open_names,
            .tag_field = tag_field,
        };
    }

    fn parseConstructor(
        self: *Self,
        definition_name: DefinitionName,
        open_names: []const []const u8,
    ) !Constructor {
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
            &[_]TokenTag{ .colon, .newline, .crlf },
            self.expect_error,
        );

        if (colon_or_newline == Token.newline or colon_or_newline == Token.crlf) {
            return Constructor{ .tag = tag, .parameter = Type.empty };
        }

        _ = try tokens.expect(Token.space, self.expect_error);

        const parameter = try self.parseFieldType(definition_name, open_names);

        return Constructor{ .tag = tag, .parameter = parameter };
    }

    fn parseAdditionalName(self: *Self) ![]const u8 {
        const tokens = &self.token_iterator;
        _ = try tokens.expect(Token.space, self.expect_error);
        const name = (try tokens.expect(Token.name, self.expect_error)).name;

        return try self.allocator.dupe(u8, name);
    }

    fn parseStructureField(
        self: *Self,
        definition_name: DefinitionName,
        open_names: []const []const u8,
    ) !Field {
        var tokens = &self.token_iterator;
        _ = try tokens.skipMany(Token.space, 4, self.expect_error);
        const field_name = try self.allocator.dupe(
            u8,
            (try tokens.expect(Token.symbol, self.expect_error)).symbol,
        );
        _ = try tokens.expect(Token.colon, self.expect_error);
        _ = try tokens.expect(Token.space, self.expect_error);

        const field_type = try self.parseFieldType(definition_name, open_names);

        return Field{ .name = field_name, .type = field_type };
    }

    fn parseMaybeAppliedName(
        self: *Self,
        definition_name: DefinitionName,
        name: []const u8,
        open_names: []const []const u8,
    ) !?AppliedName {
        const tokens = &self.token_iterator;

        const maybe_left_angle_token = try tokens.peek();
        if (maybe_left_angle_token) |maybe_left_angle| {
            switch (maybe_left_angle) {
                // we have an applied name
                .left_angle => {
                    const start_location = Location{
                        .filename = self.token_iterator.filename,
                        .line = self.token_iterator.line,
                        .column = self.token_iterator.column - name.len,
                    };
                    _ = try tokens.expect(Token.left_angle, self.expect_error);
                    const applied_open_names = try self.parseAppliedOpenNames(
                        tokens,
                        self,
                        definition_name,
                        open_names,
                    );

                    const reference = try self.allocator.create(TypeReference);
                    reference.* = try self.getTypeReference(
                        name,
                        start_location,
                        definition_name,
                        open_names,
                    );

                    const expected_applied_name_count = reference.openNames().len;
                    const applied_name_count = applied_open_names.len;
                    if (applied_name_count != expected_applied_name_count) {
                        return try self.returnAppliedNameCountError(
                            ?AppliedName,
                            name,
                            @as(u32, @intCast(expected_applied_name_count)),
                            @as(u32, @intCast(applied_name_count)),
                            start_location,
                        );
                    }

                    return AppliedName{ .reference = reference, .open_names = applied_open_names };
                },
                else => {},
            }
        }

        return null;
    }

    const ParseImportedMaybeAppliedNameErrors = error{
        OutOfMemory,
        UnexpectedToken,
        UnexpectedEndOfTokenStream,
        Overflow,
        InvalidCharacter,
        UnknownModule,
        UnknownReference,
        AppliedNameCount,
    };

    fn parseImportedMaybeAppliedName(
        self: *Self,
        tokens: *TokenIterator,
        source_definitions: *DefinitionIterator,
        definition_name: DefinitionName,
        name: []const u8,
        open_names: []const []const u8,
        import_name: []const u8,
    ) ParseImportedMaybeAppliedNameErrors!?AppliedName {
        const name_location = Location{
            .filename = tokens.filename,
            .line = tokens.line,
            .column = tokens.column - name.len,
        };
        const maybe_left_angle_token = try tokens.peek();
        if (maybe_left_angle_token) |maybe_left_angle| {
            switch (maybe_left_angle) {
                // we have an applied name
                .left_angle => {
                    const start_location = Location{
                        .filename = tokens.filename,
                        .line = tokens.line,
                        .column = tokens.column - name.len,
                    };
                    _ = try tokens.expect(Token.left_angle, self.expect_error);
                    const applied_open_names = try source_definitions.parseAppliedOpenNames(
                        tokens,
                        source_definitions,
                        definition_name,
                        open_names,
                    );

                    const reference = try self.allocator.create(TypeReference);
                    reference.* = try self.importTypeReference(
                        source_definitions,
                        name,
                        name_location,
                        import_name,
                    );

                    const expected_applied_name_count = reference.openNames().len;
                    const applied_name_count = applied_open_names.len;
                    if (applied_name_count != expected_applied_name_count) {
                        return try source_definitions.returnAppliedNameCountError(
                            ?AppliedName,
                            name,
                            @as(u32, @intCast(expected_applied_name_count)),
                            @as(u32, @intCast(applied_name_count)),
                            start_location,
                        );
                    }

                    return AppliedName{ .reference = reference, .open_names = applied_open_names };
                },
                else => {},
            }
        }

        return null;
    }

    const ParseAppliedOpenNamesError = error{
        OutOfMemory,
        UnexpectedToken,
        UnexpectedEndOfTokenStream,
        Overflow,
        InvalidCharacter,
        UnknownModule,
        UnknownReference,
        AppliedNameCount,
    };

    fn parseAppliedOpenNames(
        self: *Self,
        tokens: *TokenIterator,
        source_definitions: *DefinitionIterator,
        current_definition_name: DefinitionName,
        parent_open_names: []const []const u8,
    ) ParseAppliedOpenNamesError![]AppliedOpenName {
        var applied_open_names = ArrayList(AppliedOpenName).init(self.allocator);

        var done = false;
        while (!done) {
            const parsed_type = try source_definitions.parseType(
                current_definition_name,
                parent_open_names,
            );

            switch (parsed_type) {
                .empty, .string => debug.panic(
                    "Invalid type parsed for applied open name: {}\n",
                    .{parsed_type},
                ),
                .array, .slice, .pointer, .optional, .reference => {
                    try applied_open_names.append(AppliedOpenName{ .reference = parsed_type });
                },
            }

            switch (try tokens.expectOneOf(&[_]TokenTag{ .comma, .right_angle }, self.expect_error)) {
                .right_angle => done = true,
                .comma => {
                    _ = try tokens.expect(Token.space, self.expect_error);
                },
                else => debug.panic("Unreachable.\n", .{}),
            }
        }

        return try applied_open_names.toOwnedSlice();
    }

    const ParseTypeError = error{
        OutOfMemory,
        UnexpectedToken,
        UnexpectedEndOfTokenStream,
        InvalidCharacter,
        Overflow,
        UnknownModule,
        UnknownReference,
        AppliedNameCount,
    };

    fn parseType(
        self: *Self,
        definition_name: DefinitionName,
        open_names: []const []const u8,
    ) ParseTypeError!Type {
        const tokens = &self.token_iterator;

        const start_token = try tokens.expectOneOf(
            &[_]TokenTag{ .string, .name, .symbol, .left_bracket, .asterisk, .question_mark },
            self.expect_error,
        );

        return switch (start_token) {
            .string => |s| Type{ .string = try self.allocator.dupe(u8, s) },
            .name => |name| result: {
                if (try self.parseMaybeAppliedName(
                    definition_name,
                    name,
                    open_names,
                )) |applied_name| {
                    break :result Type{ .reference = TypeReference{ .applied_name = applied_name } };
                } else {
                    const name_location = Location{
                        .filename = tokens.filename,
                        .line = tokens.line,
                        .column = tokens.column - name.len,
                    };
                    const reference = try self.getTypeReference(
                        name,
                        name_location,
                        definition_name,
                        open_names,
                    );

                    break :result Type{ .reference = reference };
                }
            },
            .symbol => |s| result: {
                const module_name = s;
                if (!self.hasImport(module_name))
                    return try self.returnUnknownModuleError(
                        Type,
                        module_name,
                        tokens.filename,
                    );
                _ = try tokens.expect(Token.period, self.expect_error);
                const module_definition_name = (try tokens.expect(
                    Token.name,
                    self.expect_error,
                )).name;
                const name_location = Location{
                    .filename = tokens.filename,
                    .line = tokens.line,
                    .column = tokens.column - module_definition_name.len,
                };

                if (self.getModule(module_name)) |*module| {
                    var definition_iterator = module.definition_iterator;
                    if (try definition_iterator.parseImportedMaybeAppliedName(
                        tokens,
                        self,
                        definition_name,
                        module_definition_name,
                        open_names,
                        module_name,
                    )) |applied_name| {
                        break :result Type{ .reference = TypeReference{ .applied_name = applied_name } };
                    } else if (module.definition_iterator.getDefinition(
                        module_definition_name,
                    )) |d| {
                        break :result Type{
                            .reference = TypeReference{
                                .imported_definition = ImportedDefinition{
                                    .import_name = module_name,
                                    .definition = d,
                                },
                            },
                        };
                    } else {
                        break :result try self.returnUnknownReferenceError(
                            Type,
                            module_definition_name,
                            name_location,
                        );
                    }
                } else {
                    break :result try self.returnUnknownModuleError(
                        Type,
                        module_name,
                        tokens.filename,
                    );
                }
            },

            .left_bracket => result: {
                const right_bracket_or_number = try tokens.expectOneOf(
                    &[_]TokenTag{ .right_bracket, .unsigned_integer },
                    self.expect_error,
                );

                switch (right_bracket_or_number) {
                    .right_bracket => {
                        const slice_type = try self.allocator.create(Type);
                        slice_type.* = try self.parseType(definition_name, open_names);

                        break :result Type{ .slice = Slice{ .type = slice_type } };
                    },
                    .unsigned_integer => |ui| {
                        _ = try tokens.expect(Token.right_bracket, self.expect_error);
                        const array_type = try self.allocator.create(Type);
                        array_type.* = try self.parseType(definition_name, open_names);

                        break :result Type{ .array = Array{ .type = array_type, .size = ui } };
                    },
                    else => {
                        debug.panic(
                            "Unknown slice/array component, expecting closing bracket or unsigned integer plus closing bracket. Got: {}\n",
                            .{right_bracket_or_number},
                        );
                    },
                }
            },

            .asterisk => result: {
                const pointer_type = try self.allocator.create(Type);
                pointer_type.* = try self.parseType(definition_name, open_names);

                break :result Type{ .pointer = Pointer{ .type = pointer_type } };
            },

            .question_mark => result: {
                const optional_type = try self.allocator.create(Type);
                optional_type.* = try self.parseType(definition_name, open_names);

                break :result Type{ .optional = Optional{ .type = optional_type } };
            },

            else => {
                debug.panic(
                    "Unexpected token in place of field value/type: {}",
                    .{start_token},
                );
            },
        };
    }

    fn hasImport(self: Self, import_name: []const u8) bool {
        // This matters mostly because otherwise we might output code that,
        // while it outputs the correct validators and knows that the imported module has been
        // parsed, it doesn't have a reference to the other module in the output.
        // Ideally this would be automatic from imported modules, but that's more work than I care
        // to put into that particular part right now.
        for (self.imports.items, 0..) |import, i| {
            _ = i;
            if (mem.eql(u8, import.name.value, import_name)) {
                return true;
            }
        }

        return false;
    }

    fn parseFieldType(
        self: *Self,
        definition_name: DefinitionName,
        open_names: []const []const u8,
    ) !Type {
        const field = try self.parseType(definition_name, open_names);

        try self.expectNewline();

        return field;
    }

    fn addDefinition(self: *Self, name: DefinitionName, definition: Definition) !void {
        const result = try self.named_definitions.getOrPut(name.value);

        if (result.found_existing)
            try self.returnDuplicateDefinition(void, name, definition, result.value_ptr.*)
        else
            result.value_ptr.* = definition;
    }

    pub fn getDefinition(self: Self, name: []const u8) ?Definition {
        return if (self.named_definitions.getEntry(name)) |definition|
            definition.value_ptr.*
        else
            null;
    }

    /// Used for getting a reference to a type via name; looked up in named definitions storage.
    /// This copies names/open names as needed.
    fn getTypeReference(
        self: Self,
        name: []const u8,
        location: Location,
        current_definition_name: DefinitionName,
        open_names: []const []const u8,
    ) !TypeReference {
        return if (isBuiltin(name))
            TypeReference{ .builtin = Builtin.fromString(name) }
        else if (self.getDefinition(name)) |found_definition|
            TypeReference{ .definition = found_definition }
        else if (mem.eql(u8, name, current_definition_name.value))
            TypeReference{
                .loose = LooseReference{
                    .name = try self.allocator.dupe(u8, name),
                    .open_names = try utilities.deepCopySlice(u8, self.allocator, open_names),
                },
            }
        else if (utilities.isStringEqualToOneOf(name, open_names))
            TypeReference{ .open = try self.allocator.dupe(u8, name) }
        else
            try self.returnUnknownReferenceError(TypeReference, name, location);
    }

    fn importTypeReference(
        self: Self,
        source_definitions: *DefinitionIterator,
        name: []const u8,
        name_location: Location,
        import_name: []const u8,
    ) !TypeReference {
        _ = source_definitions;
        return if (self.getDefinition(name)) |found_definition|
            TypeReference{
                .imported_definition = ImportedDefinition{
                    .import_name = import_name,
                    .definition = found_definition,
                },
            }
        else
            try self.returnUnknownReferenceError(TypeReference, name, name_location);
    }

    fn getModule(self: Self, name: []const u8) ?Module {
        return if (self.modules.get(name)) |module| module else null;
    }

    fn returnUnknownReferenceError(
        self: Self,
        comptime T: type,
        name: []const u8,
        location: Location,
    ) !T {
        self.parsing_error.* = ParsingError{
            .unknown_reference = UnknownReference{
                .location = location,
                .name = name,
            },
        };

        return error.UnknownReference;
    }

    fn returnUnknownModuleError(
        self: Self,
        comptime T: type,
        name: []const u8,
        filename: []const u8,
    ) !T {
        self.parsing_error.* = ParsingError{
            .unknown_module = UnknownModule{
                .location = Location{
                    .filename = filename,
                    .line = self.token_iterator.line,
                    .column = self.token_iterator.column - name.len,
                },
                .name = name,
            },
        };

        return error.UnknownModule;
    }

    fn returnDuplicateDefinition(
        self: Self,
        comptime T: type,
        name: DefinitionName,
        definition: Definition,
        existing_definition: Definition,
    ) !T {
        self.parsing_error.* = ParsingError{
            .duplicate_definition = DuplicateDefinition{
                .location = name.location,
                .previous_location = existing_definition.name().location,
                .existing_definition = existing_definition,
                .definition = definition,
            },
        };

        return error.DuplicateDefinition;
    }

    fn returnAppliedNameCountError(
        self: Self,
        comptime T: type,
        name: []const u8,
        expected_count: u32,
        actual_count: u32,
        location: Location,
    ) !T {
        self.parsing_error.* = ParsingError{
            .applied_name_count = AppliedNameCount{
                .name = name,
                .expected = expected_count,
                .actual = actual_count,
                .location = location,
            },
        };

        return error.AppliedNameCount;
    }
};

fn isBuiltin(name: []const u8) bool {
    return utilities.isStringEqualToOneOf(name, &[_][]const u8{
        "String",
        "Boolean",
        "U8",
        "U16",
        "U32",
        "U64",
        "I8",
        "I16",
        "I32",
        "I64",
        "F32",
        "F64",
    });
}

test {
    const parser_tests = @import("parser_tests.zig");
    std.testing.refAllDecls(parser_tests);
}
