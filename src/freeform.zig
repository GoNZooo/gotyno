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

const DefinitionIterator = parser.DefinitionIterator;
const ExpectError = tokenizer.ExpectError;
const ParsingError = parser.ParsingError;

pub const OutputLanguages = struct {
    typescript: ?OutputPath = null,
};

pub const OutputPath = union(enum) {
    input,
    path: []const u8,
};

pub const CompilationTimes = struct {
    typescript: ?i128 = null,
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
        defer compilation_arena.deinit();

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
            "Total compilation time: {d:.5} ms\n",
            .{compilation_time_difference / 1000000.0},
        );
    }
}

fn directoryOfInput(filename: []const u8) []const u8 {
    return if (mem.lastIndexOf(u8, filename, "/")) |index|
        filename[0..index]
    else
        "";
}

const TestingAllocator = heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 20 });

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

    allocator.allocator.free(definition_buffer);

    _ = allocator.detectLeaks();
}
