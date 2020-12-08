const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const fs = std.fs;
const heap = std.heap;

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
) !void {
    var expect_error: ExpectError = undefined;
    const parse_result = try parser.parse(allocator, allocator, file_contents, &expect_error);
    var compilation_arena = heap.ArenaAllocator.init(allocator);
    var compilation_allocator = &compilation_arena.allocator;
    switch (parse_result) {
        .success => |success_result| {
            if (output_languages.typescript) {
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
            }
        },
    }
}

test "test runs" {
    testing.expectEqual(1 + 1, 2);
}
