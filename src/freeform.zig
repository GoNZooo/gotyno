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
    typescript: bool = false,
};

pub const CompilationTimes = struct {
    typescript: ?i128 = null,
};

pub fn compile(
    allocator: *mem.Allocator,
    filename: []const u8,
    file_contents: []const u8,
    output_languages: OutputLanguages,
    directory: fs.Dir,
    verbose: bool,
) !void {
    const out = io.getStdOut().writer();
    var compilation_times = CompilationTimes{};
    const compilation_start_time = time.nanoTimestamp();
    var compilation_arena = heap.ArenaAllocator.init(allocator);
    var compilation_allocator = &compilation_arena.allocator;

    var parsing_error: ParsingError = undefined;
    const definitions = try parser.parseWithDescribedError(
        allocator,
        allocator,
        file_contents,
        &parsing_error,
    );

    if (output_languages.typescript) {
        const typescript_start_time = time.nanoTimestamp();
        defer compilation_arena.deinit();
        const typescript_filename = try typescript.outputFilename(
            compilation_allocator,
            filename,
        );
        const typescript_output = try typescript.compileDefinitions(
            compilation_allocator,
            definitions,
        );

        try directory.writeFile(typescript_filename, typescript_output);
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
