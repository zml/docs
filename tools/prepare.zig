const std = @import("std");

const WORKSPACE = "WORKSPACE";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    var args = std.process.args();
    _ = args.next();

    if (args.next()) |subcommand| {
        if (std.ascii.eqlIgnoreCase(subcommand, "clone")) {
            try clone(arena.allocator(), &args);
        }
        if (std.ascii.eqlIgnoreCase(subcommand, "help")) {
            help();
        }
        if (std.ascii.eqlIgnoreCase(subcommand, "edit")) {
            return error.NotImplemented;
        }
        if (std.ascii.eqlIgnoreCase(subcommand, "build")) {
            try build(arena.allocator(), &args);
        }
        if (std.ascii.eqlIgnoreCase(subcommand, "commit")) {
            return error.NotImplemented;
        }
    } else {
        help();
    }
}

fn help() void {
    const msg =
        \\Usage: zig build prepare -- command [opts]
        \\ 
        \\Commands in order:
        \\-1: help               : prints this help message
        \\ 0: clone [gitref]     : clones zml and optionally checks out gitref
        \\ 1: edit               : creates and prepares the WORKSPACE for editing
        \\ 2: build [serve ...]  : builds the (edited) website and optionally runs the dev server
        \\ 3: commit             : prepares the WORKSPACE for committing
    ;
    std.debug.print("{s}\n", .{msg});
}

fn is_dir_present(dirname: []const u8) bool {
    var dir: ?std.fs.Dir = std.fs.cwd().openDir(dirname, .{}) catch null;
    if (dir) |*d| {
        defer d.close();
        return true;
    }
    return false;
}

fn clone(arena: std.mem.Allocator, args: *std.process.ArgIterator) !void {
    if (is_dir_present("zml")) {
        std.log.err("zml dir is present, cannot clone!", .{});
        return error.ZmlDirPresent;
    }

    const result = try std.process.Child.run(.{
        .allocator = arena,
        .argv = &.{ "git", "clone", "git@github.com:zml/zml.git", "zml" },
    });
    if (result.term.Exited != 0) {
        std.log.err("git clone zml returned: {d}", .{result.term.Exited});
        return error.NonzeroExit;
    }

    if (args.next()) |branch| {
        const result2 = try std.process.Child.run(.{
            .allocator = arena,
            .argv = &.{ "git", "-C", "zml", "checkout", branch },
        });
        if (result2.term.Exited != 0) {
            std.log.err("git checkout >{s}< returned: {d}", .{ branch, result2.term.Exited });
            return error.NonzeroExit;
        }
    }
}

fn setup_workspace() !void {
    if (!is_dir_present(WORKSPACE)) {
        try std.fs.cwd().makeDir(WORKSPACE);
    }
}

fn build(arena: std.mem.Allocator, args: *std.process.ArgIterator) !void {
    try setup_workspace();

    // tar $MAC_TAR_DISABLE_STUFF_FLAG -cf sources.tar zml/*.zig zml/**/*.zig
    var tar_args = std.ArrayList([]const u8).init(arena);
    try tar_args.append("tar");
    if (try is_bsd_tar(arena)) {
        try tar_args.append("--no-mac-metadata");
    }
    try tar_args.appendSlice(&.{ "-cf", "../WORKSPACE/assets/sources.tar" });
    try find_files(arena, "zml", ".zig", &tar_args, true);
    const result = try std.process.Child.run(.{
        .allocator = arena,
        .cwd = "zml",
        .argv = tar_args.items,
    });
    if (result.term.Exited != 0) {
        std.log.err("tar returned: {d}", .{result.term.Exited});
        std.log.warn("{s}", .{result.stdout});
        std.log.err("{s}", .{result.stderr});

        std.log.info("File list was: {s}", .{tar_args.items});
        return error.NonzeroExit;
    }

    // cp -v ./build.zig* WORKSPACE/
    var workspace_dir = try std.fs.cwd().openDir(WORKSPACE, .{});
    defer workspace_dir.close();
    try std.fs.cwd().copyFile("build.zig", workspace_dir, "build.zig", .{});
    try std.fs.cwd().copyFile("build.zig.zon", workspace_dir, "build.zig.zon", .{});

    // cd WORKSPACE
    // echo "Starting Zine build..."
    // zig build website $@
    std.log.info("Starting Zine build...", .{});
    var zig_args = std.ArrayList([]const u8).init(arena);
    try zig_args.appendSlice(&.{ "zig", "build", "website" });
    while (args.next()) |arg| {
        try zig_args.append(arg);
    }
    std.log.info("{s}", .{zig_args.items});
    try std.process.changeCurDir(WORKSPACE);
    switch (std.process.execv(arena, zig_args.items)) {
        else => |e| std.log.err("zig: {any}", .{e}),
    }
}

fn is_bsd_tar(arena: std.mem.Allocator) !bool {
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

fn find_files(arena: std.mem.Allocator, base_path: []const u8, extension: []const u8, results: *std.ArrayList([]const u8), skip_containing: bool) !void {
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
