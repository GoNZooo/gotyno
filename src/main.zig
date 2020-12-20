const std = @import("std");
const process = std.process;
const heap = std.heap;
const mem = std.mem;
const fs = std.fs;
const debug = std.debug;
const builtin = std.builtin;

const freeform = @import("./freeform.zig");

const ArrayList = std.ArrayList;
const StringMap = std.StringHashMap;

const OutputLanguages = freeform.OutputLanguages;

const CompilationOptions = struct {
    const Self = @This();

    inputs: []const []const u8,
    outputs: OutputLanguages,
    verbose: bool,

    pub fn fromArguments(allocator: *mem.Allocator, argument_iterator: *process.ArgIterator) !Self {
        _ = argument_iterator.skip();
        var inputs = ArrayList([]const u8).init(allocator);
        var outputs = OutputLanguages{};
        var verbose = false;

        while (argument_iterator.next(allocator)) |a| {
            if (mem.eql(u8, try a, "-ts") or mem.eql(u8, try a, "--typescript")) {
                if (argument_iterator.next(allocator)) |path| {
                    if (mem.eql(u8, try path, "=")) {
                        outputs.typescript = freeform.OutputPath.input;
                    } else {
                        outputs.typescript = freeform.OutputPath{
                            .path = try sanitizeFilename(allocator, try path),
                        };
                    }
                }
            } else if (mem.eql(u8, try a, "-v") or mem.eql(u8, try a, "--verbose")) {
                verbose = true;
            } else {
                try inputs.append(try a);
            }
        }

        if (verbose) {
            debug.print("Inputs:\n", .{});

            for (inputs.items) |input| {
                debug.print("\t{}\n", .{input});
            }

            debug.print("Outputs: {}\n", .{outputs});
        }

        return Self{ .inputs = inputs.items, .outputs = outputs, .verbose = verbose };
    }
};

const InputMap = StringMap([]const u8);

fn loadInputs(allocator: *mem.Allocator, files: []const []const u8) !InputMap {
    var input_map = InputMap.init(allocator);
    const current_directory = fs.cwd();

    for (files) |file| {
        const file_contents = try current_directory.readFileAlloc(allocator, file, 4_000_000);
        try input_map.put(file, file_contents);
    }

    return input_map;
}

fn compileInputs(
    allocator: *mem.Allocator,
    files: []const []const u8,
    output_languages: OutputLanguages,
    verbose: bool,
) !void {
    const current_directory = fs.cwd();

    for (files) |file| {
        const sanitized_filename = try sanitizeFilename(allocator, file);

        const file_contents = try current_directory.readFileAlloc(
            allocator,
            sanitized_filename,
            10_000_000,
        );

        try freeform.compile(
            allocator,
            sanitized_filename,
            file_contents,
            output_languages,
            verbose,
        );
    }
}

pub fn main() anyerror!void {
    var arguments = process.args();
    const compilation_options = try CompilationOptions.fromArguments(
        heap.page_allocator,
        &arguments,
    );

    try compileInputs(
        heap.page_allocator,
        compilation_options.inputs,
        compilation_options.outputs,
        compilation_options.verbose,
    );
}

fn sanitizeFilename(allocator: *mem.Allocator, filename: []const u8) ![]const u8 {
    return if (builtin.os.tag == .windows) filename: {
        var new_filename = try allocator.dupe(u8, mem.trimLeft(u8, filename, ".\\"));
        for (new_filename) |*character| {
            if (character.* == '\\') character.* = '/';
        }

        break :filename new_filename;
    } else filename;
}
