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

pub const OutputLanguages = struct {
    typescript: bool = false,
};

pub const OutputMap = struct {
    typescript: ?[]const u8 = null,
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
    const compilation_start_time = time.nanoTimestamp();
    var compilation_arena = heap.ArenaAllocator.init(allocator);
    var compilation_allocator = &compilation_arena.allocator;

    var expect_error: ExpectError = undefined;
    const parse_result = try parser.parseWithDescribedError(
        allocator,
        allocator,
        file_contents,
        &expect_error,
    );

    switch (parse_result) {
        .success => |success_result| {
            if (output_languages.typescript) {
                const typescript_start_time = time.nanoTimestamp();
                defer compilation_arena.deinit();
                const typescript_filename = try typescript.outputFilename(
                    compilation_allocator,
                    filename,
                );
                const typescript_output = try typescript.compileDefinitions(
                    compilation_allocator,
                    success_result.definitions,
                );

                try directory.writeFile(typescript_filename, typescript_output);
                const typescript_end_time = time.nanoTimestamp();
                const compilation_time_difference = @intToFloat(
                    f32,
                    typescript_end_time - typescript_start_time,
                );
                if (verbose)
                    try out.print(
                        "TypeScript compilation time: {d:.5} ms\n",
                        .{compilation_time_difference / 1000000.0},
                    );
            }
        },
    }
    const compilation_end_time = time.nanoTimestamp();
    const compilation_time_difference = @intToFloat(
        f32,
        compilation_end_time - compilation_start_time,
    );

    if (verbose)
        try out.print(
            "Total compilation time: {d:.5} ms\n",
            .{compilation_time_difference / 1000000.0},
        );
}
