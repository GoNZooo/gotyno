import * as svt from "simple-validation-tools";

export type Recruiter = {
    name: string;
};

export function isRecruiter(value: unknown): value is Recruiter {
    return svt.isInterface<Recruiter>(value, {name: svt.isString});
}

export function validateRecruiter(value: unknown): svt.ValidationResult<Recruiter> {
    return svt.validate<Recruiter>(value, {name: svt.validateString});
}

export type Person = {
    name: string;
    age: number;
    efficiency: number;
    on_vacation: boolean;
    hobbies: string[];
    last_fifteen_comments: string[];
    recruiter: Recruiter;
    spouse: Maybe<Person>;
};

export function isPerson(value: unknown): value is Person {
    return svt.isInterface<Person>(value, {name: svt.isString, age: svt.isNumber, efficiency: svt.isNumber, on_vacation: svt.isBoolean, hobbies: svt.arrayOf(svt.isString), last_fifteen_comments: svt.arrayOf(svt.isString), recruiter: isRecruiter, spouse: isMaybe(isPerson)});
}

export function validatePerson(value: unknown): svt.ValidationResult<Person> {
    return svt.validate<Person>(value, {name: svt.validateString, age: svt.validateNumber, efficiency: svt.validateNumber, on_vacation: svt.validateBoolean, hobbies: svt.validateArray(svt.validateString), last_fifteen_comments: svt.validateArray(svt.validateString), recruiter: validateRecruiter, spouse: validateMaybe(validatePerson)});
}

export type LogInData = {
    username: string;
    password: string;
};

export function isLogInData(value: unknown): value is LogInData {
    return svt.isInterface<LogInData>(value, {username: svt.isString, password: svt.isString});
}

export function validateLogInData(value: unknown): svt.ValidationResult<LogInData> {
    return svt.validate<LogInData>(value, {username: svt.validateString, password: svt.validateString});
}

export type UserId = {
    value: string;
};

export function isUserId(value: unknown): value is UserId {
    return svt.isInterface<UserId>(value, {value: svt.isString});
}

export function validateUserId(value: unknown): svt.ValidationResult<UserId> {
    return svt.validate<UserId>(value, {value: svt.validateString});
}

export type Channel = {
    name: string;
    private: boolean;
};

export function isChannel(value: unknown): value is Channel {
    return svt.isInterface<Channel>(value, {name: svt.isString, private: svt.isBoolean});
}

export function validateChannel(value: unknown): svt.ValidationResult<Channel> {
    return svt.validate<Channel>(value, {name: svt.validateString, private: svt.validateBoolean});
}

export type Email = {
    value: string;
};

export function isEmail(value: unknown): value is Email {
    return svt.isInterface<Email>(value, {value: svt.isString});
}

export function validateEmail(value: unknown): svt.ValidationResult<Email> {
    return svt.validate<Email>(value, {value: svt.validateString});
}

export type Event = LogIn | LogOut | JoinChannels | SetEmails;

export enum EventTag {
    LogIn = "LogIn",
    LogOut = "LogOut",
    JoinChannels = "JoinChannels",
    SetEmails = "SetEmails",
}

export type LogIn = {
    type: EventTag.LogIn;
    data: LogInData;
};

export type LogOut = {
    type: EventTag.LogOut;
    data: UserId;
};

export type JoinChannels = {
    type: EventTag.JoinChannels;
    data: Channel[];
};

export type SetEmails = {
    type: EventTag.SetEmails;
    data: Email[];
};

export function LogIn(data: LogInData): LogIn {
    return {type: EventTag.LogIn, data};
}

export function LogOut(data: UserId): LogOut {
    return {type: EventTag.LogOut, data};
}

export function JoinChannels(data: Channel[]): JoinChannels {
    return {type: EventTag.JoinChannels, data};
}

export function SetEmails(data: Email[]): SetEmails {
    return {type: EventTag.SetEmails, data};
}

export function isEvent(value: unknown): value is Event {
    return [isLogIn, isLogOut, isJoinChannels, isSetEmails].some((typePredicate) => typePredicate(value));
}

export function isLogIn(value: unknown): value is LogIn {
    return svt.isInterface<LogIn>(value, {type: EventTag.LogIn, data: isLogInData});
}

export function isLogOut(value: unknown): value is LogOut {
    return svt.isInterface<LogOut>(value, {type: EventTag.LogOut, data: isUserId});
}

export function isJoinChannels(value: unknown): value is JoinChannels {
    return svt.isInterface<JoinChannels>(value, {type: EventTag.JoinChannels, data: svt.arrayOf(isChannel)});
}

export function isSetEmails(value: unknown): value is SetEmails {
    return svt.isInterface<SetEmails>(value, {type: EventTag.SetEmails, data: svt.arrayOf(isEmail)});
}

export function validateEvent(value: unknown): svt.ValidationResult<Event> {
    return svt.validateOneOf<Event>(value, [validateLogIn, validateLogOut, validateJoinChannels, validateSetEmails]);
}

export function validateLogIn(value: unknown): svt.ValidationResult<LogIn> {
    return svt.validate<LogIn>(value, {type: EventTag.LogIn, data: validateLogInData});
}

export function validateLogOut(value: unknown): svt.ValidationResult<LogOut> {
    return svt.validate<LogOut>(value, {type: EventTag.LogOut, data: validateUserId});
}

export function validateJoinChannels(value: unknown): svt.ValidationResult<JoinChannels> {
    return svt.validate<JoinChannels>(value, {type: EventTag.JoinChannels, data: svt.validateArray(validateChannel)});
}

export function validateSetEmails(value: unknown): svt.ValidationResult<SetEmails> {
    return svt.validate<SetEmails>(value, {type: EventTag.SetEmails, data: svt.validateArray(validateEmail)});
}

export type Maybe<T> = Nothing | Just<T>;

export enum MaybeTag {
    Nothing = "Nothing",
    Just = "Just",
}

export type Nothing = {
    type: MaybeTag.Nothing;
};

export type Just<T> = {
    type: MaybeTag.Just;
    data: T;
};

export function Nothing(): Nothing {
    return {type: MaybeTag.Nothing};
}

export function Just<T>(data: T): Just<T> {
    return {type: MaybeTag.Just, data};
}

export function isMaybe<T>(isT: svt.TypePredicate<T>): svt.TypePredicate<Maybe<T>> {
    return function isMaybeT(value: unknown): value is Maybe<T> {
        return [isNothing, isJust(isT)].some((typePredicate) => typePredicate(value));
    };
}

export function isNothing(value: unknown): value is Nothing {
    return svt.isInterface<Nothing>(value, {type: MaybeTag.Nothing});
}

export function isJust<T>(isT: svt.TypePredicate<T>): svt.TypePredicate<Just<T>> {
    return function isJustT(value: unknown): value is Just<T> {
        return svt.isInterface<Just<T>>(value, {type: MaybeTag.Just, data: isT});
    };
}

export function validateMaybe<T>(validateT: svt.Validator<T>): svt.Validator<Maybe<T>> {
    return function validateMaybeT(value: unknown): svt.ValidationResult<Maybe<T>> {
        return svt.validateOneOf<Maybe<T>>(value, [validateNothing, validateJust(validateT)]);
    };
}

export function validateNothing(value: unknown): svt.ValidationResult<Nothing> {
    return svt.validate<Nothing>(value, {type: MaybeTag.Nothing});
}

export function validateJust<T>(validateT: svt.Validator<T>): svt.Validator<Just<T>> {
    return function validateJustT(value: unknown): svt.ValidationResult<Just<T>> {
        return svt.validate<Just<T>>(value, {type: MaybeTag.Just, data: validateT});
    };
}

export type Either<L, R> = Left<L> | Right<R>;

export enum EitherTag {
    Left = "Left",
    Right = "Right",
}

export type Left<L> = {
    type: EitherTag.Left;
    data: L;
};

export type Right<R> = {
    type: EitherTag.Right;
    data: R;
};

export function Left<L>(data: L): Left<L> {
    return {type: EitherTag.Left, data};
}

export function Right<R>(data: R): Right<R> {
    return {type: EitherTag.Right, data};
}

export function isEither<L, R>(isL: svt.TypePredicate<L>, isR: svt.TypePredicate<R>): svt.TypePredicate<Either<L, R>> {
    return function isEitherLR(value: unknown): value is Either<L, R> {
        return [isLeft(isL), isRight(isR)].some((typePredicate) => typePredicate(value));
    };
}

export function isLeft<L>(isL: svt.TypePredicate<L>): svt.TypePredicate<Left<L>> {
    return function isLeftL(value: unknown): value is Left<L> {
        return svt.isInterface<Left<L>>(value, {type: EitherTag.Left, data: isL});
    };
}

export function isRight<R>(isR: svt.TypePredicate<R>): svt.TypePredicate<Right<R>> {
    return function isRightR(value: unknown): value is Right<R> {
        return svt.isInterface<Right<R>>(value, {type: EitherTag.Right, data: isR});
    };
}

export function validateEither<L, R>(validateL: svt.Validator<L>, validateR: svt.Validator<R>): svt.Validator<Either<L, R>> {
    return function validateEitherLR(value: unknown): svt.ValidationResult<Either<L, R>> {
        return svt.validateOneOf<Either<L, R>>(value, [validateLeft(validateL), validateRight(validateR)]);
    };
}

export function validateLeft<L>(validateL: svt.Validator<L>): svt.Validator<Left<L>> {
    return function validateLeftL(value: unknown): svt.ValidationResult<Left<L>> {
        return svt.validate<Left<L>>(value, {type: EitherTag.Left, data: validateL});
    };
}

export function validateRight<R>(validateR: svt.Validator<R>): svt.Validator<Right<R>> {
    return function validateRightR(value: unknown): svt.ValidationResult<Right<R>> {
        return svt.validate<Right<R>>(value, {type: EitherTag.Right, data: validateR});
    };
}

export enum StillSize {
    w92 = "w92",
    w185 = "w185",
    w300 = "w300",
    h632 = "h632",
    original = "original",
}

export function isStillSize(value: unknown): value is StillSize {
    return [StillSize.w92, StillSize.w185, StillSize.w300, StillSize.h632, StillSize.original].some((v) => v === value);
}

export function validateStillSize(value: unknown): svt.ValidationResult<StillSize> {
    return svt.validateOneOf<StillSize>(value, [svt.validateConstant<StillSize.w92>(StillSize.w92), svt.validateConstant<StillSize.w185>(StillSize.w185), svt.validateConstant<StillSize.w300>(StillSize.w300), svt.validateConstant<StillSize.h632>(StillSize.h632), svt.validateConstant<StillSize.original>(StillSize.original)]);
}

export enum BackdropSize {
    w300 = "w300",
    w780 = "w780",
    w1280 = "w1280",
    original = "original",
}

export function isBackdropSize(value: unknown): value is BackdropSize {
    return [BackdropSize.w300, BackdropSize.w780, BackdropSize.w1280, BackdropSize.original].some((v) => v === value);
}

export function validateBackdropSize(value: unknown): svt.ValidationResult<BackdropSize> {
    return svt.validateOneOf<BackdropSize>(value, [svt.validateConstant<BackdropSize.w300>(BackdropSize.w300), svt.validateConstant<BackdropSize.w780>(BackdropSize.w780), svt.validateConstant<BackdropSize.w1280>(BackdropSize.w1280), svt.validateConstant<BackdropSize.original>(BackdropSize.original)]);
}

export type ImageConfigurationData = {
    base_url: string;
    secure_base_url: string;
    still_sizes: StillSize[];
    backdrop_sizes: BackdropSize[];
};

export function isImageConfigurationData(value: unknown): value is ImageConfigurationData {
    return svt.isInterface<ImageConfigurationData>(value, {base_url: svt.isString, secure_base_url: svt.isString, still_sizes: svt.arrayOf(isStillSize), backdrop_sizes: svt.arrayOf(isBackdropSize)});
}

export function validateImageConfigurationData(value: unknown): svt.ValidationResult<ImageConfigurationData> {
    return svt.validate<ImageConfigurationData>(value, {base_url: svt.validateString, secure_base_url: svt.validateString, still_sizes: svt.validateArray(validateStillSize), backdrop_sizes: svt.validateArray(validateBackdropSize)});
}

export type ConfigurationData = {
    images: ImageConfigurationData;
    change_keys: string[];
};

export function isConfigurationData(value: unknown): value is ConfigurationData {
    return svt.isInterface<ConfigurationData>(value, {images: isImageConfigurationData, change_keys: svt.arrayOf(svt.isString)});
}

export function validateConfigurationData(value: unknown): svt.ValidationResult<ConfigurationData> {
    return svt.validate<ConfigurationData>(value, {images: validateImageConfigurationData, change_keys: svt.validateArray(svt.validateString)});
}

export type KnownForMovie = {
    media_type: "movie";
    poster_path: string | null | undefined;
    id: number;
    title: string | null | undefined;
    vote_average: number;
    release_date: string | null | undefined;
    overview: string;
};

export function isKnownForMovie(value: unknown): value is KnownForMovie {
    return svt.isInterface<KnownForMovie>(value, {media_type: "movie", poster_path: svt.optional(svt.isString), id: svt.isNumber, title: svt.optional(svt.isString), vote_average: svt.isNumber, release_date: svt.optional(svt.isString), overview: svt.isString});
}

export function validateKnownForMovie(value: unknown): svt.ValidationResult<KnownForMovie> {
    return svt.validate<KnownForMovie>(value, {media_type: "movie", poster_path: svt.validateOptional(svt.validateString), id: svt.validateNumber, title: svt.validateOptional(svt.validateString), vote_average: svt.validateNumber, release_date: svt.validateOptional(svt.validateString), overview: svt.validateString});
}

export type KnownForShow = {
    media_type: "tv";
    poster_path: string | null | undefined;
    id: number;
    vote_average: number;
    overview: string;
    first_air_date: string | null | undefined;
    name: string | null | undefined;
};

export function isKnownForShow(value: unknown): value is KnownForShow {
    return svt.isInterface<KnownForShow>(value, {media_type: "tv", poster_path: svt.optional(svt.isString), id: svt.isNumber, vote_average: svt.isNumber, overview: svt.isString, first_air_date: svt.optional(svt.isString), name: svt.optional(svt.isString)});
}

export function validateKnownForShow(value: unknown): svt.ValidationResult<KnownForShow> {
    return svt.validate<KnownForShow>(value, {media_type: "tv", poster_path: svt.validateOptional(svt.validateString), id: svt.validateNumber, vote_average: svt.validateNumber, overview: svt.validateString, first_air_date: svt.validateOptional(svt.validateString), name: svt.validateOptional(svt.validateString)});
}

export type KnownFor = KnownForShow | KnownForMovie;

export function isKnownFor(value: unknown): value is KnownFor {
    return [isKnownForShow, isKnownForMovie].some((typePredicate) => typePredicate(value));
}

export function validateKnownFor(value: unknown): svt.ValidationResult<KnownFor> {
    return svt.validateOneOf<KnownFor>(value, [validateKnownForShow, validateKnownForMovie]);
}