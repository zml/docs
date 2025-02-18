const std = @import("std");
const shell = @import("shell.zig");
const regex = @import("regex.zig");

/// Actions taken by the text processor
/// Used for logging
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
        try std.testing.expectEqualStrings(
            "WORKSPACE/content/intro.md",
            moved_file,
        );
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

        try std.testing.expectEqualStrings(
            "howtos/huggingface_access_token.md",
            result,
        );
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
/// Example:
///     md_root       = "WORKSPACE/contents";
///     md_file       = "WORKSPACE/contents/tutorials/getting_started.smd";
///     absolute_link = "/howtos/deploy_on_server";
///     --------------------------------------------------------------------
///     -> return       ../howtos/deploy_on_server
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
    const relative_path_to_root = try std.fs.path.relative(
        alloc,
        md_file_dir,
        md_root,
    );
    defer alloc.free(relative_path_to_root);
    const resolved_link = try std.fs.path.join(
        alloc,
        &.{ relative_path_to_root, link_path },
    );
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
        const md_file = "WORKSPACE/contents/tutorials/getting_started.smd";
        const absolute_link = "/howtos/deploy_on_server";
        const result = try create_relative_link(
            alloc,
            md_root,
            md_file,
            absolute_link,
        );
        defer alloc.free(result);

        try std.testing.expectEqualStrings("../howtos/deploy_on_server", result);
    }
}

const ActionList = std.ArrayList(Action);

pub const Github2Zine = struct {
    alloc: std.mem.Allocator,
    /// GitHub docs path (*.md)
    gh_path: []const u8,
    /// Zine docs path (*.smd)
    zine_path: []const u8,
    /// WORKSPACE path
    workspace: []const u8,
    actions: ActionList,

    /// Inits an instance. Takes copies of paths. Call deinit() at the end.
    pub fn init(
        alloc: std.mem.Allocator,
        gh_path: []const u8,
        zine_path: []const u8,
        workspace_path: []const u8,
    ) !Github2Zine {
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
            if (std.mem.eql(u8, std.fs.path.basename(smd_yaml_src), "README.smd")) {
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
            // DON'T:
            // _ = arena_.reset(.retain_capacity);
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
        const smd_dest_path = try get_matching_path(arena, smd_src_path, self.zine_path, content_dir);

        // create the workspace subdirs if necessary
        const smd_dirs = std.fs.path.dirname(smd_dest_path) orelse return error.NoSuchDir;
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
        defer outfile.close();
        try outfile.writeAll(new_smd_content);
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
            if (std.mem.indexOf(u8, target_, "#")) |anchor_pos| {
                break :blk .{ target_[0..anchor_pos], target_[anchor_pos..] };
            }
            break :blk .{ target_, "" };
        };

        const new_target = blk: {
            if (target.len > 0) {
                const resolved = try resolve_link(arena, self.gh_path, relative_path, target);
                var target_file = std.fs.path.basename(resolved);
                var target_dir = std.fs.path.dirname(resolved) orelse "";

                if (std.mem.eql(u8, target_file, "README.md")) {
                    target_file = ""; // -> index.smd
                } else {
                    // strip extension
                    target_file = try shell.change_extension(arena, target_file, "");
                }

                if (target_dir.len > 0) {
                    target_dir = try std.fmt.allocPrint(arena, "/{s}", .{target_dir});
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
    fn rewriteContent(
        self: *Github2Zine,
        arena: std.mem.Allocator,
        markdown_content: []const u8,
        relative_path: []const u8,
    ) ![]const u8 {
        var link_matcher = try regex.LinkMatcher.init(.{ .GH_Link = .{} });

        const Context = struct {
            processor: *Github2Zine,
            relative_path: []const u8,
        };
        const context: Context = .{ .processor = self, .relative_path = relative_path };

        const link_cb = struct {
            fn cb(ctx: Context, alloc: std.mem.Allocator, match: regex.LinkMatch) ![]const u8 {
                // replace newlines in link_text
                const link_text = try std.mem.replaceOwned(u8, alloc, match.link_text.content, "\n", " ");
                // get link target and strip extra whitespace
                const target = std.mem.trim(u8, match.link_url.content, " \n\r\t");
                if (std.mem.startsWith(u8, target, "http")) {
                    return match.entire_link.content;
                }
                return try ctx.processor.rewriteLink(alloc, ctx.relative_path, link_text, target);
            }
        }.cb;
        const new_content = try link_matcher.replaceCtx(Context, context, arena, markdown_content, link_cb);

        const img_cb = struct {
            fn cb(ctx: Context, alloc: std.mem.Allocator, match: regex.LinkMatch) ![]const u8 {
                // replace newlines in link_text
                const link_text = try std.mem.replaceOwned(u8, alloc, match.link_text.content, "\n", " ");
                // get link target and strip extra whitespace
                const target = std.mem.trim(u8, match.link_url.content, " \n\r\t");
                return try ctx.processor.rewriteImageLink(alloc, ctx.relative_path, link_text, target);
            }
        }.cb;

        var img_matcher = try regex.LinkMatcher.init(.{ .GH_Img = .{} });
        return try img_matcher.replaceCtx(Context, context, arena, new_content, img_cb);
    }
};

test "RewriteGhContent" {
    // TODO: need to create these docs if not present, see resolveLink
    const md = "Hello [world](../learn/concepts.md)! We love [zig](https://ziglang.org)!";
    const smd = "Hello [world](/learn/concepts)! We love [zig](https://ziglang.org)!";
    const md_filn = "zml/docs/tutorials/getting_started.md";

    const alloc = std.testing.allocator;
    var arena_ = std.heap.ArenaAllocator.init(alloc);
    defer arena_.deinit();
    const arena = arena_.allocator();

    var processor = try Github2Zine.init(alloc, "zml/docs", "content", "WORKSPACE");
    defer processor.deinit();
    const replaced = try processor.rewriteContent(arena, md, md_filn);

    try std.testing.expectEqualStrings(smd, replaced);
}

pub const Zine2GH = struct {
    alloc: std.mem.Allocator,
    /// GitHub docs path (*.md)
    gh_path: []const u8,
    /// Zine docs path (*.smd)
    zine_path: []const u8,
    /// WORKSPACE path
    workspace: []const u8,
    actions: ActionList,

    imglink_checker: regex.LinkMatcher,

    /// Inits an instance. Takes copies of paths. Call deinit() at the end.
    pub fn init(alloc: std.mem.Allocator, gh_path: []const u8, zine_path: []const u8, workspace_path: []const u8) !Zine2GH {
        return .{
            .alloc = alloc,
            .gh_path = try alloc.dupe(u8, gh_path),
            .zine_path = try alloc.dupe(u8, zine_path),
            .workspace = try alloc.dupe(u8, workspace_path),
            .actions = ActionList.init(alloc),
            .imglink_checker = try regex.LinkMatcher.init(.{ .Extract_Img = .{} }),
        };
    }

    pub fn deinit(self: *Zine2GH) void {
        self.alloc.free(self.gh_path);
        self.alloc.free(self.zine_path);
        self.alloc.free(self.workspace);
        self.actions.deinit();
    }

    ///  Process the entire zine docs collection.
    ///  Calls process_file on all files.
    ///  Collects actions in `actions`.
    /// NOTE: This code expects zine_path to be sth like "content".
    pub fn process(self: *Zine2GH) !void {
        var smd_sources = std.ArrayList([]const u8).init(self.alloc);
        defer smd_sources.deinit();
        var arena_ = std.heap.ArenaAllocator.init(self.alloc);
        defer arena_.deinit();
        const arena = arena_.allocator();

        // first, scan all files we need to process
        // when we actually process, we need to make sure that a corresponding
        // zine file exists
        const workspace_content = try std.fs.path.join(arena, &.{ self.workspace, self.zine_path });
        try shell.find_files(arena, workspace_content, ".smd", &smd_sources, .{});
        for (smd_sources.items) |source_smd| {
            try self.actions.append(.{ .ProcessingFile = source_smd });

            // we split the source .SMD into its .smd and .md part
            const dest_smd_yaml = try get_matching_path(
                arena,
                source_smd,
                workspace_content,
                self.zine_path,
            );

            var dest_md = try get_matching_path(
                arena,
                source_smd,
                workspace_content,
                self.gh_path,
            );

            // override index.smd -> README.md so GH displays them as folder default
            dest_md = try shell.change_extension(arena, dest_md, ".md");
            if (std.mem.eql(u8, std.fs.path.basename(dest_smd_yaml), "index.smd")) {
                dest_md = try shell.rename_basename(arena, dest_md, "README.md");
            }

            if (!shell.exists(dest_md)) {
                //
                // intentionally left blank,
                //
                // update: further down, we only create it, if there's actual
                // content inside the .smd!
            }
            try self.processFile(arena, source_smd, dest_smd_yaml, dest_md);
            // DON'T:
            // _ = arena_.reset(.retain_capacity);
        }
    }

    /// Processes a single file:
    ///     - rewrites links
    ///     - rewrites images
    ///
    /// The input SMD file will be split into its SMD (YAML) part and MD
    /// (content) part. The md part will be written to the GH repo. The SMD
    /// part will be written to the SMD file in the docs (this) repo.
    fn processFile(
        self: *Zine2GH,
        arena: std.mem.Allocator,
        /// the SMD source file
        source_smd: []const u8,
        /// the destination for the SMD YAML part
        dest_smd_yaml: []const u8,
        /// the destination for the MD part
        dest_md: []const u8,
    ) !void {
        const max_file_size: usize = 2048 * 1024;
        const content = try std.fs.cwd().readFileAlloc(arena, source_smd, max_file_size);
        const new_content = try self.rewriteContent(arena, content, source_smd);
        const new_yaml, const new_md_content = try self.splitYamlAndContent(arena, new_content, source_smd);

        // create the smd subdirs if necessary
        const dest_smd_yaml_dir = std.fs.path.dirname(dest_smd_yaml) orelse return error.NoSuchDir;
        if (!shell.is_dir_present(dest_smd_yaml_dir)) {
            try self.actions.append(.{ .CreateDir = dest_smd_yaml_dir });
            try std.fs.cwd().makePath(dest_smd_yaml_dir);
        }

        // only if there is actual markdown content, also create the .md subdirs
        if (new_md_content.len > 0) {
            const dest_md_dir = std.fs.path.dirname(dest_md) orelse return error.NoSuchDir;
            if (!shell.is_dir_present(dest_md_dir)) {
                try self.actions.append(.{ .CreateDir = dest_md_dir });
                try std.fs.cwd().makePath(dest_md_dir);
            }
        }

        // create the target SMD and MD files
        try self.actions.append(.{
            .SplitSmd = .{
                .source_file = source_smd,
                .smd_dest = dest_smd_yaml,
                .md_dest = dest_md,
            },
        });

        // TODO: use buffered writer
        var smd_outfile = try std.fs.cwd().createFile(dest_smd_yaml, .{});
        defer smd_outfile.close();
        try smd_outfile.writeAll(new_yaml);
        if (new_md_content.len > 0) {
            var md_outfile = try std.fs.cwd().createFile(dest_md, .{});
            defer md_outfile.close();
            try md_outfile.writeAll(new_md_content);
        }
    }

    /// Rewrites file links from zine SMD format to GH Markdown format
    fn rewriteLink(
        self: *Zine2GH,
        arena: std.mem.Allocator,
        relative_path: []const u8,
        link_text: []const u8,
        target_: []const u8,
    ) ![]const u8 {
        const original = target_;

        const target, const anchor = blk: {
            if (std.mem.indexOf(u8, target_, "#")) |anchor_pos| {
                break :blk .{ target_[0..anchor_pos], target_[anchor_pos..] };
            }
            break :blk .{ target_, "" };
        };

        if (std.mem.startsWith(u8, original, "#")) {
            return try std.fmt.allocPrint(arena, "[{s}]({s})", .{ link_text, original });
        }

        if (!std.mem.startsWith(u8, target, "/") and !std.mem.startsWith(u8, target, "$image")) {
            std.log.err("Error in {s}: expected $image.url('...') or an absolute path in `{s}`!", .{ relative_path, target });
            return error.InvalidLink;
        }

        // deal with $image.url('')
        if (std.mem.startsWith(u8, target, "$image")) {
            var it = try self.imglink_checker.search(target);
            if (it.next()) |match| {
                const target_url = match.link_url;
                const link_url = try std.fmt.allocPrint(arena, "![{s}]({s})", .{ link_text, target_url.content });
                try self.actions.append(.{ .TranslateImage = .{
                    .source_file = relative_path,
                    .original = target,
                    .destination = target_url.content,
                } });
                return link_url;
            } else {
                std.log.err("Error in {s}: expected $image.url('...')  in `{s}`!", .{ relative_path, target });
                return error.InvalidLink;
            }
        }

        // deal with normal links
        const new_target = blk: {
            if (target.len > 0) {
                const workspace_content = try std.fs.path.join(arena, &.{ self.workspace, self.zine_path });
                const resolved = try create_relative_link(arena, workspace_content, relative_path, target);
                var target_file = std.fs.path.basename(resolved);
                var target_dir = std.fs.path.dirname(resolved) orelse "";

                // find the target file in zine
                // it might either be target + '.smd' or target + '/index.smd'
                // whatever we have to append, we append to target_file.
                // but instead .smd, we append .md and instead of /index.smd, we
                // append /README.md or just '/'
                const search_target = if (target[0] == '/') target[1..] else target;
                const search_smd_prefix = try std.fs.path.join(arena, &.{ workspace_content, search_target });
                const search_smd = try std.fmt.allocPrint(arena, "{s}.smd", .{search_smd_prefix});
                const search_index = try std.fmt.allocPrint(arena, "{s}/index.smd", .{search_smd_prefix});

                if (shell.exists(search_smd)) {
                    // we link to an smd file
                    target_file = try std.fmt.allocPrint(arena, "{s}.md", .{target_file});
                } else if (shell.exists(search_index)) {
                    if (target_file.len == 0 or std.mem.endsWith(u8, target_file, "/")) {
                        // link to a directory
                        // TODO:  keeping a link to the directory (.../) is probably
                        // safer than the explicit README.md stuff below
                        // GH will render README.md as dir default anyway
                        const sep = if (target_file.len == 0) "" else "/";
                        target_file = try std.fmt.allocPrint(arena, "{s}{s}README.md", .{ target_file, sep });
                    }
                    // don't care
                }

                if (target_dir.len > 0) {
                    target_dir = try std.fmt.allocPrint(arena, "{s}/", .{target_dir});
                }
                break :blk try std.fmt.allocPrint(arena, "{s}{s}{s}", .{ target_dir, target_file, anchor });
            } else {
                break :blk anchor;
            }
        };

        const link_url = std.fmt.allocPrint(arena, "[{s}]({s})", .{ link_text, new_target });
        try self.actions.append(.{ .TranslateLink = .{
            .source_file = relative_path,
            .original = original,
            .destination = new_target,
        } });
        return link_url;
    }

    fn rewriteImageLink(
        self: *Zine2GH,
        arena: std.mem.Allocator,
        relative_path: []const u8,
        img_text: []const u8,
        img_target: []const u8,
    ) ![]const u8 {
        _ = self;
        _ = arena;

        // we don't handle Markdown image links in SMD sources. They must be written
        // in [$image]() format and hence are dealt with in rewriteLink()!
        std.log.err("Error in {s}:\n    ![{s}]({s})\nThere shouldn't be any ![image](links) until zine is fixed", .{ relative_path, img_text, img_target });
        return error.InvalidLink;

        // # new_target = f"[{img_text}]($image.url('{img_target}'))"
        // # self.actions.append(TranslateImageAction(source_file=relative_path,
        // #                                         original=img_target,
        // #                                         destination=new_target))
        // # return new_target
    }

    ///    - rewrites markdown links
    ///    - but errors on image links ![imgtext](imglink) ; see above rewriteImageLink()
    ///    - also handles newlines in links
    fn rewriteContent(
        self: *Zine2GH,
        arena: std.mem.Allocator,
        markdown_content: []const u8,
        relative_path: []const u8,
    ) ![]const u8 {
        var link_matcher = try regex.LinkMatcher.init(.{ .Zine_Link = .{} });

        const Context = struct {
            processor: *Zine2GH,
            relative_path: []const u8,
        };
        const context: Context = .{ .processor = self, .relative_path = relative_path };

        const link_cb = struct {
            fn cb(ctx: Context, alloc: std.mem.Allocator, match: regex.LinkMatch) ![]const u8 {
                // replace newlines in link_text
                const link_text = try std.mem.replaceOwned(u8, alloc, match.link_text.content, "\n", " ");
                // get link target and strip extra whitespace
                const target = std.mem.trim(u8, match.link_url.content, " \n\r\t");
                if (std.mem.startsWith(u8, target, "http")) {
                    return match.entire_link.content;
                }
                return try ctx.processor.rewriteLink(alloc, ctx.relative_path, link_text, target);
            }
        }.cb;
        const new_content = try link_matcher.replaceCtx(Context, context, arena, markdown_content, link_cb);

        // TODO: make this work once it is needed. Seems like it also finds []($image) links
        // (that's probably what it's made for :lol:)
        if (false) {
            // in properly crafted .smd files, this should never find an image link
            const img_cb = struct {
                fn cb(ctx: Context, alloc: std.mem.Allocator, match: regex.LinkMatch) ![]const u8 {
                    // replace newlines in link_text
                    const img_text = try std.mem.replaceOwned(u8, alloc, match.link_text.content, "\n", " ");
                    // get image target and strip extra whitespace
                    const img_target = std.mem.trim(u8, match.link_url.content, " \n\r\t");
                    return try ctx.processor.rewriteImageLink(alloc, ctx.relative_path, img_text, img_target);
                }
            }.cb;

            var img_matcher = try regex.LinkMatcher.init(.{ .Zine_Img = .{} });
            return try img_matcher.replaceCtx(Context, context, arena, new_content, img_cb);
        }
        return new_content;
    }

    /// Takes the content, splits it into the YAML section and the content
    /// section, and then returns the two: yaml, content in a tuple
    fn splitYamlAndContent(
        _: *Zine2GH,
        arena: std.mem.Allocator,
        content: []const u8,
        smd_src_file: []const u8,
    ) !struct { []const u8, []const u8 } {
        var lines_smd = std.ArrayList([]const u8).init(arena);
        var lines_md = std.ArrayList([]const u8).init(arena);
        var seen_first_sep: bool = false;
        var seen_second_sep: bool = false;
        var line_it: std.mem.SplitIterator(u8, .scalar) = .{
            .buffer = content,
            .index = 0,
            .delimiter = '\n',
        };
        while (line_it.next()) |line| {
            if (seen_second_sep) {
                try lines_md.append(line);
            } else {
                try lines_smd.append(line);
                if (std.mem.startsWith(u8, line, "---")) {
                    if (seen_first_sep) {
                        seen_second_sep = true;
                    } else {
                        seen_first_sep = true;
                    }
                }
            }
        }

        if (lines_smd.items.len == 0) {
            std.log.err("ERROR: did not produce any YAML lines for {s}", .{smd_src_file});
            return error.ProcessingError;
        }

        const new_yaml = try std.mem.join(arena, "\n", lines_smd.items);
        const new_content = try std.mem.join(arena, "\n", lines_md.items);
        return .{ new_yaml, new_content };
    }
};

test "RewriteZineContent" {
    // TODO: need to create these docs if not present, see resolveLink

    // test with md content
    {
        const smd =
            \\---
            \\.title = "ZML Concepts",
            \\.layout = "documentation.shtml",
            \\.author = "gwenzek",
            \\.date = @date("2024-08-29"),
            \\---
            \\
            \\# ZML Concepts
            \\
            \\## Model lifecycle
            \\
            \\ZML is an inference stack that helps running Machine Learning (ML) models, and
            \\particulary Neural Networks (NN).
            \\[Multilayer perceptrons]($image.url('https://raw.githubusercontent.com/zml/zml.github.io/refs/heads/main/docs-assets/perceptron.png'))
            \\[blah](/howtos/add_weights)
        ;
        const expected_smd =
            \\---
            \\.title = "ZML Concepts",
            \\.layout = "documentation.shtml",
            \\.author = "gwenzek",
            \\.date = @date("2024-08-29"),
            \\---
        ;
        const expected_md =
            \\
            \\# ZML Concepts
            \\
            \\## Model lifecycle
            \\
            \\ZML is an inference stack that helps running Machine Learning (ML) models, and
            \\particulary Neural Networks (NN).
            \\![Multilayer perceptrons](https://raw.githubusercontent.com/zml/zml.github.io/refs/heads/main/docs-assets/perceptron.png)
            \\[blah](../howtos/add_weights.md)
        ;

        const smd_filn = "WORKSPACE/content/learn/concepts.smd";

        const alloc = std.testing.allocator;
        var arena_ = std.heap.ArenaAllocator.init(alloc);
        defer arena_.deinit();
        const arena = arena_.allocator();

        var processor = try Zine2GH.init(alloc, "zml/docs", "content", "WORKSPACE");
        defer processor.deinit();

        const new_content = try processor.rewriteContent(arena, smd, smd_filn);
        const new_yaml, const new_md_content = try processor.splitYamlAndContent(arena, new_content, smd_filn);

        try std.testing.expectEqualStrings(expected_smd, new_yaml);
        try std.testing.expectEqualStrings(expected_md, new_md_content);
    }
}
