# gotyno

A type definition language that outputs definitions and validation functions in
different languages (eventually).

## Supported languages

- [x] TypeScript
- [ ] F#
- [ ] OCaml
- [ ] Haskell
- [ ] PureScript
- [ ] Elixir (partial support)
- [ ] Zig

### TypeScript example

[basic.gotyno](./test_files/basic.gotyno) has an example of some types being
defined and [basic.ts](./test_files/basic.ts) is the automatically generated
TypeScript output from this file.

Behind the scenens it's using a validation library I wrote for validating
`unknown` values (for the most part against given interface definitions).

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

```
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

```
enum Colors {
    red = "FF0000"
    green = "00FF00"
    blue = "0000FF"
}
```

### Unions

#### Tagged

```
union InteractionEvent {
    Click: Coordinates
    KeyPress: KeyCode
    Focus: *Element,
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

```
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

## Note about MacOS releases

Cross-compilation from Linux/Windows doesn't yet work for MacOS so sadly I have
to recommend just downloading a current release of Zig and compiling via:

```
$ zig build -Drelease-fast
```

And running:

```
$ ./zig-cache/bin/gotyno --verbose --typescript inputFile.gotyno
```
