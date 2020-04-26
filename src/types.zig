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

pub fn Either(comptime L: type, comptime R: type) type {
    return union(enum) {
        Left: L,
        Right: R,
    };
}

pub const EmbedsSimpleMaybe = struct {
    name: []const u8,
    age: Maybe(u8),
};

pub fn GenericThree(comptime T: type, comptime U: type, comptime V: type) type {
    return struct {
        v1: U,
        v2: T,
        v3: V,
        v4: U,
        v5: V,
        v6: T,
        dead_weight: bool,
    };
}

pub fn GenericFour(
    comptime T: type,
    comptime U: type,
    comptime V: type,
    comptime X: type,
) type {
    return struct {
        v1: U,
        v2: T,
        v3: V,
        v4: U,
        v5: V,
        v6: X,
        dead_weight: bool,
    };
}

pub fn GenericFive(
    comptime T: type,
    comptime U: type,
    comptime V: type,
    comptime X: type,
    comptime Y: type,
) type {
    return struct {
        v1: U,
        v2: T,
        v3: V,
        v4: U,
        v5: Y,
        v6: X,
        dead_weight: bool,
    };
}

pub fn GenericSix(
    comptime T: type,
    comptime U: type,
    comptime V: type,
    comptime X: type,
    comptime Y: type,
    comptime Z: type,
) type {
    return struct {
        v1: U,
        v2: T,
        v3: V,
        v4: Z,
        v5: Y,
        v6: X,
        dead_weight: bool,
    };
}
