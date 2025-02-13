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
        if (std.ascii.eqlIgnoreCase(subcommand, "build")) {
            try build(arena.allocator(), &args);
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
    const is_bsd = try is_bsd_tar(arena);
    _ = args;

    std.log.info("BSD TAR: {}", .{is_bsd});
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
