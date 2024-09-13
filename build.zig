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
            staticAsset(b, "main.wasm"),
            staticAsset(b, "main.js"),
            staticAsset(b, "sources.tar"),
        },
        .debug = true,
    });
}

fn staticAsset(b: *std.Build, name: []const u8) zine.BuildAsset {
    return .{
        .name = name,
        .lp = b.path(name),
        .install_path = name,
        .install_always = true,
    };
}
