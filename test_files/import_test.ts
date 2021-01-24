import * as svt from "simple-validation-tools";

import * as basic from "./basic";

export type StructureUsingImport = {
    event: basic.Event;
};

export function isStructureUsingImport(value: unknown): value is StructureUsingImport {
    return svt.isInterface<StructureUsingImport>(value, {event: basic.isEvent});
}

export function validateStructureUsingImport(value: unknown): svt.ValidationResult<StructureUsingImport> {
    return svt.validate<StructureUsingImport>(value, {event: basic.validateEvent});
}

export type UnionUsingImport = CoolEvent | Other;

export enum UnionUsingImportTag {
    CoolEvent = "CoolEvent",
    Other = "Other",
}

export type CoolEvent = {
    type: UnionUsingImportTag.CoolEvent;
    data: basic.Event;
};

export type Other = {
    type: UnionUsingImportTag.Other;
    data: basic.Person;
};

export function CoolEvent(data: basic.Event): CoolEvent {
    return {type: UnionUsingImportTag.CoolEvent, data};
}

export function Other(data: basic.Person): Other {
    return {type: UnionUsingImportTag.Other, data};
}

export function isUnionUsingImport(value: unknown): value is UnionUsingImport {
    return [isCoolEvent, isOther].some((typePredicate) => typePredicate(value));
}

export function isCoolEvent(value: unknown): value is CoolEvent {
    return svt.isInterface<CoolEvent>(value, {type: UnionUsingImportTag.CoolEvent, data: basic.isEvent});
}

export function isOther(value: unknown): value is Other {
    return svt.isInterface<Other>(value, {type: UnionUsingImportTag.Other, data: basic.isPerson});
}

export function validateUnionUsingImport(value: unknown): svt.ValidationResult<UnionUsingImport> {
    return svt.validateWithTypeTag<UnionUsingImport>(value, {[UnionUsingImportTag.CoolEvent]: validateCoolEvent, [UnionUsingImportTag.Other]: validateOther}, "type");
}

export function validateCoolEvent(value: unknown): svt.ValidationResult<CoolEvent> {
    return svt.validate<CoolEvent>(value, {type: UnionUsingImportTag.CoolEvent, data: basic.validateEvent});
}

export function validateOther(value: unknown): svt.ValidationResult<Other> {
    return svt.validate<Other>(value, {type: UnionUsingImportTag.Other, data: basic.validatePerson});
}