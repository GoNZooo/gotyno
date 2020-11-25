const std = @import("std");
const debug = std.debug;
const mem = std.mem;
const heap = std.heap;
const testing = std.testing;
const fmt = std.fmt;
const process = std.process;
const io = std.io;
const fs = std.fs;

const maybe_example =
    \\union Maybe<T> {
    \\    Just: T;
    \\    Nothing;
    \\}
;

const either_example =
    \\union Either<T, E> {
    \\    Right: T;
    \\    Left: E;
    \\}
;

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

const project_example =
    \\struct Project {
    \\    type: "Project";
    \\    id: u64;
    \\    owner: Person;
    \\    assigned_employees: []Person;
    \\}
;

const Field = struct {
    name: []const u8,
    specification: FieldSpecification,
};

const Literal = union(enum) {
    string: []const u8,
    integer: LiteralInteger,
    float: f64,
    boolean: bool,
};

const LiteralInteger = union(enum) {
    positive: u128,
    negative: i128,
};

const TypeSpecification = union(enum) {
    u8: void,
    u16: void,
    u32: void,
    u64: void,
    u128: void,
    i8: void,
    i16: void,
    i32: void,
    i64: void,
    i128: void,
    boolean: void,
    f32: void,
    f64: void,
    string: void,
    embedded_type: []const u8,
    slice: SliceSpecification,
    array: ArraySpecification,
};

const SliceSpecification = union(enum) {
    nested_slice: SliceSpecification,
    nested_array: ArraySpecification,
    simple: []const u8,
};

const FieldSpecification = union(enum) {
    literal: Literal,
    type_specification: TypeSpecification,
};

test "test runs" {
    testing.expectEqual(1 + 1, 2);
}
