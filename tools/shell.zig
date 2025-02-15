const std = @import("std");

pub fn is_dir_present(dirname: []const u8) bool {
    var dir: ?std.fs.Dir = std.fs.cwd().openDir(dirname, .{}) catch null;
    if (dir) |*d| {
        defer d.close();
        return true;
    }
    return false;
}

/// Walks directory `base_path`, and inserts all files ending in `extension` into
/// the passed-in `results` ArrayList. If `skip_containing` is true, the containing
/// `base_path` will be omitted from paths inserted into the results.
/// Caller is expected to pass in an arena for simplicity. The arena is only used
/// in `skip_containing` mode, to dupe the file paths being inserted into `results`.
pub fn find_files(
    arena: std.mem.Allocator,
    base_path: []const u8,
    extension: []const u8,
    results: *std.ArrayList([]const u8),
    skip_containing: bool,
) !void {
    var base_dir = try std.fs.cwd().openDir(base_path, .{ .iterate = true });
    defer base_dir.close();

    var walker = try base_dir.walk(arena);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.path, extension)) {
            if (skip_containing) {
                try results.append(try arena.dupe(u8, entry.path));
            } else {
                const full_path =
                    try std.fs.path.join(arena, &.{ base_path, entry.path });
                try results.append(full_path);
            }
        }
    }
}

/// Turns a list of strings into a string of concatenated elements separated by
/// opts.separator. For simplicity, it's recommended to use with an arena. Yet
/// it plays nice with normal allocators, too.
pub fn joinArgs(
    arena: std.mem.Allocator,
    args: [][]const u8,
    opts: struct { separator: u8 = ' ' },
) ![]const u8 {
    var result = std.ArrayList(u8).init(arena);
    defer result.deinit();
    for (args, 0..) |arg, i| {
        try result.appendSlice(arg);
        if (i < args.len - 1) {
            try result.append(opts.separator);
        }
    }
    return result.toOwnedSlice();
}

/// Returns whether system's tar is a macos variant.
/// This is necessary if you want to pass macos-specific params to tar, like
/// for ignoring .DS_Store and other shit.
pub fn is_bsd_tar(arena: std.mem.Allocator) !bool {
    const result = try std.process.Child.run(.{
        .allocator = arena,
        .argv = &.{ "tar", "--version" },
    });
    if (result.term.Exited != 0) {
        std.log.err("tar returned: {d}", .{result.term.Exited});
        return error.NonzeroExit;
    }

    if (std.mem.indexOf(u8, result.stdout, "bsdtar")) |_| {
        return true;
    }
    return false;
}

/// Returns whether `file` ends in extension `ext`.
pub fn has_extension(file: []const u8, ext: []const u8) bool {
    // TODO: wouldn't a a simple .endsWith() be enough?
    const file_ext = std.fs.path.extension(file);
    return std.mem.eql(u8, file_ext, ext);
}

/// Changes the extension of file to `new_ext`. Allocates in all cases.
pub fn change_extension(
    alloc: std.mem.Allocator,
    file: []const u8,
    new_ext: []const u8,
) ![]const u8 {
    const index = std.mem.lastIndexOfScalar(u8, file, '.') orelse file.len;
    return std.fmt.allocPrint(alloc, "{s}{s}", .{ file[0..index], new_ext });
}

test change_extension {
    const alloc = std.testing.allocator;
    {
        const f1 = "hello.md";
        const r1 = try change_extension(alloc, f1, ".smd");
        defer alloc.free(r1);
        try std.testing.expectEqualStrings("hello.smd", r1);
    }
    {
        const f1 = "hello";
        const r1 = try change_extension(alloc, f1, ".smd");
        defer alloc.free(r1);
        try std.testing.expectEqualStrings("hello.smd", r1);
    }
}

pub fn rename_basename(alloc: std.mem.Allocator, path: []const u8, new_name: []const u8) ![]const u8 {
    if (std.fs.path.dirname(path)) |dirname| {
        return try std.fmt.allocPrint(alloc, "{s}/{s}", .{ dirname, new_name });
    }
    return alloc.dupe(new_name); // contract says retval must be freed
}

/// Remove preceding and terminating slashes if present.
/// No allocation, returns subslice of original.
pub fn remove_enclosing_slashes(path: []const u8) []const u8 {
    if (path.len == 0) return path;
    const start_index: usize = if (path[0] == '/') 1 else 0;
    const end_index: usize = if (path[path.len - 1] == '/') path.len - 1 else path.len;
    return path[start_index..end_index];
}

test remove_enclosing_slashes {
    {
        const input = "/foo/bar/";
        const output = remove_enclosing_slashes(input);
        try std.testing.expectEqualStrings("foo/bar", output);
    }
    {
        const input = "foo/bar/";
        const output = remove_enclosing_slashes(input);
        try std.testing.expectEqualStrings("foo/bar", output);
    }
    {
        const input = "foo/bar";
        const output = remove_enclosing_slashes(input);
        try std.testing.expectEqualStrings("foo/bar", output);
    }
}
