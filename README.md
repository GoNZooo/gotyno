# gotyno

A type definition language that outputs definitions and validation functions in
different languages (eventually).

## Other version

**Active development of this project has continued in a different implementation:**

[gotyno-hs](https://github.com/GoNZooo/gotyno-hs)

The reason for this, initially, was that I wanted to re-implement this in
Haskell and see how it'd turn out. The result was that adding things like
"compile on modification" was a lot easier, so the primary repository for the
compiler is now switched over.

### Features/fixes currently missing from this implementation

- Compile on modification / Watch mode
- "Declarations" (references to external data definitions)
- {U,I}{64,128} typed as bigints & encoded/decoded as strings
- Python output

If you don't need any of the above, this repo should be as good to use as it
was before. I do still recommend switching to `gotyno-hs`, since it's a lot more
active. I may backport some/all of the above features, but I can't promise that
it'll be done soon or at all.

## Supported languages

- [x] TypeScript
- [x] F#
- [ ] OCaml
- [ ] Haskell
- [ ] PureScript
- [ ] Elixir (partial support)
- [ ] Zig

### TypeScript example

[basic.gotyno](./test_files/basic.gotyno) has an example of some types being
defined and [basic.ts](./test_files/basic.ts) is the automatically generated
TypeScript output from this file.

Behind the scenes it's using a validation library I wrote for validating
`unknown` values (for the most part against given interface definitions).

### F# example

[basic.gotyno](./test_files/basic.gotyno) has an example of some types being
defined and [basic.fs](./test_files/basic.fs) is the automatically generated
F# output from this file.

The F# version uses `Thoth` for JSON decoding, as well as an additional
extension library to it for some custom decoding helpers that I wrote.

## The Language

All supported type names are uppercase and type definitions currently are
enforced as such as well.

### Annotations/Types

- `?TypeName` signifies an optional type.
- `*TypeName` signifies a pointer to that type. In languages where pointers are
  hidden from the user this may not be visible in types generated for it.
- `[]TypeName` signifies a sequence of several `TypeName` with a length known at
  run-time, whereas `[N]TypeName` signifies a sequence of several `TypeName`
  with a known and enforced length at compile-time. Some languages may or may
  not have the latter concept and will use only the former for code generation.
- `TypeName<OtherTypeName>` signifies an application of a generic type, such that
  whatever type variable `TypeName` takes in its definition is filled in with
  `OtherTypeName` in this specific instance.
- Conversely, `struct/union TypeName <T>{ ... }` is how one defines a type that
  takes a type parameter. The `<T>` part is seen here to take and provide a type
  `T` for the adjacent scope, hence its position in the syntax.
- The type `"SomeValue"` signifies a literal string of that value and can be
  used very effectively in TypeScript.
- The unsigned integer type is the same, but for integers. It's debatable
  whether this is useful to have.

### Structs

```gotyno
struct Recruiter {
    name: String
}

struct Person {
    name: String
    age: U8
    efficiency: F32
    on_vacation: Boolean
    hobbies: []String
    last_fifteen_comments: [15]String
    recruiter: ?Recruiter
    spouse: Maybe<Person>
}

struct Generic <T>{
    field: T
    other_field: OtherType<T>
}
```

### Enums

```gotyno
enum Colors {
    red = "FF0000"
    green = "00FF00"
    blue = "0000FF"
}
```

### Unions

#### Tagged

```gotyno
union InteractionEvent {
    Click: Coordinates
    KeyPress: KeyCode
    Focus: *Element
}

union Option <T>{
    None
    Some: T
}

union Result<E, T>{
    Error: E
    Ok: T
}
```

#### Untagged

Sometimes a union that carries no extra tags is required, though usually these
will have to be identified less automatically, perhaps via custom tags in their
respective payload:

```gotyno
struct SomeType {
    type: "SomeType"
    some_field: F32
    some_other_field: ?String
}

struct SomeOtherType {
    type: "SomeOtherType"
    active: Boolean
    some_other_field: ?String
}

untagged union Possible {
    SomeType
    SomeOtherType
    String
}
```

In TypeScript, for example, the correct type guard and validator for this
untagged union will be generated, and the literal string fields can still be
used for identifying which type one has.

#### Setting the tag key and embedding it in payload structures

The above can also be accomplished by setting the tag key to be embedded in
options passed to the `union` keyword (we can also set which key is used):

```gotyno
struct SomeType {
    some_field: F32
    some_other_field: ?String
}

struct SomeOtherType {
    active: Boolean
    some_other_field: ?String
}

union(tag = type_tag, embedded) Possible {
    FirstConstructor: SomeType
    SecondConstructor: SomeOtherType
}
```

This effectively will create a structure where we get the field `type_tag`
embedded in the payload structures (`SomeType` & `SomeOtherType`) with the
values `"FirstConstructor"` and `"SecondConstructor"` respectively.

Note that in order to embed a type key we obviously need the payload (if present)
to be a structure type, otherwise we have no fields to merge the type tag field
into.

Both checks for existence of the referenced payload types and checks that they
are structures are done during compilation.

## Note about MacOS releases

Cross-compilation from Linux/Windows doesn't yet work for MacOS so sadly I have
to recommend just downloading a current release of Zig and compiling via:

```bash
zig build -Drelease-fast
```

And running:

```bash
./zig-cache/bin/gotyno --verbose --typescript = --fsharp = inputFile.gotyno
# or
./zig-cache/bin/gotyno -v -ts = -fs = inputFile.gotyno
```

Optionally you can also specify a different output directory after
`-ts`/`--typescript`:

```bash
$ ./zig-cache/bin/gotyno --verbose --typescript other/directory/ts --fsharp other/directory/fs inputFile.gotyno
# or
$ ./zig-cache/bin/gotyno -v -ts other/directory/ts -fs other/directory/fs inputFile.gotyno
```

The output files for TypeScript/F# output will then be written in that directory,
still with the same module names as the input file.
