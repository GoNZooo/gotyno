import * as svt from "simple-validation-tools";

export type Recruiter = {
    type: "Recruiter";
    name: string;
};

export const isRecruiter = (value: unknown): value is Recruiter => {
    return svt.isInterface<Recruiter>(value, {type: "Recruiter", name: svt.isString});
};

export const validateRecruiter = (value: unknown): svt.ValidationResult<Recruiter> => {
    return svt.validate<Recruiter>(value, {type: "Recruiter", name: svt.validateString});
};

export type Person = {
    type: "Person";
    name: string;
    age: number;
    efficiency: number;
    on_vacation: boolean;
    hobbies: string[];
    last_fifteen_comments: string[];
    recruiter: Recruiter;
};

export const isPerson = (value: unknown): value is Person => {
    return svt.isInterface<Person>(value, {type: "Person", name: svt.isString, age: svt.isNumber, efficiency: svt.isNumber, on_vacation: svt.isBoolean, hobbies: svt.arrayOf(svt.isString), last_fifteen_comments: svt.arrayOf(svt.isString), recruiter: isRecruiter});
};

export const validatePerson = (value: unknown): svt.ValidationResult<Person> => {
    return svt.validate<Person>(value, {type: "Person", name: svt.validateString, age: svt.validateNumber, efficiency: svt.validateNumber, on_vacation: svt.validateBoolean, hobbies: svt.validateArray(svt.validateString), last_fifteen_comments: svt.validateArray(svt.validateString), recruiter: validateRecruiter});
};

export type LogInData = {
    type: "LogInData";
    username: string;
    password: string;
};

export const isLogInData = (value: unknown): value is LogInData => {
    return svt.isInterface<LogInData>(value, {type: "LogInData", username: svt.isString, password: svt.isString});
};

export const validateLogInData = (value: unknown): svt.ValidationResult<LogInData> => {
    return svt.validate<LogInData>(value, {type: "LogInData", username: svt.validateString, password: svt.validateString});
};

export type UserId = {
    type: "UserId";
    value: string;
};

export const isUserId = (value: unknown): value is UserId => {
    return svt.isInterface<UserId>(value, {type: "UserId", value: svt.isString});
};

export const validateUserId = (value: unknown): svt.ValidationResult<UserId> => {
    return svt.validate<UserId>(value, {type: "UserId", value: svt.validateString});
};

export type Channel = {
    type: "Channel";
    name: string;
    private: boolean;
};

export const isChannel = (value: unknown): value is Channel => {
    return svt.isInterface<Channel>(value, {type: "Channel", name: svt.isString, private: svt.isBoolean});
};

export const validateChannel = (value: unknown): svt.ValidationResult<Channel> => {
    return svt.validate<Channel>(value, {type: "Channel", name: svt.validateString, private: svt.validateBoolean});
};

export type Email = {
    type: "Email";
    value: string;
};

export const isEmail = (value: unknown): value is Email => {
    return svt.isInterface<Email>(value, {type: "Email", value: svt.isString});
};

export const validateEmail = (value: unknown): svt.ValidationResult<Email> => {
    return svt.validate<Email>(value, {type: "Email", value: svt.validateString});
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

export const isLogIn = (value: unknown): value is LogIn => {
    return svt.isInterface<LogIn>(value, {type: "LogIn", data: isLogInData});
};

export const isLogOut = (value: unknown): value is LogOut => {
    return svt.isInterface<LogOut>(value, {type: "LogOut", data: isUserId});
};

export const isJoinChannels = (value: unknown): value is JoinChannels => {
    return svt.isInterface<JoinChannels>(value, {type: "JoinChannels", data: svt.arrayOf(isChannel)});
};

export const isSetEmails = (value: unknown): value is SetEmails => {
    return svt.isInterface<SetEmails>(value, {type: "SetEmails", data: svt.arrayOf(isEmail)});
};

export const validateLogIn = (value: unknown): svt.ValidationResult<LogIn> => {
    return svt.validate<LogIn>(value, {type: "LogIn", data: validateLogInData});
};

export const validateLogOut = (value: unknown): svt.ValidationResult<LogOut> => {
    return svt.validate<LogOut>(value, {type: "LogOut", data: validateUserId});
};

export const validateJoinChannels = (value: unknown): svt.ValidationResult<JoinChannels> => {
    return svt.validate<JoinChannels>(value, {type: "JoinChannels", data: svt.validateArray(validateChannel)});
};

export const validateSetEmails = (value: unknown): svt.ValidationResult<SetEmails> => {
    return svt.validate<SetEmails>(value, {type: "SetEmails", data: svt.validateArray(validateEmail)});
};