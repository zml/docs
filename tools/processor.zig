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

pub fn main() !void {
    std.debug.print("All your codebase\n", .{});
}
