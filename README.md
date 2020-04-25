# zig-type-translator

The thesis is this: It's neat to write a type in one language and have it
automatically defined as per that spec in another language, with some leniency
with regards to idioms, etc.

## Example

In the repo you'll find (in `types.zig`) some basic types. These can be
automatically converted into other language forms via `typedefinitionToString`
functions in their respective modules.

```zig
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

const Point = struct {
    x: i32,
    y: i32,
};
```

Running the executable in this repo will yield:

```
TypeScript:
interface BasicStruct {
  type: "BasicStruct";
  u: number;
  i: number;
  f: number;
  s: string;
  bools: Array<boolean>;
  hobbies: Array<string>;
  lotto_numbers: Array<Array<number>>;
  points: Array<Point>;
}
type BasicUnion =
  BasicStruct
  | Point;

PureScript:
newtype BasicStruct
  = BasicStruct
  { u :: Int
  , i :: Int
  , f :: Number
  , s :: String
  , bools :: Array Boolean
  , hobbies :: Array String
  , lotto_numbers :: Array (Array Int)
  , points :: Array Point
  }
data BasicUnion
  = Struct BasicStruct
  | Coordinates Point
  | NoPayload

Haskell:
data BasicStruct
  = BasicStruct
  { u :: Int
  , i :: Int
  , f :: Number
  , s :: String
  , bools :: [Bool]
  , hobbies :: [String]
  , lotto_numbers :: [[Int]]
  , points :: [Point]
  }
data BasicUnion
  = Struct BasicStruct
  | Coordinates Point
  | NoPayload
```

Note the difference in what is important between TypeScript and PureScript/Haskell:

We want to distinguish types based on their payload in TypeScript, which is why
we have the `type` field/tag and the union is based on the payloads themselves.
