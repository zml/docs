const std = @import("std");
const shell = @import("shell.zig");

const Action = union(enum) {
    CreateDir: []const u8,
    TranslateLink: struct {
        source_file: []const u8,
        original: []const u8,
        destination: []const u8,
    },
    MergeIntoSmd: struct {
        smd_dest: []const u8,
        smd_source: []const u8,
        md_source: []const u8,
    },
    SplitSmd: struct {
        source_file: []const u8,
        smd_dest: []const u8,
        md_dest: []const u8,
    },
    ProcessingFile: []const u8,
    IgnoreFile: struct {
        source_file: []const u8,
        reason: []const u8,
    },
    TranslateImage: struct {
        source_file: []const u8,
        original: []const u8,
        destination: []const u8,
    },
    pub fn format(
        self: Action,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .CreateDir => |a| {
                try writer.print("CreateDir{{ ", .{});
                try writer.print(".dirname=\"", .{});
                try writer.print("{s}\", ", .{a});
                try writer.print("}}", .{});
            },
            .TranslateLink => |a| {
                try writer.print("TranslateLink{{ ", .{});
                try writer.print(".source_file=\"", .{});
                try writer.print("{s}\", ", .{a.source_file});
                try writer.print(".original=\"", .{});
                try writer.print("{s}\", ", .{a.original});
                try writer.print(".destination=\"", .{});
                try writer.print("{s}\", ", .{a.destination});
                try writer.print("}}", .{});
            },
            .MergeIntoSmd => |a| {
                try writer.print("MergeIntoSmd{{ ", .{});
                try writer.print(".smd_dest=\"", .{});
                try writer.print("{s}\", ", .{a.smd_dest});
                try writer.print(".smd_source=\"", .{});
                try writer.print("{s}\", ", .{a.smd_source});
                try writer.print(".md_source=\"", .{});
                try writer.print("{s}\", ", .{a.md_source});
                try writer.print("}}", .{});
            },
            .SplitSmd => |a| {
                try writer.print("SplitSmd{{ ", .{});
                try writer.print(".source_file=\"", .{});
                try writer.print("{s}\", ", .{a.source_file});
                try writer.print(".smd_dest=\"", .{});
                try writer.print("{s}\", ", .{a.smd_dest});
                try writer.print(".md_dest=\"", .{});
                try writer.print("{s}\", ", .{a.md_dest});
                try writer.print("}}", .{});
            },
            .ProcessingFile => |a| {
                try writer.print("ProcessingFile{{ ", .{});
                try writer.print(".filename=\"", .{});
                try writer.print("{s}\", ", .{a});
                try writer.print("}}", .{});
            },
            .IgnoreFile => |a| {
                try writer.print("IgnoreFile{{ ", .{});
                try writer.print(".source_file=\"", .{});
                try writer.print("{s}\", ", .{a.source_file});
                try writer.print(".reason=\"", .{});
                try writer.print("{s}\", ", .{a.reason});
                try writer.print("}}", .{});
            },
            .TranslateImage => |a| {
                try writer.print("TranslateImage{{ ", .{});
                try writer.print(".source_file=\"", .{});
                try writer.print("{s}\", ", .{a.source_file});
                try writer.print(".original=\"", .{});
                try writer.print("{s}\", ", .{a.original});
                try writer.print(".destination=\"", .{});
                try writer.print("{s}\", ", .{a.destination});
                try writer.print("}}", .{});
            },
        }
    }
};

/// Match file from `strip_path` into `prepend_path`:
///
/// Example:
///     file         = source/dir/foo.md
///     strip_path   = source/dir
///     prepend_path = dest/dir
///     ----------------------------------
///     -> return      dest/dir/foo.md
///
/// Errors out if file is not in strip_path. Allocates.
pub fn get_matching_path(
    alloc: std.mem.Allocator,
    file_: []const u8,
    strip_path_: []const u8,
    prepend_path_: []const u8,
) ![]const u8 {
    const strip_path = shell.remove_enclosing_slashes(strip_path_);
    const file = shell.remove_enclosing_slashes(file_);
    if (!std.mem.startsWith(u8, file, strip_path)) {
        return error.FileNotInStripPath;
    }
    const prepend_path = shell.remove_enclosing_slashes(prepend_path_);
    const sub_path = shell.remove_enclosing_slashes(file[strip_path.len..]);
    return try std.fmt.allocPrint(alloc, "{s}/{s}", .{ prepend_path, sub_path });
}

test get_matching_path {
    const alloc = std.testing.allocator;
    {
        const source_file = "zml/doc/intro.md";
        const source_dir = "zml/doc/";
        const dest_dir = "WORKSPACE/content";

        const moved_file = try get_matching_path(alloc, source_file, source_dir, dest_dir);
        defer alloc.free(moved_file);
        try std.testing.expectEqualStrings("WORKSPACE/content/intro.md", moved_file);
    }
}

/// Resolve the relative link within the context of the md_root.
/// Allocates.
///
/// Used in translation of `../foo/bar.md` markdown links into absolute
/// `/foo/bar` links for zine. Note that the stripping of the extension is done
/// outside of this function.
///
/// DOES NOT WORK WITH FICTIONAL FILES!!! (i.e. is not string based but fs based)
///
/// md_root: The root directory for markdown files.
/// md_file: The path to the markdown file containing the link
/// relative_link: The relative link target contained in the markdown file.
/// returns: The resolved path of the link within md_root.
///
/// Example:
///     md_root       = zml/docs
///     md_file       = zml/docs/tutorials/foo.md
///     relative_link = ../learn/tensors.md
///     ----------------------------------------------
///     -> return       learn/tensors.md
///
fn resolve_link(
    alloc: std.mem.Allocator,
    md_root: []const u8,
    md_file: []const u8,
    relative_link: []const u8,
) ![]const u8 {
    const abs_md_root = try std.fs.cwd().realpathAlloc(alloc, md_root);
    defer alloc.free(abs_md_root);
    const abs_md_file = try std.fs.cwd().realpathAlloc(alloc, md_file);
    defer alloc.free(abs_md_file);

    const abs_md_dir = std.fs.path.dirname(abs_md_file) orelse return error.NoSuchDir;
    const rel_path = try std.fmt.allocPrint(
        alloc,
        "{s}/{s}",
        .{ abs_md_dir, relative_link },
    );
    defer alloc.free(rel_path);

    const abs_link_path = try std.fs.cwd().realpathAlloc(alloc, rel_path);
    defer alloc.free(abs_link_path);
    std.debug.assert(std.mem.startsWith(u8, abs_link_path, abs_md_root));
    std.debug.assert(abs_link_path.len > abs_md_root.len + 1);
    return try alloc.dupe(u8, abs_link_path[abs_md_root.len + 1 ..]);
}

test resolve_link {
    const alloc = std.testing.allocator;
    {
        // NOTE: this test only works if those files are present!!!
        // TODO: create temp dirs and files
        const md_root = "zml/docs";
        const md_file = "zml/docs/tutorials/getting_started.md";
        const relative_link = "../learn/concepts.md";
        const result = try resolve_link(alloc, md_root, md_file, relative_link);
        defer alloc.free(result);

        try std.testing.expectEqualStrings("learn/concepts.md", result);
    }
    // resolve_link(md_root='zml/docs',
    //              md_file='zml/docs/tutorials/getting_started.md',
    //              relative_link='../howtos/huggingface_access_token.md')
    //              -> howtos/huggingface_access_token.md
    {
        // NOTE: this test only works if those files are present!!!
        // TODO: create temp dirs and files
        const md_root = "zml/docs";
        const md_file = "zml/docs/tutorials/getting_started.md";
        const relative_link = "../howtos/huggingface_access_token.md";
        const result = try resolve_link(alloc, md_root, md_file, relative_link);
        defer alloc.free(result);

        try std.testing.expectEqualStrings("howtos/huggingface_access_token.md", result);
    }
}

/// Creates a relative link for a markdown file given the root directory, the
/// file location, and the link starting with a slash. Allocates.
///
/// Used in translation of absolute zine links `/foo/bar/baz` into relative
/// markdown links `../bar/baz.md`. Note the + '.md' is done outside of this
/// function.
///
/// Args:
///     md_root       : The root directory of all markdown files.
///     md_file       : The path to the markdown file containing the link.
///     absolute_link : The link that starts with a slash (from root).
/// Returns:
///     The resolved relative link.
///
fn create_relative_link(
    alloc: std.mem.Allocator,
    md_root: []const u8,
    md_file: []const u8,
    absolute_link: []const u8,
) ![]const u8 {
    if (absolute_link.len == 0) return error.EmptyLink;
    if (absolute_link[0] != '/') return error.LinkNotAbsolute;

    const link_path = absolute_link[1..];
    const md_file_dir = std.fs.path.dirname(md_file) orelse return error.NoSuchDir;
    const relative_path_to_root = try std.fs.path.relative(alloc, md_file_dir, md_root);
    defer alloc.free(relative_path_to_root);
    const resolved_link = try std.fs.path.join(alloc, &.{ relative_path_to_root, link_path });
    return resolved_link;
}

test create_relative_link {
    const alloc = std.testing.allocator;
    {
        // create_relative_link(md_root='WORKSPACE/content',
        //                      md_file='WORKSPACE/content/tutorials/getting_started.smd',
        //                      ansolute_link='/howtos/deploy_on_server')
        //                      -> resolved_link='../howtos/deploy_on_server'
        // NOTE: this test only works if those files are present!!!
        // TODO: create temp dirs and files
        const md_root = "WORKSPACE/content";
        const md_file = "WORKSPACE/content/tutorials/getting_started.smd";
        const absolute_link = "/howtos/deploy_on_server";
        const result = try create_relative_link(alloc, md_root, md_file, absolute_link);
        defer alloc.free(result);

        try std.testing.expectEqualStrings("../howtos/deploy_on_server", result);
        std.debug.print("create_relative_link: {s}\n", .{result});
    }
}

pub fn main() !void {
    std.debug.print("All your codebase\n", .{});
}
