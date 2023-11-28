const std = @import("std");
const debug = std.debug;
const mem = std.mem;

const parser = @import("parser.zig");
const testing_utilities = @import("testing_utilities.zig");

const Definition = parser.Definition;
const DefinitionName = parser.DefinitionName;
const Field = parser.Field;
const Constructor = parser.Constructor;
const ConstructorWithEmbeddedTypeTag = parser.ConstructorWithEmbeddedTypeTag;
const Enumeration = parser.Enumeration;
const UntaggedUnion = parser.UntaggedUnion;
const Import = parser.Import;

pub fn expectEqualDefinitions(as: []const Definition, bs: []const Definition) void {
    const Names = struct {
        a: DefinitionName,
        b: DefinitionName,
    };

    const Fields = struct {
        a: []const Field,
        b: []const Field,
    };

    const FieldsAndNames = struct {
        names: Names,
        fields: Fields,
    };

    if (as.len == 0) {
        testing_utilities.testPanic("Definition slice `as` is zero length; invalid test\n", .{});
    }

    if (bs.len == 0) {
        testing_utilities.testPanic("Definition slice `bs` is zero length; invalid test\n", .{});
    }

    if (as.len != bs.len) {
        testing_utilities.testPanic(
            "Definition slices are different length: {} != {}\n",
            .{ as.len, bs.len },
        );
    }

    for (as, 0..) |a, i| {
        const b = bs[i];

        if (!a.isEqual(b)) {
            switch (a) {
                .structure => |structure| {
                    const fields_and_names = switch (structure) {
                        .plain => |plain| FieldsAndNames{
                            .names = Names{ .a = plain.name, .b = b.structure.plain.name },
                            .fields = Fields{ .a = plain.fields, .b = b.structure.plain.fields },
                        },
                        .generic => |generic| FieldsAndNames{
                            .names = Names{ .a = generic.name, .b = b.structure.generic.name },
                            .fields = Fields{ .a = generic.fields, .b = b.structure.generic.fields },
                        },
                    };

                    debug.print("Definition at index {} different\n", .{i});
                    if (!fields_and_names.names.a.isEqual(fields_and_names.names.b)) {
                        debug.panic(
                            "\tNames: {} != {}\n",
                            .{ fields_and_names.names.a, fields_and_names.names.b },
                        );
                    }

                    expectEqualFields(fields_and_names.fields.a, fields_and_names.fields.b);

                    switch (structure) {
                        .generic => |generic| {
                            expectEqualOpenNames(
                                generic.open_names,
                                b.structure.generic.open_names,
                            );
                        },
                        .plain => {},
                    }
                },

                .@"union" => |u| {
                    switch (u) {
                        .plain => |plain| {
                            if (!plain.name.isEqual(b.@"union".plain.name)) {
                                debug.panic(
                                    "\tNames: {} != {}\n",
                                    .{ plain.name, b.@"union".plain.name },
                                );
                            }

                            expectEqualConstructors(
                                plain.constructors,
                                b.@"union".plain.constructors,
                            );
                        },
                        .generic => |generic| {
                            if (!generic.name.isEqual(b.@"union".generic.name)) {
                                debug.print(
                                    "\tNames: {} != {}\n",
                                    .{ generic.name, b.@"union".generic.name },
                                );
                            }

                            expectEqualConstructors(
                                generic.constructors,
                                b.@"union".generic.constructors,
                            );

                            expectEqualOpenNames(generic.open_names, b.@"union".generic.open_names);
                        },
                        .embedded => |embedded| {
                            if (!embedded.name.isEqual(b.@"union".embedded.name)) {
                                debug.panic(
                                    "\tNames: {} != {}\n",
                                    .{ embedded.name, b.@"union".embedded.name },
                                );
                            }

                            expectEqualEmbeddedConstructors(
                                embedded.constructors,
                                b.@"union".embedded.constructors,
                            );

                            expectEqualOpenNames(
                                embedded.open_names,
                                b.@"union".embedded.open_names,
                            );
                        },
                    }
                },

                .enumeration => |e| {
                    expectEqualEnumerations(e, b.enumeration);
                },

                .untagged_union => |u| {
                    expectEqualUntaggedUnions(u, b.untagged_union);
                },

                .import => |import| {
                    expectEqualImports(import, b.import);
                },
            }
        }
    }
}

fn expectEqualFields(as: []const Field, bs: []const Field) void {
    if (as.len != bs.len) {
        testing_utilities.testPanic(
            "Different number of fields found: {} != {}\n",
            .{ as.len, bs.len },
        );
    }

    for (as, 0..) |a, i| {
        if (!a.isEqual(bs[i])) {
            testing_utilities.testPanic(
                "Different field at index {}:\nExpected:\n\t{}\nGot:\n\t{}\n",
                .{ i, a, bs[i] },
            );
        }
    }
}

fn expectEqualOpenNames(as: []const []const u8, bs: []const []const u8) void {
    if (as.len != bs.len) {
        testing_utilities.testPanic(
            "Different number of open names found: {} != {}\n",
            .{ as.len, bs.len },
        );
    }

    for (as, 0..) |a, i| {
        if (!mem.eql(u8, a, bs[i])) {
            testing_utilities.testPanic(
                "Different open name at index {}:\n\tExpected: {}\n\tGot: {}\n",
                .{ i, a, bs[i] },
            );
        }
    }
}

fn expectEqualConstructors(as: []const Constructor, bs: []const Constructor) void {
    if (as.len != bs.len) {
        testing_utilities.testPanic(
            "Different number of constructors found: {} != {}\n",
            .{ as.len, bs.len },
        );
    }

    for (as, 0..) |a, i| {
        const b = bs[i];
        if (!a.isEqual(b)) {
            testing_utilities.testPanic(
                "Different constructor at index {}:\n\tExpected: {}\n\tGot: {}\n",
                .{ i, a, b },
            );
        }
    }
}

fn expectEqualEmbeddedConstructors(
    as: []const ConstructorWithEmbeddedTypeTag,
    bs: []const ConstructorWithEmbeddedTypeTag,
) void {
    for (as, 0..) |a, i| {
        const b = bs[i];
        if (!a.isEqual(b)) {
            if (!mem.eql(u8, a.tag, b.tag)) {
                testing_utilities.testPanic(
                    "Embedded constructor tags do not match: {} != {}\n",
                    .{ a.tag, b.tag },
                );
            }

            if (a.parameter) |a_parameter| {
                if (b.parameter) |b_parameter| {
                    expectEqualFields(a_parameter.plain.fields, b_parameter.plain.fields);
                } else {
                    testing_utilities.testPanic(
                        "Embedded constructor {} ({}) has parameter whereas {} does not\n",
                        .{ i, a.tag, b.tag },
                    );
                }
            } else {
                if (b.parameter) {
                    testing_utilities.testPanic(
                        "Embedded constructor {} ({}) has parameter whereas {} does not\n",
                        .{ i, b.tag, a.tag },
                    );
                }
            }

            testing_utilities.testPanic(
                "Different constructor at index {}:\n\tExpected: {}\n\tGot: {}\n",
                .{ i, a, b },
            );
        }
    }
}

fn expectEqualEnumerations(a: Enumeration, b: Enumeration) void {
    if (!a.name.isEqual(b.name)) {
        testing_utilities.testPanic(
            "Enumeration names do not match: {} != {}\n",
            .{ a.name, b.name },
        );
    }

    if (a.fields.len != b.fields.len) {
        testing_utilities.testPanic(
            "Different amount of fields for enumerations: {} != {}\n",
            .{ a.fields.len, b.fields.len },
        );
    }

    for (a.fields, 0..) |field, i| {
        if (!field.isEqual(b.fields[i])) {
            debug.print("Field at index {} is different:\n", .{i});
            debug.print("\tExpected: {}\n", .{field});
            testing_utilities.testPanic("\tGot: {}\n", .{b.fields[i]});
        }
    }
}

fn expectEqualUntaggedUnions(a: UntaggedUnion, b: UntaggedUnion) void {
    if (!a.name.isEqual(b.name)) {
        testing_utilities.testPanic(
            "Untagged union names do not match: {} != {}\n",
            .{ a.name, b.name },
        );
    }

    if (a.values.len != b.values.len) {
        testing_utilities.testPanic(
            "Different amount of values for untagged unions: {} != {}\n",
            .{ a.values.len, b.values.len },
        );
    }

    for (a.values, 0..) |field, i| {
        if (!field.isEqual(b.values[i])) {
            debug.print("Value at index {} is different:\n", .{i});
            debug.print("\tExpected: {}\n", .{field});
            testing_utilities.testPanic("\tGot: {}\n", .{b.values[i]});
        }
    }
}

fn expectEqualImports(a: Import, b: Import) void {
    if (!a.name.isEqual(b.name)) {
        testing_utilities.testPanic(
            "Import names do not match: {} != {}\n",
            .{ a.name, b.name },
        );
    }

    if (!mem.eql(u8, a.alias, b.alias)) {
        testing_utilities.testPanic(
            "Import aliases do not match: {} != {}\n",
            .{ a.alias, b.alias },
        );
    }
}
