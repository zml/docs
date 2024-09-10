const std = @import("std");
const zine = @import("zine");

pub fn build(b: *std.Build) !void {
    zine.website(b, .{
        .title = "ZML Documentation Website",
        .host_url = "https://docs.zml.ai",
        .content_dir_path = "content",
        .layouts_dir_path = "layouts",
        .assets_dir_path = "assets",
        .static_assets = &.{
            "zml_api.js",
            "zml.no_light.svg",
        },
        .build_assets = &.{
            .{
                .name = "main_wasm",
                .lp = b.path("../zml/bazel-bin/zml/docs.docs/main.wasm"),
                .install_path = "main.wasm",
                .install_always = true,
            },
            .{
                .name = "sources",
                .lp = b.path("../zml/bazel-bin/zml/docs.docs/sources.tar"),
                .install_path = "sources.tar",
                .install_always = true,
            },
        },
        .debug = true,
    });
}
