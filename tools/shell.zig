const std = @import("std");

pub fn is_dir_present(dirname: []const u8) bool {
    var dir: ?std.fs.Dir = std.fs.cwd().openDir(dirname, .{}) catch null;
    if (dir) |*d| {
        defer d.close();
        return true;
    }
    return false;
}

pub fn find_files(arena: std.mem.Allocator, base_path: []const u8, extension: []const u8, results: *std.ArrayList([]const u8), skip_containing: bool) !void {
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

pub fn joinCommandLineArgs(arena: std.mem.Allocator, args: [][]const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(arena);
    for (args, 0..) |arg, i| {
        try result.appendSlice(arg);
        if (i < args.len - 1) {
            try result.append(' ');
        }
    }
    return result.items;
}

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
