const std = @import("std");

const WORKSPACE = "WORKSPACE";
const LINK_DIRS: [4][]const u8 = .{
    "assets",
    "layouts",
    "zig_docs",
    "tools",
};

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
            try edit(arena.allocator());
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

fn clone(arena: std.mem.Allocator, args_: ?*std.process.ArgIterator) !void {
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

    if (args_) |args| {
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
    std.log.info("ZML cloned into ./zml", .{});
}

fn setup_workspace(arena: std.mem.Allocator) !void {
    if (!is_dir_present("zml")) {
        try clone(arena, null);
    }
    if (!is_dir_present(WORKSPACE)) {
        try std.fs.cwd().makeDir(WORKSPACE);
    }

    var cwd = std.fs.cwd();
    var workspace_dir = try cwd.openDir(WORKSPACE, .{});
    defer workspace_dir.close();

    if (!is_dir_present(try std.fmt.allocPrint(arena, "{s}/{s}", .{ WORKSPACE, "content" }))) {
        try workspace_dir.makeDir("content");
    }
    for (LINK_DIRS) |subpath| {
        if (!is_dir_present(try std.fmt.allocPrint(arena, "{s}/{s}", .{ WORKSPACE, subpath }))) {
            const link_dir = try std.fmt.allocPrint(arena, "../{s}", .{subpath});
            std.log.debug("{s} -> {s}", .{ subpath, link_dir });
            try workspace_dir.symLink(link_dir, subpath, .{});
        }
    }
    std.log.info("Workspace ./{s}/ created!", .{WORKSPACE});
}

fn edit(arena: std.mem.Allocator) !void {
    try setup_workspace(arena);

    //  now create the .smd files
    //  NOTE: the .smd files are the authoritative source of existence
    //        meaning: if there is no .smd file in contents, its associated
    //        `.md` file will not move into the workspace.
    //  You can use above as a feature, adding .md files that are intended only for
    //  GH browsing use, even in the content/ directory; although, I'd advise against
    //  such shenanigans
    //
    //  Note: the below is necessary to copy over .smd (only, no associated .md)
    //  files that would not be touched by processor.py because they don't need
    //  translation
    var cwd = std.fs.cwd();
    var content_src_dir = try cwd.openDir("content", .{ .iterate = true });
    defer content_src_dir.close();

    var workspace_dir = try cwd.openDir(WORKSPACE, .{});
    defer workspace_dir.close();
    var content_dest_dir = try workspace_dir.openDir("content", .{});
    defer content_dest_dir.close();

    var walker = try content_src_dir.walk(arena);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind == .directory) {
            try content_dest_dir.makePath(entry.path);
        }
        if (entry.kind == .file and std.mem.endsWith(u8, entry.path, ".smd")) {
            try content_src_dir.copyFile(entry.path, content_dest_dir, entry.path, .{});
        }
    }

    std.log.info("EDIT in ./{s}/", .{WORKSPACE});

    // python processor.py EDIT content zml/docs WORKSPACE
    switch (std.process.execv(arena, &.{ "python", "processor.py", "EDIT", "content", "zml/docs", "WORKSPACE" })) {
        else => |e| std.log.err("python: {any}", .{e}),
    }
    unreachable;
}

fn build(arena: std.mem.Allocator, args: *std.process.ArgIterator) !void {
    try setup_workspace(arena);

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

        std.log.info("File list was: {s}", .{try joinCommandLineArgs(arena, tar_args.items)});
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
    std.log.info("{s}", .{try joinCommandLineArgs(arena, zig_args.items)});
    try std.process.changeCurDir(WORKSPACE);
    switch (std.process.execv(arena, zig_args.items)) {
        else => |e| std.log.err("zig: {any}", .{e}),
    }
    unreachable;
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

fn joinCommandLineArgs(arena: std.mem.Allocator, args: [][]const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(arena);
    for (args, 0..) |arg, i| {
        try result.appendSlice(arg);
        if (i < args.len - 1) {
            try result.append(' ');
        }
    }
    return result.items;
}
