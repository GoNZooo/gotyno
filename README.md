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

## Roadmap

The project was previously reoriented from a model where it took Zig type
definitions and turned them into types in other languages. This had some issues
that seemed to be more work than seemed reasonable or currently impossible to
solve so I reworked it into a type definition language instead.

Currently it parses generic type definitions correctly, but doesn't output
definitions and validation for them. I have an idea for how to solve this that
I'm fairly confident will work, but I've yet to create it.
