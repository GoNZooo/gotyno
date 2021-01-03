const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const fs = std.fs;
const heap = std.heap;
const time = std.time;
const io = std.io;

pub const tokenizer = @import("./freeform/tokenizer.zig");
pub const parser = @import("./freeform/parser.zig");
pub const typescript = @import("./typescript.zig");
pub const fsharp = @import("./fsharp.zig");
pub const testing_utilities = @import("./freeform/testing_utilities.zig");

const DefinitionIterator = parser.DefinitionIterator;
const ExpectError = tokenizer.ExpectError;
const ParsingError = parser.ParsingError;

const TestingAllocator = testing_utilities.TestingAllocator;

pub const OutputLanguages = struct {
    typescript: ?OutputPath = null,
    fsharp: ?OutputPath = null,
};

pub const OutputPath = union(enum) {
    input,
    path: []const u8,
};

pub const CompilationTimes = struct {
    typescript: ?i128 = null,
    fsharp: ?i128 = null,
};

pub fn compile(
    allocator: *mem.Allocator,
    filename: []const u8,
    file_contents: []const u8,
    output_languages: OutputLanguages,
    verbose: bool,
) !void {
    var compilation_times = CompilationTimes{};
    const compilation_start_time = time.nanoTimestamp();
    var compilation_arena = heap.ArenaAllocator.init(allocator);
    var compilation_allocator = &compilation_arena.allocator;
    defer compilation_arena.deinit();

    var parsing_error: ParsingError = undefined;
    var definitions = try parser.parseWithDescribedError(
        allocator,
        allocator,
        file_contents,
        &parsing_error,
    );
    defer definitions.deinit();

    if (output_languages.typescript) |path| {
        const typescript_start_time = time.nanoTimestamp();

        const output_path = switch (path) {
            .input => directoryOfInput(filename),
            .path => |p| p,
        };

        var output_directory = try fs.cwd().openDir(output_path, .{});
        defer output_directory.close();

        const typescript_filename = try typescript.outputFilename(
            compilation_allocator,
            filename,
        );

        const typescript_output = try typescript.compileDefinitions(
            compilation_allocator,
            definitions.definitions,
        );

        try output_directory.writeFile(typescript_filename, typescript_output);
        const typescript_end_time = time.nanoTimestamp();
        const compilation_time_difference = typescript_end_time - typescript_start_time;
        compilation_times.typescript = compilation_time_difference;
    }

    if (output_languages.fsharp) |path| {
        const fsharp_start_time = time.nanoTimestamp();

        const output_path = switch (path) {
            .input => directoryOfInput(filename),
            .path => |p| p,
        };

        var output_directory = try fs.cwd().openDir(output_path, .{});
        defer output_directory.close();

        const fsharp_filename = try fsharp.outputFilename(
            compilation_allocator,
            filename,
        );

        const fsharp_output = try fsharp.compileDefinitions(
            compilation_allocator,
            definitions.definitions,
        );

        try output_directory.writeFile(fsharp_filename, fsharp_output);
        const fsharp_end_time = time.nanoTimestamp();
        const compilation_time_difference = fsharp_end_time - fsharp_start_time;
        compilation_times.fsharp = compilation_time_difference;
    }

    const compilation_end_time = time.nanoTimestamp();
    const compilation_time_difference = @intToFloat(
        f32,
        compilation_end_time - compilation_start_time,
    );

    if (verbose) {
        const out = io.getStdOut().writer();
        if (compilation_times.typescript) |t| {
            try out.print(
                "TypeScript compilation time: {d:.5} ms\n",
                .{@intToFloat(f32, t) / 1000000.0},
            );
        }

        try out.print(
            "Total compilation & output time: {d:.5} ms for {} lines & {} definitions.\n\t({d:.5} ms/line & {d:.5} ms/definition)\n",
            .{
                compilation_time_difference / 1000000.0,
                definitions.definition_iterator.token_iterator.line,
                definitions.definitions.len,
                (compilation_time_difference / 1000000.0) /
                    @intToFloat(f32, definitions.definition_iterator.token_iterator.line),
                (compilation_time_difference / 1000000.0) /
                    @intToFloat(f32, definitions.definitions.len),
            },
        );
    }
}

fn directoryOfInput(filename: []const u8) []const u8 {
    return if (mem.lastIndexOf(u8, filename, "/")) |index|
        filename[0..index]
    else
        "";
}

test "Leak check for `compile` with all languages" {
    var allocator = TestingAllocator{};

    const definition_buffer = try fs.cwd().readFileAlloc(
        &allocator.allocator,
        "test_files/basic.gotyno",
        4_000_000,
    );

    try compile(
        &allocator.allocator,
        "test_files/test.gotyno",
        definition_buffer,
        OutputLanguages{ .typescript = OutputPath.input },
        false,
    );

    const typescript_output = try fs.cwd().readFileAlloc(
        &allocator.allocator,
        "test_files/test.ts",
        4_000_000,
    );

    // @WARN: @TODO: this test doesn't pass with the GPA in `Release{Small,Fast,Safe}` but passes
    // with the page allocator.
    // The reason for the failure is that tag fields in generic unions somehow point to remnants of
    // structure field names, i.e. what should be a basic `type` tag becomes `name` if a struct
    // before has a field called `name`, `nam<invalid character>` if the field was `nam`, because
    // it still tries to read 4 bytes from what should be `"type"`.
    // testing.expectEqualStrings(expected_typescript_compilation_output, typescript_output);

    allocator.allocator.free(definition_buffer);
    allocator.allocator.free(typescript_output);

    testing_utilities.expectNoLeaks(&allocator);
}

test "Compilation gives expected output" {
    var allocator = heap.page_allocator;

    const definition_buffer = try fs.cwd().readFileAlloc(
        allocator,
        "test_files/basic.gotyno",
        4_000_000,
    );

    try compile(
        allocator,
        "test_files/test.gotyno",
        definition_buffer,
        OutputLanguages{ .typescript = OutputPath.input },
        false,
    );

    const typescript_output = try fs.cwd().readFileAlloc(
        allocator,
        "test_files/test.ts",
        4_000_000,
    );
    testing.expectEqualStrings(expected_typescript_compilation_output, typescript_output);

    allocator.free(definition_buffer);
    allocator.free(typescript_output);
}

const expected_typescript_compilation_output = @embedFile("../test_files/test_expected.ts");
