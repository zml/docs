const std = @import("std");
const zine = @import("zine");

pub fn build(b: *std.Build) !void {
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    // Vendored version of https://github.com/ziglang/zig/tree/0.13.0/lib/docs/wasm
    const docs_wasm = b.addExecutable(.{
        .name = "main",
        .target = wasm_target,
        .optimize = b.standardOptimizeOption(.{}),
        .root_source_file = .{ .cwd_relative = "zig_docs/main.zig" },
    });
    docs_wasm.entry = .disabled;
    docs_wasm.rdynamic = true;
    const Walk = b.addModule("Walk", .{
        .root_source_file = .{ .cwd_relative = "zig_docs/Walk.zig" },
    });
    docs_wasm.root_module.addImport("Walk", Walk);

    zine.website(b, .{
        .title = "ZML Documentation Website",
        .host_url = "https://docs.zml.ai",
        .content_dir_path = "content",
        .layouts_dir_path = "layouts",
        .assets_dir_path = "assets",
        .static_assets = &.{
            "zml.no_light.svg",
            "zml_api.js",
            "sources.tar",
            "CNAME",
            "fonts/jbm/JetBrainsMono-Light.woff2",
            "fonts/jbm/JetBrainsMono-ThinItalic.woff2",
            "fonts/jbm/JetBrainsMono-BoldItalic.woff2",
            "fonts/jbm/JetBrainsMono-Regular.woff2",
            "fonts/jbm/JetBrainsMono-SemiBold.woff2",
            "fonts/jbm/JetBrainsMono-MediumItalic.woff2",
            "fonts/jbm/JetBrainsMono-ExtraLightItalic.woff2",
            "fonts/jbm/JetBrainsMono-Medium.woff2",
            "fonts/jbm/JetBrainsMono-LightItalic.woff2",
            "fonts/jbm/JetBrainsMono-ExtraLight.woff2",
            "fonts/jbm/JetBrainsMono-Bold.woff2",
            "fonts/jbm/JetBrainsMono-Thin.woff2",
            "fonts/jbm/JetBrainsMono-SemiBoldItalic.woff2",
            "fonts/jbm/JetBrainsMono-ExtraBoldItalic.woff2",
            "fonts/jbm/JetBrainsMono-ExtraBold.woff2",
            "fonts/jbm/JetBrainsMono-Italic.woff2",
        },
        .build_assets = &.{
            .{
                .name = "main.wasm",
                .lp = docs_wasm.getEmittedBin(),
                .install_path = "main.wasm",
                .install_always = true,
            },
        },
        .debug = true,
    });
}
