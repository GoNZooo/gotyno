pub const person_struct =
    \\struct Person {
    \\    type: "Person";
    \\    name: String;
    \\    age: U8;
    \\    efficiency: F32;
    \\    on_vacation: Boolean;
    \\    hobbies: []String;
    \\    last_fifteen_comments: [15]String;
    \\}
;

pub const maybe_union =
    \\union <T> Maybe {
    \\    Just: T;
    \\    Nothing;
    \\}
;

pub const either_union =
    \\union <E, T> Either {
    \\    Left: E;
    \\    Right: T;
    \\}
;

pub const list_union =
    \\union <T> List {
    \\    Empty;
    \\    Cons: *List<T>;
    \\}
;
