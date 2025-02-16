const std = @import("std");
const shell = @import("shell.zig");
const LinkMatcher = @import("linkmatcher.zig").LinkMatcher;

test {
    std.testing.refAllDecls(LinkMatcher);
}

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
        const md_root = "WORKSPACE/contents";
        const md_file = "WORKSPACE/contents/tutorials/getting_started.smdd";
        const absolute_link = "/howtos/deploy_on_server";
        const result = try create_relative_link(alloc, md_root, md_file, absolute_link);
        defer alloc.free(result);

        try std.testing.expectEqualStrings("../howtos/deploy_on_server", result);
    }
}

const ActionList = std.ArrayList(Action);

const Github2Zine = struct {
    alloc: std.mem.Allocator,
    /// GitHub docs path (*.md)
    gh_path: []const u8,
    /// Zine docs path (*.smd)
    zine_path: []const u8,
    /// WORKSPACE path
    workspace: []const u8,
    actions: ActionList,

    /// Inits an instance. Takes copies of paths. Call deinit() at the end.
    pub fn init(alloc: std.mem.Allocator, gh_path: []const u8, zine_path: []const u8, workspace_path: []const u8) !Github2Zine {
        return .{
            .alloc = alloc,
            .gh_path = try alloc.dupe(u8, gh_path),
            .zine_path = try alloc.dupe(u8, zine_path),
            .workspace = try alloc.dupe(u8, workspace_path),
            .actions = ActionList.init(alloc),
        };
    }

    pub fn deinit(self: *Github2Zine) void {
        self.alloc.free(self.gh_path);
        self.alloc.free(self.zine_path);
        self.alloc.free(self.workspace);
        self.actions.deinit();
    }

    /// Processes the entire GH docs collection.
    /// Calls process_file on all markdown files.
    /// Collects taken actions in `self.actions`.
    pub fn process(self: *Github2Zine) !void {
        var md_sources = std.ArrayList([]const u8).init(self.alloc);
        defer md_sources.deinit();

        var arena_ = std.heap.ArenaAllocator.init(self.alloc);
        defer arena_.deinit();
        const arena = arena_.allocator();

        try shell.find_files(arena, self.gh_path, ".md", &md_sources, .{});
        for (md_sources.items) |source_md| {
            try self.actions.append(.{ .ProcessingFile = source_md });
            var smd_yaml_src = try get_matching_path(arena, source_md, self.gh_path, self.zine_path);
            smd_yaml_src = try shell.change_extension(arena, smd_yaml_src, ".smd");
            if (std.mem.eql(u8, std.fs.path.basename(smd_yaml_src), "README.md")) {
                smd_yaml_src = try shell.rename_basename(arena, smd_yaml_src, "index.smd");
            }
            if (!shell.exists(smd_yaml_src)) {
                try self.actions.append(.{
                    .IgnoreFile = .{
                        .source_file = source_md,
                        .reason = "Matching .smd file does not exist",
                    },
                });
                continue;
            }
            try self.processFile(arena, source_md, smd_yaml_src);
        }
    }

    /// Processes a single file:
    ///     - rewrites links
    ///     - 'renames' to appropriate .smd
    ///     - returns both rewritten content and renamed file
    fn processFile(
        self: *Github2Zine,
        arena: std.mem.Allocator,
        md_path: []const u8,
        smd_src_path: []const u8,
    ) !void {
        const max_file_size: usize = 2048 * 1024;
        const content = try std.fs.cwd().readFileAlloc(arena, md_path, max_file_size);
        const new_md_content = try self.rewriteContent(arena, content, md_path);
        const yaml = try std.fs.cwd().readFileAlloc(arena, smd_src_path, max_file_size);
        const new_smd_content = try std.fmt.allocPrint(arena, "{s}\n{s}", .{ yaml, new_md_content });
        const content_dir = try std.fs.path.join(arena, &.{ self.workspace, "content" });

        // smd_dest_path is smd_src_path in the WORKSPACE
        const smd_dest_path = get_matching_path(arena, smd_src_path, self.zine_path, content_dir);

        // create the workspace subdirs if necessary
        const smd_dirs = std.fs.path.dirname(smd_dest_path);
        if (!shell.is_dir_present(smd_dirs)) {
            try self.actions.append(.{ .CreateDir = smd_dirs });
            try std.fs.cwd().makePath(smd_dirs);
        }

        // create workspace .smd file
        try self.actions.append(.{
            .MergeIntoSmd = .{
                .smd_dest = smd_dest_path,
                .smd_source = smd_src_path,
                .md_source = md_path,
            },
        });

        // TODO: use buffered writer
        var outfile = try std.fs.cwd().createFile(smd_dest_path, .{});
        try outfile.writeAll(new_smd_content);
        defer outfile.close();
    }

    /// Rewrites file links from GH markdown format to zine format
    fn rewriteLink(
        self: *Github2Zine,
        arena: std.mem.Allocator,
        relative_path: []const u8,
        link_text: []const u8,
        target_: []const u8,
    ) ![]const u8 {
        const original = target_;

        const target, const anchor = blk: {
            if (std.mem.indexOf(u8, target_, '#')) |anchor_pos| {
                break :blk .{ target_[0..anchor_pos], target_[anchor_pos..] };
            }
            break :blk .{ target_, "" };
        };

        const new_target = blk: {
            if (target.len > 0) {
                const resolved = try resolve_link(arena, self.gh_path, relative_path, target);
                var target_file = std.fs.path.basename(resolved);
                var target_dir = std.fs.path.dirname(resolved);

                if (std.mem.eql(u8, target_file, "README.md")) {
                    target_file = ""; // -> index.smd
                } else {
                    // strip extension
                    target_file = try shell.change_extension(arena, target_file, "");
                }

                if (target_dir.len > 0) {
                    target_dir = std.fmd.allocPrint(arena, "/{s}", .{target_dir});
                }
                break :blk try std.fmt.allocPrint(arena, "{s}/{s}{s}", .{ target_dir, target_file, anchor });
            } else {
                break :blk anchor;
            }
        };
        const link_url = try std.fmt.allocPrint(arena, "[{s}]({s})", .{ link_text, new_target });
        try self.actions.append(.{ .TranslateLink = .{
            .source_file = relative_path,
            .original = original,
            .destination = new_target,
        } });
        return link_url;
    }

    // TODO: this is temp until loris fixes zine
    fn rewriteImageLink(
        self: *Github2Zine,
        arena: std.mem.Allocator,
        relative_path: []const u8,
        img_text: []const u8,
        img_target: []const u8,
    ) ![]const u8 {
        const new_target = try std.fmt.allocPrint(arena, "[{s}]($image.url('{s}'))", .{ img_text, img_target });
        try self.actions.append(.{ .TranslateImage = .{
            .source_file = relative_path,
            .original = img_target,
            .destination = new_target,
        } });
        return new_target;
    }

    ///    - rewrites markdown links
    ///    - but ignores image links ![imgtext](imglink)
    ///    - also handles newlines in links
    fn rewriteContent(self: *Github2Zine, arena: std.mem.Allocator, markdown_content: []const u8, relative_path: []const u8) ![]const u8 {
        _ = self;
        _ = arena;
        _ = markdown_content;
        _ = relative_path;
        unreachable;
    }
};

fn help() void {
    std.debug.print(
        \\
        \\ Usage: zig build process -- EDIT|COMMIT SMD_DIR MD_DIR WORKSPACE_DIR
        \\
        \\ The first parameter (mode) defines the conversion direction:
        \\ EDIT     : creates the WORKSPACE for editing & building with zine.
        \\ COMMIT   : converts back to the GitHub representation, for committing.
        \\
        \\ Example: zig build process -- EDIT content zml/docs WORKSPACE
    );
    std.process.exit(1);
}

pub fn main() !void {
    std.debug.print("All your codebase\n", .{});
}
