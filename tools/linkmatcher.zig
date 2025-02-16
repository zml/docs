const std = @import("std");

const c = @cImport({
    @cDefine("PCRE2_CODE_UNIT_WIDTH", "8");
    @cInclude("pcre2.h");
});

pub const Match = struct {
    start_offset: usize,
    end_offset: usize,
    content: []const u8,
};

pub const LinkMatch = struct {
    entire_link: Match,
    link_text: Match,
    link_url: Match,
};

pub const LinkMatcher = struct {
    pub const LinkType = union(enum) {
        GH_Link: struct { re: []const u8 = "(?<!\\!)\\[([^\\]]*?)\\]\\(([^)]+)\\)" },
        GH_Img: struct { re: []const u8 = "!\\[([^\\]]*?)\\]\\(([^)]+)\\)" },
        Zine_Link: struct { re: []const u8 = "(?<!\\!)\\[([^\\]]*?)\\]\\(([^()]*(\\([^()]*\\)[^()]*)*)\\)" },
        Zine_Img: struct { re: []const u8 = "(?<=\\!)\\[([^\\]]*?)\\]\\(([^()]+(?:\\([^()]*\\)[^()]*)*)\\)" },
    };

    compiled_re: *c.pcre2_code_8,

    pub fn init(link_type: LinkType) !LinkMatcher {
        const re = blk: {
            switch (link_type) {
                inline else => |x| break :blk x.re,
            }
        };

        var error_code: c_int = undefined;
        var error_offset: usize = undefined;

        const re_ptr = c.pcre2_compile_8(
            re.ptr,
            re.len,
            c.PCRE2_DOTALL,
            &error_code,
            &error_offset,
            null,
        );
        if (re_ptr) |compiled_re| {
            return .{
                .compiled_re = compiled_re,
            };
        }
        return error.ReCompileError;
    }

    pub fn deinit(self: *LinkMatcher) void {
        c.pcre2_code_free_8(self.compiled_re);
    }

    pub fn search(self: *LinkMatcher, content: []const u8) !LinkIterator {
        return try LinkIterator.init(content, self.compiled_re);
    }
};

pub const LinkIterator = struct {
    content: []const u8,
    compiled_re: *c.pcre2_code_8,
    match_data: *c.pcre2_match_data_8,
    start_offset: usize,

    pub fn init(content: []const u8, compiled_re: *c.pcre2_code_8) !LinkIterator {
        if (c.pcre2_match_data_create_from_pattern_8(compiled_re, null)) |match_data| {
            return .{
                .content = content,
                .compiled_re = compiled_re,
                .match_data = match_data,
                .start_offset = 0,
            };
        }
        return error.OutOfMemory; // judged by pcre2 source code
    }

    pub fn deinit(self: *LinkIterator) void {
        c.pcre2_match_data_free_8(self.match_data);
    }

    pub fn next(self: *LinkIterator) ?LinkMatch {
        const rc = c.pcre2_match_8(
            self.compiled_re,
            self.content.ptr,
            self.content.len,
            self.start_offset, // start at offset 0 in the subject
            0,
            self.match_data,
            null,
        );
        if (rc == c.PCRE2_ERROR_NOMATCH) {
            return null;
        }
        if (rc < 0) {
            return null;
        }

        const ovector = c.pcre2_get_ovector_pointer_8(self.match_data);

        self.start_offset = ovector[1];
        if (self.start_offset >= self.content.len) {
            return null;
        }

        return .{
            .entire_link = .{
                .content = self.content[ovector[0]..ovector[1]],
                .start_offset = ovector[0],
                .end_offset = ovector[1],
            },
            .link_text = .{
                .content = self.content[ovector[2]..ovector[3]],
                .start_offset = ovector[2],
                .end_offset = ovector[3],
            },
            .link_url = .{
                .content = self.content[ovector[4]..ovector[5]],
                .start_offset = ovector[4],
                .end_offset = ovector[5],
            },
        };
    }
};

test LinkMatcher {
    const content =
        \\ Hello, world!
        \\ [a link](an url)!
        \\ [a second link](with an url)!
    ;
    var matcher = try LinkMatcher.init(.{ .GH_Link = .{} });
    defer matcher.deinit();

    var it = try matcher.search(content);
    defer it.deinit();

    var result = it.next();
    if (result) |match| {
        try std.testing.expectEqualStrings("[a link](an url)", match.entire_link.content);
        try std.testing.expectEqualStrings("a link", match.link_text.content);
        try std.testing.expectEqualStrings("an url", match.link_url.content);
    } else {
        return error.NoMatch;
    }

    result = it.next();
    if (result) |match| {
        try std.testing.expectEqualStrings("[a second link](with an url)", match.entire_link.content);
        try std.testing.expectEqualStrings("a second link", match.link_text.content);
        try std.testing.expectEqualStrings("with an url", match.link_url.content);
    } else {
        return error.NoMatch;
    }

    result = it.next();
    try std.testing.expectEqual(null, result);
}
