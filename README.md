# zig-type-translator

The thesis is this: It's neat to write a type in one language and have it
automatically defined as per that spec in another language, with some leniency
with regards to idioms, etc.

## Way forward

Likely it'll make more sense to not interpret types from any one language'
internal structures and instead just parse either a ready-made language
(whatever pleases oneself, I guess?) or a basic format that is tailored for
the essentials of what one wants to do.

This is all obviously reinventing the wheel, which I'm fine with. More likely
than anything else is that I'll just write a parser in Zig for a custom format
and use that.

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

```typescript
// TypeScript:

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

interface Point {
  type: "Point";
  x: number;
  y: number;
}

type BasicUnion =
  BasicStruct
  | Point;
```

```purescript
-- PureScript:

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

newtype Point
  = Point
  { x :: Int
  , y :: Int
  }

data BasicUnion
  = Struct BasicStruct
  | Coordinates Point
  | NoPayload
```

```haskell
-- Haskell:

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

data Point
  = Point
  { x :: Int
  , y :: Int
  }

data BasicUnion
  = Struct BasicStruct
  | Coordinates Point
  | NoPayload
```

Note the difference in what is important between TypeScript and PureScript/Haskell:

We want to distinguish types based on their payload in TypeScript, which is why
we have the `type` field/tag and the union is based on the payloads themselves.
