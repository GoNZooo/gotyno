pub const BasicStruct = struct {
    u: u32,
    i: i64,
    f: f64,
    s: []const u8,
    bools: []bool,
    hobbies: []const []const u8,
    lotto_numbers: [][]u32,
    points: []Point,
};

pub const BasicUnion = union(enum) {
    Struct: BasicStruct,
    Coordinates: Point,
    NoPayload,
};

pub const Point = struct {
    x: i32,
    y: i32,
};

pub fn GenericStruct(comptime T: type, comptime U: type) type {
    return struct {
        v1: T,
        v2: U,
        v3: T,
        non_generic_value: u32,
    };
}

pub fn Maybe(comptime T: type) type {
    return union(enum) {
        Nothing,
        Just: T,
    };
}
