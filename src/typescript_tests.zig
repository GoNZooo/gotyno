const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const debug = std.debug;

const parser = @import("./freeform/parser.zig");
const tokenizer = @import("./freeform/tokenizer.zig");
const testing_utilities = @import("./freeform/testing_utilities.zig");
const type_examples = @import("./freeform/type_examples.zig");
const typescript = @import("./typescript.zig");

const Definition = parser.Definition;
const ImportedDefinition = parser.ImportedDefinition;
const AppliedName = parser.AppliedName;
const AppliedOpenName = parser.AppliedOpenName;
const ParsingError = parser.ParsingError;
const TokenTag = tokenizer.TokenTag;
const Token = tokenizer.Token;
const EnumerationField = parser.EnumerationField;
const EnumerationValue = parser.EnumerationValue;
const DefinitionName = parser.DefinitionName;
const BufferData = parser.BufferData;
const Import = parser.Import;
const Location = parser.Location;
const Slice = parser.Slice;
const Array = parser.Array;
const Pointer = parser.Pointer;
const Optional = parser.Optional;
const Union = parser.Union;
const PlainUnion = parser.PlainUnion;
const GenericUnion = parser.GenericUnion;
const Structure = parser.Structure;
const PlainStructure = parser.PlainStructure;
const GenericStructure = parser.GenericStructure;
const UntaggedUnion = parser.UntaggedUnion;
const UntaggedUnionValue = parser.UntaggedUnionValue;
const Enumeration = parser.Enumeration;
const Constructor = parser.Constructor;
const EmbeddedUnion = parser.EmbeddedUnion;
const ConstructorWithEmbeddedTypeTag = parser.ConstructorWithEmbeddedTypeTag;
const Field = parser.Field;
const Type = parser.Type;
const TypeReference = parser.TypeReference;
const LooseReference = parser.LooseReference;
const Builtin = parser.Builtin;
const TestingAllocator = testing_utilities.TestingAllocator;

test "Outputs `Person` struct correctly" {
    var allocator = TestingAllocator{};

    const expected_output =
        \\export type Person = {
        \\    type: "Person";
        \\    name: string;
        \\    age: number;
        \\    efficiency: number;
        \\    on_vacation: boolean;
        \\    hobbies: string[];
        \\    last_fifteen_comments: string[];
        \\    recruiter: Person;
        \\};
        \\
        \\export function isPerson(value: unknown): value is Person {
        \\    return svt.isInterface<Person>(value, {type: "Person", name: svt.isString, age: svt.isNumber, efficiency: svt.isNumber, on_vacation: svt.isBoolean, hobbies: svt.arrayOf(svt.isString), last_fifteen_comments: svt.arrayOf(svt.isString), recruiter: isPerson});
        \\}
        \\
        \\export function validatePerson(value: unknown): svt.ValidationResult<Person> {
        \\    return svt.validate<Person>(value, {type: "Person", name: svt.validateString, age: svt.validateNumber, efficiency: svt.validateNumber, on_vacation: svt.validateBoolean, hobbies: svt.validateArray(svt.validateString), last_fifteen_comments: svt.validateArray(svt.validateString), recruiter: validatePerson});
        \\}
    ;

    var parsing_error: ParsingError = undefined;

    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        "test.gotyno",
        type_examples.person_structure,
        null,
        &parsing_error,
    );

    const output = try typescript.outputPlainStructure(
        &allocator.allocator,
        (definitions).definitions[0].structure.plain,
    );

    testing.expectEqualStrings(output, expected_output);

    definitions.deinit();
    allocator.allocator.free(output);
    testing_utilities.expectNoLeaks(&allocator);
}

test "Outputs `Node` struct correctly" {
    var allocator = TestingAllocator{};

    const expected_output =
        \\export type Node<T, U> = {
        \\    data: T;
        \\    otherData: U;
        \\};
        \\
        \\export function isNode<T, U>(isT: svt.TypePredicate<T>, isU: svt.TypePredicate<U>): svt.TypePredicate<Node<T, U>> {
        \\    return function isNodeTU(value: unknown): value is Node<T, U> {
        \\        return svt.isInterface<Node<T, U>>(value, {data: isT, otherData: isU});
        \\    };
        \\}
        \\
        \\export function validateNode<T, U>(validateT: svt.Validator<T>, validateU: svt.Validator<U>): svt.Validator<Node<T, U>> {
        \\    return function validateNodeTU(value: unknown): svt.ValidationResult<Node<T, U>> {
        \\        return svt.validate<Node<T, U>>(value, {data: validateT, otherData: validateU});
        \\    };
        \\}
    ;

    var parsing_error: ParsingError = undefined;

    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        "test.gotyno",
        type_examples.node_structure,
        null,
        &parsing_error,
    );

    const output = try typescript.outputGenericStructure(
        &allocator.allocator,
        definitions.definitions[0].structure.generic,
    );

    testing.expectEqualStrings(output, expected_output);

    definitions.deinit();
    allocator.allocator.free(output);
    testing_utilities.expectNoLeaks(&allocator);
}

test "Outputs `Event` union correctly" {
    var allocator = TestingAllocator{};

    const expected_output =
        \\export type Event = LogIn | LogOut | JoinChannels | SetEmails | Close;
        \\
        \\export enum EventTag {
        \\    LogIn = "LogIn",
        \\    LogOut = "LogOut",
        \\    JoinChannels = "JoinChannels",
        \\    SetEmails = "SetEmails",
        \\    Close = "Close",
        \\}
        \\
        \\export type LogIn = {
        \\    type: EventTag.LogIn;
        \\    data: LogInData;
        \\};
        \\
        \\export type LogOut = {
        \\    type: EventTag.LogOut;
        \\    data: UserId;
        \\};
        \\
        \\export type JoinChannels = {
        \\    type: EventTag.JoinChannels;
        \\    data: Channel[];
        \\};
        \\
        \\export type SetEmails = {
        \\    type: EventTag.SetEmails;
        \\    data: Email[];
        \\};
        \\
        \\export type Close = {
        \\    type: EventTag.Close;
        \\};
        \\
        \\export function LogIn(data: LogInData): LogIn {
        \\    return {type: EventTag.LogIn, data};
        \\}
        \\
        \\export function LogOut(data: UserId): LogOut {
        \\    return {type: EventTag.LogOut, data};
        \\}
        \\
        \\export function JoinChannels(data: Channel[]): JoinChannels {
        \\    return {type: EventTag.JoinChannels, data};
        \\}
        \\
        \\export function SetEmails(data: Email[]): SetEmails {
        \\    return {type: EventTag.SetEmails, data};
        \\}
        \\
        \\export function Close(): Close {
        \\    return {type: EventTag.Close};
        \\}
        \\
        \\export function isEvent(value: unknown): value is Event {
        \\    return [isLogIn, isLogOut, isJoinChannels, isSetEmails, isClose].some((typePredicate) => typePredicate(value));
        \\}
        \\
        \\export function isLogIn(value: unknown): value is LogIn {
        \\    return svt.isInterface<LogIn>(value, {type: EventTag.LogIn, data: isLogInData});
        \\}
        \\
        \\export function isLogOut(value: unknown): value is LogOut {
        \\    return svt.isInterface<LogOut>(value, {type: EventTag.LogOut, data: isUserId});
        \\}
        \\
        \\export function isJoinChannels(value: unknown): value is JoinChannels {
        \\    return svt.isInterface<JoinChannels>(value, {type: EventTag.JoinChannels, data: svt.arrayOf(isChannel)});
        \\}
        \\
        \\export function isSetEmails(value: unknown): value is SetEmails {
        \\    return svt.isInterface<SetEmails>(value, {type: EventTag.SetEmails, data: svt.arrayOf(isEmail)});
        \\}
        \\
        \\export function isClose(value: unknown): value is Close {
        \\    return svt.isInterface<Close>(value, {type: EventTag.Close});
        \\}
        \\
        \\export function validateEvent(value: unknown): svt.ValidationResult<Event> {
        \\    return svt.validateWithTypeTag<Event>(value, {[EventTag.LogIn]: validateLogIn, [EventTag.LogOut]: validateLogOut, [EventTag.JoinChannels]: validateJoinChannels, [EventTag.SetEmails]: validateSetEmails, [EventTag.Close]: validateClose}, "type");
        \\}
        \\
        \\export function validateLogIn(value: unknown): svt.ValidationResult<LogIn> {
        \\    return svt.validate<LogIn>(value, {type: EventTag.LogIn, data: validateLogInData});
        \\}
        \\
        \\export function validateLogOut(value: unknown): svt.ValidationResult<LogOut> {
        \\    return svt.validate<LogOut>(value, {type: EventTag.LogOut, data: validateUserId});
        \\}
        \\
        \\export function validateJoinChannels(value: unknown): svt.ValidationResult<JoinChannels> {
        \\    return svt.validate<JoinChannels>(value, {type: EventTag.JoinChannels, data: svt.validateArray(validateChannel)});
        \\}
        \\
        \\export function validateSetEmails(value: unknown): svt.ValidationResult<SetEmails> {
        \\    return svt.validate<SetEmails>(value, {type: EventTag.SetEmails, data: svt.validateArray(validateEmail)});
        \\}
        \\
        \\export function validateClose(value: unknown): svt.ValidationResult<Close> {
        \\    return svt.validate<Close>(value, {type: EventTag.Close});
        \\}
    ;

    var parsing_error: ParsingError = undefined;

    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        "test.gotyno",
        type_examples.event_union,
        null,
        &parsing_error,
    );

    const output = try typescript.outputPlainUnion(
        &allocator.allocator,
        definitions.definitions[4].@"union".plain,
    );

    testing.expectEqualStrings(output, expected_output);

    definitions.deinit();
    allocator.allocator.free(output);
    testing_utilities.expectNoLeaks(&allocator);
}

test "Outputs `Maybe` union correctly" {
    var allocator = TestingAllocator{};

    const expected_output =
        \\export type Maybe<T> = just<T> | nothing;
        \\
        \\export enum MaybeTag {
        \\    just = "just",
        \\    nothing = "nothing",
        \\}
        \\
        \\export type just<T> = {
        \\    type: MaybeTag.just;
        \\    data: T;
        \\};
        \\
        \\export type nothing = {
        \\    type: MaybeTag.nothing;
        \\};
        \\
        \\export function just<T>(data: T): just<T> {
        \\    return {type: MaybeTag.just, data};
        \\}
        \\
        \\export function nothing(): nothing {
        \\    return {type: MaybeTag.nothing};
        \\}
        \\
        \\export function isMaybe<T>(isT: svt.TypePredicate<T>): svt.TypePredicate<Maybe<T>> {
        \\    return function isMaybeT(value: unknown): value is Maybe<T> {
        \\        return [isJust(isT), isNothing].some((typePredicate) => typePredicate(value));
        \\    };
        \\}
        \\
        \\export function isJust<T>(isT: svt.TypePredicate<T>): svt.TypePredicate<just<T>> {
        \\    return function isJustT(value: unknown): value is just<T> {
        \\        return svt.isInterface<just<T>>(value, {type: MaybeTag.just, data: isT});
        \\    };
        \\}
        \\
        \\export function isNothing(value: unknown): value is nothing {
        \\    return svt.isInterface<nothing>(value, {type: MaybeTag.nothing});
        \\}
        \\
        \\export function validateMaybe<T>(validateT: svt.Validator<T>): svt.Validator<Maybe<T>> {
        \\    return function validateMaybeT(value: unknown): svt.ValidationResult<Maybe<T>> {
        \\        return svt.validateWithTypeTag<Maybe<T>>(value, {[MaybeTag.just]: validateJust(validateT), [MaybeTag.nothing]: validateNothing}, "type");
        \\    };
        \\}
        \\
        \\export function validateJust<T>(validateT: svt.Validator<T>): svt.Validator<just<T>> {
        \\    return function validateJustT(value: unknown): svt.ValidationResult<just<T>> {
        \\        return svt.validate<just<T>>(value, {type: MaybeTag.just, data: validateT});
        \\    };
        \\}
        \\
        \\export function validateNothing(value: unknown): svt.ValidationResult<nothing> {
        \\    return svt.validate<nothing>(value, {type: MaybeTag.nothing});
        \\}
    ;

    var parsing_error: ParsingError = undefined;

    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        "test.gotyno",
        type_examples.maybe_union,
        null,
        &parsing_error,
    );

    const output = try typescript.outputGenericUnion(
        &allocator.allocator,
        definitions.definitions[0].@"union".generic,
    );

    testing.expectEqualStrings(output, expected_output);

    definitions.deinit();
    allocator.allocator.free(output);
    testing_utilities.expectNoLeaks(&allocator);
}

test "Outputs `Either` union correctly" {
    var allocator = TestingAllocator{};

    const expected_output =
        \\export type Either<E, T> = Left<E> | Right<T>;
        \\
        \\export enum EitherTag {
        \\    Left = "Left",
        \\    Right = "Right",
        \\}
        \\
        \\export type Left<E> = {
        \\    type: EitherTag.Left;
        \\    data: E;
        \\};
        \\
        \\export type Right<T> = {
        \\    type: EitherTag.Right;
        \\    data: T;
        \\};
        \\
        \\export function Left<E>(data: E): Left<E> {
        \\    return {type: EitherTag.Left, data};
        \\}
        \\
        \\export function Right<T>(data: T): Right<T> {
        \\    return {type: EitherTag.Right, data};
        \\}
        \\
        \\export function isEither<E, T>(isE: svt.TypePredicate<E>, isT: svt.TypePredicate<T>): svt.TypePredicate<Either<E, T>> {
        \\    return function isEitherET(value: unknown): value is Either<E, T> {
        \\        return [isLeft(isE), isRight(isT)].some((typePredicate) => typePredicate(value));
        \\    };
        \\}
        \\
        \\export function isLeft<E>(isE: svt.TypePredicate<E>): svt.TypePredicate<Left<E>> {
        \\    return function isLeftE(value: unknown): value is Left<E> {
        \\        return svt.isInterface<Left<E>>(value, {type: EitherTag.Left, data: isE});
        \\    };
        \\}
        \\
        \\export function isRight<T>(isT: svt.TypePredicate<T>): svt.TypePredicate<Right<T>> {
        \\    return function isRightT(value: unknown): value is Right<T> {
        \\        return svt.isInterface<Right<T>>(value, {type: EitherTag.Right, data: isT});
        \\    };
        \\}
        \\
        \\export function validateEither<E, T>(validateE: svt.Validator<E>, validateT: svt.Validator<T>): svt.Validator<Either<E, T>> {
        \\    return function validateEitherET(value: unknown): svt.ValidationResult<Either<E, T>> {
        \\        return svt.validateWithTypeTag<Either<E, T>>(value, {[EitherTag.Left]: validateLeft(validateE), [EitherTag.Right]: validateRight(validateT)}, "type");
        \\    };
        \\}
        \\
        \\export function validateLeft<E>(validateE: svt.Validator<E>): svt.Validator<Left<E>> {
        \\    return function validateLeftE(value: unknown): svt.ValidationResult<Left<E>> {
        \\        return svt.validate<Left<E>>(value, {type: EitherTag.Left, data: validateE});
        \\    };
        \\}
        \\
        \\export function validateRight<T>(validateT: svt.Validator<T>): svt.Validator<Right<T>> {
        \\    return function validateRightT(value: unknown): svt.ValidationResult<Right<T>> {
        \\        return svt.validate<Right<T>>(value, {type: EitherTag.Right, data: validateT});
        \\    };
        \\}
    ;

    var parsing_error: ParsingError = undefined;

    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        "test.gotyno",
        type_examples.either_union,
        null,
        &parsing_error,
    );

    const output = try typescript.outputGenericUnion(
        &allocator.allocator,
        definitions.definitions[0].@"union".generic,
    );

    testing.expectEqualStrings(output, expected_output);

    definitions.deinit();
    allocator.allocator.free(output);
    testing_utilities.expectNoLeaks(&allocator);
}

test "Outputs struct with concrete `Maybe` correctly" {
    var allocator = TestingAllocator{};

    const expected_output =
        \\export type WithMaybe = {
        \\    field: Maybe<string>;
        \\};
        \\
        \\export function isWithMaybe(value: unknown): value is WithMaybe {
        \\    return svt.isInterface<WithMaybe>(value, {field: isMaybe(svt.isString)});
        \\}
        \\
        \\export function validateWithMaybe(value: unknown): svt.ValidationResult<WithMaybe> {
        \\    return svt.validate<WithMaybe>(value, {field: validateMaybe(svt.validateString)});
        \\}
    ;

    var parsing_error: ParsingError = undefined;

    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        "test.gotyno",
        type_examples.structure_with_concrete_maybe,
        null,
        &parsing_error,
    );

    const output = try typescript.outputPlainStructure(
        &allocator.allocator,
        definitions.definitions[1].structure.plain,
    );

    testing.expectEqualStrings(output, expected_output);

    definitions.deinit();
    allocator.allocator.free(output);
    testing_utilities.expectNoLeaks(&allocator);
}

test "Outputs struct with different `Maybe`s correctly" {
    var allocator = TestingAllocator{};

    const expected_output =
        \\export type WithMaybe<T, E> = WithConcrete | WithGeneric<T> | WithBare<E>;
        \\
        \\export enum WithMaybeTag {
        \\    WithConcrete = "WithConcrete",
        \\    WithGeneric = "WithGeneric",
        \\    WithBare = "WithBare",
        \\}
        \\
        \\export type WithConcrete = {
        \\    type: WithMaybeTag.WithConcrete;
        \\    data: Maybe<string>;
        \\};
        \\
        \\export type WithGeneric<T> = {
        \\    type: WithMaybeTag.WithGeneric;
        \\    data: Maybe<T>;
        \\};
        \\
        \\export type WithBare<E> = {
        \\    type: WithMaybeTag.WithBare;
        \\    data: E;
        \\};
        \\
        \\export function WithConcrete(data: Maybe<string>): WithConcrete {
        \\    return {type: WithMaybeTag.WithConcrete, data};
        \\}
        \\
        \\export function WithGeneric<T>(data: Maybe<T>): WithGeneric<T> {
        \\    return {type: WithMaybeTag.WithGeneric, data};
        \\}
        \\
        \\export function WithBare<E>(data: E): WithBare<E> {
        \\    return {type: WithMaybeTag.WithBare, data};
        \\}
        \\
        \\export function isWithMaybe<T, E>(isT: svt.TypePredicate<T>, isE: svt.TypePredicate<E>): svt.TypePredicate<WithMaybe<T, E>> {
        \\    return function isWithMaybeTE(value: unknown): value is WithMaybe<T, E> {
        \\        return [isWithConcrete, isWithGeneric(isT), isWithBare(isE)].some((typePredicate) => typePredicate(value));
        \\    };
        \\}
        \\
        \\export function isWithConcrete(value: unknown): value is WithConcrete {
        \\    return svt.isInterface<WithConcrete>(value, {type: WithMaybeTag.WithConcrete, data: isMaybe(svt.isString)});
        \\}
        \\
        \\export function isWithGeneric<T>(isT: svt.TypePredicate<T>): svt.TypePredicate<WithGeneric<T>> {
        \\    return function isWithGenericT(value: unknown): value is WithGeneric<T> {
        \\        return svt.isInterface<WithGeneric<T>>(value, {type: WithMaybeTag.WithGeneric, data: isMaybe(isT)});
        \\    };
        \\}
        \\
        \\export function isWithBare<E>(isE: svt.TypePredicate<E>): svt.TypePredicate<WithBare<E>> {
        \\    return function isWithBareE(value: unknown): value is WithBare<E> {
        \\        return svt.isInterface<WithBare<E>>(value, {type: WithMaybeTag.WithBare, data: isE});
        \\    };
        \\}
        \\
        \\export function validateWithMaybe<T, E>(validateT: svt.Validator<T>, validateE: svt.Validator<E>): svt.Validator<WithMaybe<T, E>> {
        \\    return function validateWithMaybeTE(value: unknown): svt.ValidationResult<WithMaybe<T, E>> {
        \\        return svt.validateWithTypeTag<WithMaybe<T, E>>(value, {[WithMaybeTag.WithConcrete]: validateWithConcrete, [WithMaybeTag.WithGeneric]: validateWithGeneric(validateT), [WithMaybeTag.WithBare]: validateWithBare(validateE)}, "type");
        \\    };
        \\}
        \\
        \\export function validateWithConcrete(value: unknown): svt.ValidationResult<WithConcrete> {
        \\    return svt.validate<WithConcrete>(value, {type: WithMaybeTag.WithConcrete, data: validateMaybe(svt.validateString)});
        \\}
        \\
        \\export function validateWithGeneric<T>(validateT: svt.Validator<T>): svt.Validator<WithGeneric<T>> {
        \\    return function validateWithGenericT(value: unknown): svt.ValidationResult<WithGeneric<T>> {
        \\        return svt.validate<WithGeneric<T>>(value, {type: WithMaybeTag.WithGeneric, data: validateMaybe(validateT)});
        \\    };
        \\}
        \\
        \\export function validateWithBare<E>(validateE: svt.Validator<E>): svt.Validator<WithBare<E>> {
        \\    return function validateWithBareE(value: unknown): svt.ValidationResult<WithBare<E>> {
        \\        return svt.validate<WithBare<E>>(value, {type: WithMaybeTag.WithBare, data: validateE});
        \\    };
        \\}
    ;

    var parsing_error: ParsingError = undefined;

    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        "test.gotyno",
        type_examples.union_with_different_maybes,
        null,
        &parsing_error,
    );

    const output = try typescript.outputGenericUnion(
        &allocator.allocator,
        definitions.definitions[1].@"union".generic,
    );

    testing.expectEqualStrings(output, expected_output);

    definitions.deinit();
    allocator.allocator.free(output);
    testing_utilities.expectNoLeaks(&allocator);
}

test "Outputs `List` union correctly" {
    var allocator = TestingAllocator{};

    const expected_output =
        \\export type List<T> = Empty | Cons<T>;
        \\
        \\export enum ListTag {
        \\    Empty = "Empty",
        \\    Cons = "Cons",
        \\}
        \\
        \\export type Empty = {
        \\    type: ListTag.Empty;
        \\};
        \\
        \\export type Cons<T> = {
        \\    type: ListTag.Cons;
        \\    data: List<T>;
        \\};
        \\
        \\export function Empty(): Empty {
        \\    return {type: ListTag.Empty};
        \\}
        \\
        \\export function Cons<T>(data: List<T>): Cons<T> {
        \\    return {type: ListTag.Cons, data};
        \\}
        \\
        \\export function isList<T>(isT: svt.TypePredicate<T>): svt.TypePredicate<List<T>> {
        \\    return function isListT(value: unknown): value is List<T> {
        \\        return [isEmpty, isCons(isT)].some((typePredicate) => typePredicate(value));
        \\    };
        \\}
        \\
        \\export function isEmpty(value: unknown): value is Empty {
        \\    return svt.isInterface<Empty>(value, {type: ListTag.Empty});
        \\}
        \\
        \\export function isCons<T>(isT: svt.TypePredicate<T>): svt.TypePredicate<Cons<T>> {
        \\    return function isConsT(value: unknown): value is Cons<T> {
        \\        return svt.isInterface<Cons<T>>(value, {type: ListTag.Cons, data: isList(isT)});
        \\    };
        \\}
        \\
        \\export function validateList<T>(validateT: svt.Validator<T>): svt.Validator<List<T>> {
        \\    return function validateListT(value: unknown): svt.ValidationResult<List<T>> {
        \\        return svt.validateWithTypeTag<List<T>>(value, {[ListTag.Empty]: validateEmpty, [ListTag.Cons]: validateCons(validateT)}, "type");
        \\    };
        \\}
        \\
        \\export function validateEmpty(value: unknown): svt.ValidationResult<Empty> {
        \\    return svt.validate<Empty>(value, {type: ListTag.Empty});
        \\}
        \\
        \\export function validateCons<T>(validateT: svt.Validator<T>): svt.Validator<Cons<T>> {
        \\    return function validateConsT(value: unknown): svt.ValidationResult<Cons<T>> {
        \\        return svt.validate<Cons<T>>(value, {type: ListTag.Cons, data: validateList(validateT)});
        \\    };
        \\}
    ;

    var parsing_error: ParsingError = undefined;

    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        "test.gotyno",
        type_examples.list_union,
        null,
        &parsing_error,
    );

    const output = try typescript.outputGenericUnion(
        &allocator.allocator,
        definitions.definitions[0].@"union".generic,
    );

    testing.expectEqualStrings(output, expected_output);

    definitions.deinit();
    allocator.allocator.free(output);
    testing_utilities.expectNoLeaks(&allocator);
}

test "Outputs struct with optional float value correctly" {
    var allocator = TestingAllocator{};

    const expected_output =
        \\export type WithOptionalFloat = {
        \\    field: number | null | undefined;
        \\};
        \\
        \\export function isWithOptionalFloat(value: unknown): value is WithOptionalFloat {
        \\    return svt.isInterface<WithOptionalFloat>(value, {field: svt.optional(svt.isNumber)});
        \\}
        \\
        \\export function validateWithOptionalFloat(value: unknown): svt.ValidationResult<WithOptionalFloat> {
        \\    return svt.validate<WithOptionalFloat>(value, {field: svt.validateOptional(svt.validateNumber)});
        \\}
    ;

    var parsing_error: ParsingError = undefined;

    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        "test.gotyno",
        type_examples.structure_with_optional_float,
        null,
        &parsing_error,
    );

    const output = try typescript.outputPlainStructure(
        &allocator.allocator,
        definitions.definitions[0].structure.plain,
    );

    testing.expectEqualStrings(output, expected_output);

    definitions.deinit();
    allocator.allocator.free(output);
    testing_utilities.expectNoLeaks(&allocator);
}

test "lowercase plain union has correct output" {
    var allocator = TestingAllocator{};

    const definition_buffer =
        \\union BackdropSize {
        \\    w300
        \\    w1280
        \\    original
        \\}
    ;

    const expected_output =
        \\export type BackdropSize = w300 | w1280 | original;
        \\
        \\export enum BackdropSizeTag {
        \\    w300 = "w300",
        \\    w1280 = "w1280",
        \\    original = "original",
        \\}
        \\
        \\export type w300 = {
        \\    type: BackdropSizeTag.w300;
        \\};
        \\
        \\export type w1280 = {
        \\    type: BackdropSizeTag.w1280;
        \\};
        \\
        \\export type original = {
        \\    type: BackdropSizeTag.original;
        \\};
        \\
        \\export function w300(): w300 {
        \\    return {type: BackdropSizeTag.w300};
        \\}
        \\
        \\export function w1280(): w1280 {
        \\    return {type: BackdropSizeTag.w1280};
        \\}
        \\
        \\export function original(): original {
        \\    return {type: BackdropSizeTag.original};
        \\}
        \\
        \\export function isBackdropSize(value: unknown): value is BackdropSize {
        \\    return [isW300, isW1280, isOriginal].some((typePredicate) => typePredicate(value));
        \\}
        \\
        \\export function isW300(value: unknown): value is w300 {
        \\    return svt.isInterface<w300>(value, {type: BackdropSizeTag.w300});
        \\}
        \\
        \\export function isW1280(value: unknown): value is w1280 {
        \\    return svt.isInterface<w1280>(value, {type: BackdropSizeTag.w1280});
        \\}
        \\
        \\export function isOriginal(value: unknown): value is original {
        \\    return svt.isInterface<original>(value, {type: BackdropSizeTag.original});
        \\}
        \\
        \\export function validateBackdropSize(value: unknown): svt.ValidationResult<BackdropSize> {
        \\    return svt.validateWithTypeTag<BackdropSize>(value, {[BackdropSizeTag.w300]: validateW300, [BackdropSizeTag.w1280]: validateW1280, [BackdropSizeTag.original]: validateOriginal}, "type");
        \\}
        \\
        \\export function validateW300(value: unknown): svt.ValidationResult<w300> {
        \\    return svt.validate<w300>(value, {type: BackdropSizeTag.w300});
        \\}
        \\
        \\export function validateW1280(value: unknown): svt.ValidationResult<w1280> {
        \\    return svt.validate<w1280>(value, {type: BackdropSizeTag.w1280});
        \\}
        \\
        \\export function validateOriginal(value: unknown): svt.ValidationResult<original> {
        \\    return svt.validate<original>(value, {type: BackdropSizeTag.original});
        \\}
    ;

    var parsing_error: ParsingError = undefined;

    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        "test.gotyno",
        definition_buffer,
        null,
        &parsing_error,
    );

    const output = try typescript.outputPlainUnion(
        &allocator.allocator,
        definitions.definitions[0].@"union".plain,
    );

    testing.expectEqualStrings(output, expected_output);

    definitions.deinit();
    allocator.allocator.free(output);
    testing_utilities.expectNoLeaks(&allocator);
}

test "basic string-based enumeration is output correctly" {
    var allocator = TestingAllocator{};

    const definition_buffer =
        \\enum BackdropSize {
        \\    w300 = "w300"
        \\    w1280 = "w1280"
        \\    original = "original"
        \\}
    ;

    const expected_output =
        \\export enum BackdropSize {
        \\    w300 = "w300",
        \\    w1280 = "w1280",
        \\    original = "original",
        \\}
        \\
        \\export function isBackdropSize(value: unknown): value is BackdropSize {
        \\    return [BackdropSize.w300, BackdropSize.w1280, BackdropSize.original].some((v) => v === value);
        \\}
        \\
        \\export function validateBackdropSize(value: unknown): svt.ValidationResult<BackdropSize> {
        \\    return svt.validateOneOfLiterals<BackdropSize>(value, [BackdropSize.w300, BackdropSize.w1280, BackdropSize.original]);
        \\}
    ;

    var parsing_error: ParsingError = undefined;
    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        "test.gotyno",
        definition_buffer,
        null,
        &parsing_error,
    );

    const output = try typescript.outputEnumeration(
        &allocator.allocator,
        definitions.definitions[0].enumeration,
    );

    testing.expectEqualStrings(output, expected_output);

    definitions.deinit();
    allocator.allocator.free(output);
    testing_utilities.expectNoLeaks(&allocator);
}

test "Basic untagged union is output correctly" {
    var allocator = TestingAllocator{};

    const definition_buffer =
        \\struct KnownForShow {
        \\    f: String
        \\}
        \\
        \\struct KnownForMovie {
        \\    f: U32
        \\}
        \\
        \\untagged union KnownFor {
        \\    KnownForMovie
        \\    KnownForShow
        \\    String
        \\    F32
        \\}
    ;

    const expected_output =
        \\export type KnownFor = KnownForMovie | KnownForShow | string | number;
        \\
        \\export function isKnownFor(value: unknown): value is KnownFor {
        \\    return [isKnownForMovie, isKnownForShow, svt.isString, svt.isNumber].some((typePredicate) => typePredicate(value));
        \\}
        \\
        \\export function validateKnownFor(value: unknown): svt.ValidationResult<KnownFor> {
        \\    return svt.validateOneOf<KnownFor>(value, [validateKnownForMovie, validateKnownForShow, svt.validateString, svt.validateNumber]);
        \\}
    ;

    var parsing_error: ParsingError = undefined;
    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        "test.gotyno",
        definition_buffer,
        null,
        &parsing_error,
    );

    const output = try typescript.outputUntaggedUnion(
        &allocator.allocator,
        definitions.definitions[2].untagged_union,
    );

    testing.expectEqualStrings(output, expected_output);

    definitions.deinit();
    allocator.allocator.free(output);
    testing_utilities.expectNoLeaks(&allocator);
}

test "Tagged union with tag specifier is output correctly" {
    var allocator = TestingAllocator{};

    const definition_buffer =
        \\struct Movie {
        \\    f: String
        \\}
        \\
        \\struct Show {
        \\    f2: String
        \\}
        \\
        \\union(tag = kind) KnownFor {
        \\    KnownForMovie: Movie
        \\    KnownForShow: Show
        \\}
    ;

    const expected_output =
        \\export type KnownFor = KnownForMovie | KnownForShow;
        \\
        \\export enum KnownForTag {
        \\    KnownForMovie = "KnownForMovie",
        \\    KnownForShow = "KnownForShow",
        \\}
        \\
        \\export type KnownForMovie = {
        \\    kind: KnownForTag.KnownForMovie;
        \\    data: Movie;
        \\};
        \\
        \\export type KnownForShow = {
        \\    kind: KnownForTag.KnownForShow;
        \\    data: Show;
        \\};
        \\
        \\export function KnownForMovie(data: Movie): KnownForMovie {
        \\    return {kind: KnownForTag.KnownForMovie, data};
        \\}
        \\
        \\export function KnownForShow(data: Show): KnownForShow {
        \\    return {kind: KnownForTag.KnownForShow, data};
        \\}
        \\
        \\export function isKnownFor(value: unknown): value is KnownFor {
        \\    return [isKnownForMovie, isKnownForShow].some((typePredicate) => typePredicate(value));
        \\}
        \\
        \\export function isKnownForMovie(value: unknown): value is KnownForMovie {
        \\    return svt.isInterface<KnownForMovie>(value, {kind: KnownForTag.KnownForMovie, data: isMovie});
        \\}
        \\
        \\export function isKnownForShow(value: unknown): value is KnownForShow {
        \\    return svt.isInterface<KnownForShow>(value, {kind: KnownForTag.KnownForShow, data: isShow});
        \\}
        \\
        \\export function validateKnownFor(value: unknown): svt.ValidationResult<KnownFor> {
        \\    return svt.validateWithTypeTag<KnownFor>(value, {[KnownForTag.KnownForMovie]: validateKnownForMovie, [KnownForTag.KnownForShow]: validateKnownForShow}, "kind");
        \\}
        \\
        \\export function validateKnownForMovie(value: unknown): svt.ValidationResult<KnownForMovie> {
        \\    return svt.validate<KnownForMovie>(value, {kind: KnownForTag.KnownForMovie, data: validateMovie});
        \\}
        \\
        \\export function validateKnownForShow(value: unknown): svt.ValidationResult<KnownForShow> {
        \\    return svt.validate<KnownForShow>(value, {kind: KnownForTag.KnownForShow, data: validateShow});
        \\}
    ;

    var parsing_error: ParsingError = undefined;
    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        "test.gotyno",
        definition_buffer,
        null,
        &parsing_error,
    );

    const output = try typescript.outputPlainUnion(
        &allocator.allocator,
        definitions.definitions[2].@"union".plain,
    );

    testing.expectEqualStrings(output, expected_output);

    definitions.deinit();
    allocator.allocator.free(output);
    testing_utilities.expectNoLeaks(&allocator);
}

test "Tagged generic union with tag specifier is output correctly" {
    var allocator = TestingAllocator{};

    const definition_buffer =
        \\union(tag = kind) Option <T>{
        \\    Some: T
        \\    None
        \\}
    ;

    const expected_output =
        \\export type Option<T> = Some<T> | None;
        \\
        \\export enum OptionTag {
        \\    Some = "Some",
        \\    None = "None",
        \\}
        \\
        \\export type Some<T> = {
        \\    kind: OptionTag.Some;
        \\    data: T;
        \\};
        \\
        \\export type None = {
        \\    kind: OptionTag.None;
        \\};
        \\
        \\export function Some<T>(data: T): Some<T> {
        \\    return {kind: OptionTag.Some, data};
        \\}
        \\
        \\export function None(): None {
        \\    return {kind: OptionTag.None};
        \\}
        \\
        \\export function isOption<T>(isT: svt.TypePredicate<T>): svt.TypePredicate<Option<T>> {
        \\    return function isOptionT(value: unknown): value is Option<T> {
        \\        return [isSome(isT), isNone].some((typePredicate) => typePredicate(value));
        \\    };
        \\}
        \\
        \\export function isSome<T>(isT: svt.TypePredicate<T>): svt.TypePredicate<Some<T>> {
        \\    return function isSomeT(value: unknown): value is Some<T> {
        \\        return svt.isInterface<Some<T>>(value, {kind: OptionTag.Some, data: isT});
        \\    };
        \\}
        \\
        \\export function isNone(value: unknown): value is None {
        \\    return svt.isInterface<None>(value, {kind: OptionTag.None});
        \\}
        \\
        \\export function validateOption<T>(validateT: svt.Validator<T>): svt.Validator<Option<T>> {
        \\    return function validateOptionT(value: unknown): svt.ValidationResult<Option<T>> {
        \\        return svt.validateWithTypeTag<Option<T>>(value, {[OptionTag.Some]: validateSome(validateT), [OptionTag.None]: validateNone}, "kind");
        \\    };
        \\}
        \\
        \\export function validateSome<T>(validateT: svt.Validator<T>): svt.Validator<Some<T>> {
        \\    return function validateSomeT(value: unknown): svt.ValidationResult<Some<T>> {
        \\        return svt.validate<Some<T>>(value, {kind: OptionTag.Some, data: validateT});
        \\    };
        \\}
        \\
        \\export function validateNone(value: unknown): svt.ValidationResult<None> {
        \\    return svt.validate<None>(value, {kind: OptionTag.None});
        \\}
    ;

    var parsing_error: ParsingError = undefined;
    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        "test.gotyno",
        definition_buffer,
        null,
        &parsing_error,
    );

    const output = try typescript.outputGenericUnion(
        &allocator.allocator,
        definitions.definitions[0].@"union".generic,
    );

    testing.expectEqualStrings(output, expected_output);

    definitions.deinit();
    allocator.allocator.free(output);
    testing_utilities.expectNoLeaks(&allocator);
}

test "Union with embedded tag is output correctly" {
    var allocator = TestingAllocator{};

    const definition_buffer =
        \\struct One {
        \\    field1: String
        \\}
        \\
        \\struct Two {
        \\    field2: F32
        \\    field3: Boolean
        \\}
        \\
        \\union(tag = media_type, embedded) Embedded {
        \\    WithOne: One
        \\    WithTwo: Two
        \\    Empty
        \\}
    ;

    const expected_output =
        \\export type Embedded = WithOne | WithTwo | Empty;
        \\
        \\export enum EmbeddedTag {
        \\    WithOne = "WithOne",
        \\    WithTwo = "WithTwo",
        \\    Empty = "Empty",
        \\}
        \\
        \\export type WithOne = {
        \\    media_type: EmbeddedTag.WithOne;
        \\    field1: string;
        \\};
        \\
        \\export type WithTwo = {
        \\    media_type: EmbeddedTag.WithTwo;
        \\    field2: number;
        \\    field3: boolean;
        \\};
        \\
        \\export type Empty = {
        \\    media_type: EmbeddedTag.Empty;
        \\};
        \\
        \\export function WithOne(data: One): WithOne {
        \\    return {media_type: EmbeddedTag.WithOne, ...data};
        \\}
        \\
        \\export function WithTwo(data: Two): WithTwo {
        \\    return {media_type: EmbeddedTag.WithTwo, ...data};
        \\}
        \\
        \\export function Empty(): Empty {
        \\    return {media_type: EmbeddedTag.Empty};
        \\}
        \\
        \\export function isEmbedded(value: unknown): value is Embedded {
        \\    return [isWithOne, isWithTwo, isEmpty].some((typePredicate) => typePredicate(value));
        \\}
        \\
        \\export function isWithOne(value: unknown): value is WithOne {
        \\    return svt.isInterface<WithOne>(value, {media_type: EmbeddedTag.WithOne, field1: svt.isString});
        \\}
        \\
        \\export function isWithTwo(value: unknown): value is WithTwo {
        \\    return svt.isInterface<WithTwo>(value, {media_type: EmbeddedTag.WithTwo, field2: svt.isNumber, field3: svt.isBoolean});
        \\}
        \\
        \\export function isEmpty(value: unknown): value is Empty {
        \\    return svt.isInterface<Empty>(value, {media_type: EmbeddedTag.Empty});
        \\}
        \\
        \\export function validateEmbedded(value: unknown): svt.ValidationResult<Embedded> {
        \\    return svt.validateWithTypeTag<Embedded>(value, {[EmbeddedTag.WithOne]: validateWithOne, [EmbeddedTag.WithTwo]: validateWithTwo, [EmbeddedTag.Empty]: validateEmpty}, "media_type");
        \\}
        \\
        \\export function validateWithOne(value: unknown): svt.ValidationResult<WithOne> {
        \\    return svt.validate<WithOne>(value, {media_type: EmbeddedTag.WithOne, field1: svt.validateString});
        \\}
        \\
        \\export function validateWithTwo(value: unknown): svt.ValidationResult<WithTwo> {
        \\    return svt.validate<WithTwo>(value, {media_type: EmbeddedTag.WithTwo, field2: svt.validateNumber, field3: svt.validateBoolean});
        \\}
        \\
        \\export function validateEmpty(value: unknown): svt.ValidationResult<Empty> {
        \\    return svt.validate<Empty>(value, {media_type: EmbeddedTag.Empty});
        \\}
    ;

    var parsing_error: ParsingError = undefined;
    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        "test.gotyno",
        definition_buffer,
        null,
        &parsing_error,
    );

    const output = try typescript.outputEmbeddedUnion(
        &allocator.allocator,
        definitions.definitions[2].@"union".embedded,
    );

    testing.expectEqualStrings(output, expected_output);

    definitions.deinit();
    allocator.allocator.free(output);
    testing_utilities.expectNoLeaks(&allocator);
}

test "Union with embedded tag and lowercase constructors is output correctly" {
    var allocator = TestingAllocator{};

    const definition_buffer =
        \\struct One {
        \\    field1: String
        \\}
        \\
        \\struct Two {
        \\    field2: F32
        \\    field3: Boolean
        \\}
        \\
        \\union(tag = media_type, embedded) Embedded {
        \\    movie: One
        \\    tv: Two
        \\    Empty
        \\}
    ;

    const expected_output =
        \\export type Embedded = movie | tv | Empty;
        \\
        \\export enum EmbeddedTag {
        \\    movie = "movie",
        \\    tv = "tv",
        \\    Empty = "Empty",
        \\}
        \\
        \\export type movie = {
        \\    media_type: EmbeddedTag.movie;
        \\    field1: string;
        \\};
        \\
        \\export type tv = {
        \\    media_type: EmbeddedTag.tv;
        \\    field2: number;
        \\    field3: boolean;
        \\};
        \\
        \\export type Empty = {
        \\    media_type: EmbeddedTag.Empty;
        \\};
        \\
        \\export function movie(data: One): movie {
        \\    return {media_type: EmbeddedTag.movie, ...data};
        \\}
        \\
        \\export function tv(data: Two): tv {
        \\    return {media_type: EmbeddedTag.tv, ...data};
        \\}
        \\
        \\export function Empty(): Empty {
        \\    return {media_type: EmbeddedTag.Empty};
        \\}
        \\
        \\export function isEmbedded(value: unknown): value is Embedded {
        \\    return [isMovie, isTv, isEmpty].some((typePredicate) => typePredicate(value));
        \\}
        \\
        \\export function isMovie(value: unknown): value is movie {
        \\    return svt.isInterface<movie>(value, {media_type: EmbeddedTag.movie, field1: svt.isString});
        \\}
        \\
        \\export function isTv(value: unknown): value is tv {
        \\    return svt.isInterface<tv>(value, {media_type: EmbeddedTag.tv, field2: svt.isNumber, field3: svt.isBoolean});
        \\}
        \\
        \\export function isEmpty(value: unknown): value is Empty {
        \\    return svt.isInterface<Empty>(value, {media_type: EmbeddedTag.Empty});
        \\}
        \\
        \\export function validateEmbedded(value: unknown): svt.ValidationResult<Embedded> {
        \\    return svt.validateWithTypeTag<Embedded>(value, {[EmbeddedTag.movie]: validateMovie, [EmbeddedTag.tv]: validateTv, [EmbeddedTag.Empty]: validateEmpty}, "media_type");
        \\}
        \\
        \\export function validateMovie(value: unknown): svt.ValidationResult<movie> {
        \\    return svt.validate<movie>(value, {media_type: EmbeddedTag.movie, field1: svt.validateString});
        \\}
        \\
        \\export function validateTv(value: unknown): svt.ValidationResult<tv> {
        \\    return svt.validate<tv>(value, {media_type: EmbeddedTag.tv, field2: svt.validateNumber, field3: svt.validateBoolean});
        \\}
        \\
        \\export function validateEmpty(value: unknown): svt.ValidationResult<Empty> {
        \\    return svt.validate<Empty>(value, {media_type: EmbeddedTag.Empty});
        \\}
    ;

    var parsing_error: ParsingError = undefined;
    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        "test.gotyno",
        definition_buffer,
        null,
        &parsing_error,
    );

    const output = try typescript.outputEmbeddedUnion(
        &allocator.allocator,
        definitions.definitions[2].@"union".embedded,
    );

    testing.expectEqualStrings(output, expected_output);

    definitions.deinit();
    allocator.allocator.free(output);
    testing_utilities.expectNoLeaks(&allocator);
}

test "Imports are output correctly" {
    var allocator = TestingAllocator{};

    const definition_buffer =
        \\import other
        \\import sourceFile = importAlias
        \\
    ;

    const expected_output_1 =
        \\import * as other from "./other";
    ;

    const expected_output_2 =
        \\import * as importAlias from "./sourceFile";
    ;

    var parsing_error: ParsingError = undefined;
    var definitions = try parser.parseWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        "test.gotyno",
        definition_buffer,
        null,
        &parsing_error,
    );

    const output_1 = try typescript.outputImport(
        &allocator.allocator,
        definitions.definitions[0].import,
    );

    testing.expectEqualStrings(output_1, expected_output_1);

    const output_2 = try typescript.outputImport(
        &allocator.allocator,
        definitions.definitions[1].import,
    );

    testing.expectEqualStrings(output_2, expected_output_2);

    definitions.deinit();
    allocator.allocator.free(output_1);
    allocator.allocator.free(output_2);
    testing_utilities.expectNoLeaks(&allocator);
}

test "Parsing an imported reference works even with nested ones" {
    var allocator = TestingAllocator{};

    const module1_filename = "module1.gotyno";
    const module1_name = "module1";
    const module1_buffer =
        \\union Maybe <T>{
        \\    Nothing
        \\    Just: T
        \\}
        \\
        \\union Either <L, R>{
        \\    Left: L
        \\    Right: R
        \\}
    ;

    const module2_filename = "module2.gotyno";
    const module2_name = "module2";
    const module2_buffer =
        \\struct HoldsSomething <T>{
        \\    holdingField: T
        \\}
        \\
        \\struct PlainStruct {
        \\    normalField: String
        \\}
        \\
        \\struct Two {
        \\    fieldHolding: HoldsSomething<module1.Maybe<module1.Either<String, PlainStruct>>>
        \\}
    ;

    const buffers = [_]BufferData{
        .{ .filename = module1_filename, .buffer = module1_buffer },
        .{ .filename = module2_filename, .buffer = module2_buffer },
    };

    var parsing_error: ParsingError = undefined;

    var modules = try parser.parseModulesWithDescribedError(
        &allocator.allocator,
        &allocator.allocator,
        &buffers,
        &parsing_error,
    );

    const maybe_module1 = modules.get(module1_name);
    testing.expect(maybe_module1 != null);
    var module1 = maybe_module1.?;

    const maybe_module2 = modules.get(module2_name);
    testing.expect(maybe_module2 != null);
    var module2 = maybe_module2.?;

    const expected_two_output =
        \\export type Two = {
        \\    fieldHolding: HoldsSomething<module1.Maybe<module1.Either<string, PlainStruct>>>;
        \\};
        \\
        \\export function isTwo(value: unknown): value is Two {
        \\    return svt.isInterface<Two>(value, {fieldHolding: isHoldsSomething(module1.isMaybe(module1.isEither(svt.isString, isPlainStruct)))});
        \\}
        \\
        \\export function validateTwo(value: unknown): svt.ValidationResult<Two> {
        \\    return svt.validate<Two>(value, {fieldHolding: validateHoldsSomething(module1.validateMaybe(module1.validateEither(svt.validateString, validatePlainStruct)))});
        \\}
    ;

    const two_output = try typescript.outputPlainStructure(
        &allocator.allocator,
        module2.definitions[2].structure.plain,
    );

    testing.expectEqualStrings(expected_two_output, two_output);

    allocator.allocator.free(two_output);
    modules.deinit();
    testing_utilities.expectNoLeaks(&allocator);
}
