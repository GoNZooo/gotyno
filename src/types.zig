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
};

const Point = struct {
    x: i32,
    y: i32,
};
