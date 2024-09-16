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
        .optimize = .Debug,
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
