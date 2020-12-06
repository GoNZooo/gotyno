pub const person_structure =
    \\struct Person {
    \\    name: String;
    \\    age: U8;
    \\    efficiency: F32;
    \\    on_vacation: Boolean;
    \\    hobbies: []String;
    \\    last_fifteen_comments: [15]String;
    \\    recruiter: *Person;
    \\}
;

pub const node_structure =
    \\struct Node <T>{
    \\    data: T;
    \\}
;

pub const event_union =
    \\union Event {
    \\    LogIn: LogInData;
    \\    LogOut: UserId;
    \\    JoinChannels: []Channel;
    \\    SetEmails: [5]Email;
    \\}
;

pub const person_structure_and_event_union =
    \\struct Person {
    \\    name: String;
    \\    age: U8;
    \\    efficiency: F32;
    \\    on_vacation: Boolean;
    \\    hobbies: []String;
    \\    last_fifteen_comments: [15]String;
    \\    recruiter: *Person;
    \\}
    \\
    \\union Event {
    \\    LogIn: LogInData;
    \\    LogOut: UserId;
    \\    JoinChannels: []Channel;
    \\    SetEmails: [5]Email;
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

pub const structure_with_concrete_maybe =
    \\struct WithMaybe {
    \\    field: Maybe<String>;
    \\};
;

pub const union_with_different_maybes =
    \\union WithMaybe <T, E>{
    \\    WithConcrete: Maybe<String>;
    \\    WithGeneric: Maybe<T>;
    \\    WithBare: E;
    \\};
;
