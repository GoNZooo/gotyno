import * as svt from "simple-validation-tools";

export type Recruiter = {
    name: string;
};

export function isRecruiter(value: unknown): value is Recruiter {
    return svt.isInterface<Recruiter>(value, {name: svt.isString});
};

export function validateRecruiter(value: unknown): svt.ValidationResult<Recruiter> {
    return svt.validate<Recruiter>(value, {name: svt.validateString});
};

export type Person = {
    name: string;
    age: number;
    efficiency: number;
    on_vacation: boolean;
    hobbies: string[];
    last_fifteen_comments: string[];
    recruiter: Recruiter;
};

export function isPerson(value: unknown): value is Person {
    return svt.isInterface<Person>(value, {name: svt.isString, age: svt.isNumber, efficiency: svt.isNumber, on_vacation: svt.isBoolean, hobbies: svt.arrayOf(svt.isString), last_fifteen_comments: svt.arrayOf(svt.isString), recruiter: isRecruiter});
};

export function validatePerson(value: unknown): svt.ValidationResult<Person> {
    return svt.validate<Person>(value, {name: svt.validateString, age: svt.validateNumber, efficiency: svt.validateNumber, on_vacation: svt.validateBoolean, hobbies: svt.validateArray(svt.validateString), last_fifteen_comments: svt.validateArray(svt.validateString), recruiter: validateRecruiter});
};

export type LogInData = {
    username: string;
    password: string;
};

export function isLogInData(value: unknown): value is LogInData {
    return svt.isInterface<LogInData>(value, {username: svt.isString, password: svt.isString});
};

export function validateLogInData(value: unknown): svt.ValidationResult<LogInData> {
    return svt.validate<LogInData>(value, {username: svt.validateString, password: svt.validateString});
};

export type UserId = {
    value: string;
};

export function isUserId(value: unknown): value is UserId {
    return svt.isInterface<UserId>(value, {value: svt.isString});
};

export function validateUserId(value: unknown): svt.ValidationResult<UserId> {
    return svt.validate<UserId>(value, {value: svt.validateString});
};

export type Channel = {
    name: string;
    private: boolean;
};

export function isChannel(value: unknown): value is Channel {
    return svt.isInterface<Channel>(value, {name: svt.isString, private: svt.isBoolean});
};

export function validateChannel(value: unknown): svt.ValidationResult<Channel> {
    return svt.validate<Channel>(value, {name: svt.validateString, private: svt.validateBoolean});
};

export type Email = {
    value: string;
};

export function isEmail(value: unknown): value is Email {
    return svt.isInterface<Email>(value, {value: svt.isString});
};

export function validateEmail(value: unknown): svt.ValidationResult<Email> {
    return svt.validate<Email>(value, {value: svt.validateString});
};

export type Event = LogIn | LogOut | JoinChannels | SetEmails;

export type LogIn = {
    type: "LogIn";
    data: LogInData;
};

export type LogOut = {
    type: "LogOut";
    data: UserId;
};

export type JoinChannels = {
    type: "JoinChannels";
    data: Channel[];
};

export type SetEmails = {
    type: "SetEmails";
    data: Email[];
};

export function LogIn(data: LogInData): LogIn {
    return {type: "LogIn", data};
};

export function LogOut(data: UserId): LogOut {
    return {type: "LogOut", data};
};

export function JoinChannels(data: Channel[]): JoinChannels {
    return {type: "JoinChannels", data};
};

export function SetEmails(data: Email[]): SetEmails {
    return {type: "SetEmails", data};
};

export function isLogIn(value: unknown): value is LogIn {
    return svt.isInterface<LogIn>(value, {type: "LogIn", data: isLogInData});
};

export function isLogOut(value: unknown): value is LogOut {
    return svt.isInterface<LogOut>(value, {type: "LogOut", data: isUserId});
};

export function isJoinChannels(value: unknown): value is JoinChannels {
    return svt.isInterface<JoinChannels>(value, {type: "JoinChannels", data: svt.arrayOf(isChannel)});
};

export function isSetEmails(value: unknown): value is SetEmails {
    return svt.isInterface<SetEmails>(value, {type: "SetEmails", data: svt.arrayOf(isEmail)});
};

export function validateLogIn(value: unknown): svt.ValidationResult<LogIn> {
    return svt.validate<LogIn>(value, {type: "LogIn", data: validateLogInData});
};

export function validateLogOut(value: unknown): svt.ValidationResult<LogOut> {
    return svt.validate<LogOut>(value, {type: "LogOut", data: validateUserId});
};

export function validateJoinChannels(value: unknown): svt.ValidationResult<JoinChannels> {
    return svt.validate<JoinChannels>(value, {type: "JoinChannels", data: svt.validateArray(validateChannel)});
};

export function validateSetEmails(value: unknown): svt.ValidationResult<SetEmails> {
    return svt.validate<SetEmails>(value, {type: "SetEmails", data: svt.validateArray(validateEmail)});
};