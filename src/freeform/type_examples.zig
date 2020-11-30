pub const person_structure =
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
    \\union Maybe <T>{
    \\    Just: T;
    \\    Nothing;
    \\}
;

pub const either_union =
    \\union Either <E, T>{
    \\    Left: E;
    \\    Right: T;
    \\}
;

pub const list_union =
    \\union List <T>{
    \\    Empty;
    \\    Cons: *List<T>;
    \\}
;
