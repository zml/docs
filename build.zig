const std = @import("std");
const zine = @import("zine");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // the zine dev server needs this option!!!
    const opt_debug = b.option(bool, "debug", "zine debug, unused") orelse true;
    const include_drafts = b.option(
        bool,
        "include-drafts",
        "Include drafts in zine output",
    ) orelse false;

    const pcre2_dep = b.dependency("pcre2", .{
        .target = target,
        .optimize = optimize,
        .@"code-unit-width" = .@"8",
    });

    const docs_wasm = try buildDocsWasm(b, optimize);
    const website_step, const serve_step = try buildWebSite(b, docs_wasm, opt_debug, include_drafts);
    // has to be run with zig build website
    _ = website_step;
    // has to be run with zig build serve
    _ = serve_step;

    const tool_exe = try buildTool(b, target, optimize);
    tool_exe.linkLibrary(pcre2_dep.artifact("pcre2-8")); // for unicode 8
    b.installArtifact(tool_exe);

    //
    // TESTS
    //
    addTests(b, target, optimize, pcre2_dep);
}

/// build the WASM docs target
fn buildDocsWasm(b: *std.Build, optimize: std.builtin.OptimizeMode) !*std.Build.Step.Compile {
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    // Vendored version of https://github.com/ziglang/zig/tree/0.13.0/lib/docs/wasm
    const docs_wasm = b.addExecutable(.{
        .name = "main",
        .target = wasm_target,
        .optimize = optimize,
        .root_source_file = .{ .cwd_relative = "zig_docs/main.zig" },
    });
    docs_wasm.entry = .disabled;
    docs_wasm.rdynamic = true;
    const Walk = b.addModule("Walk", .{
        .root_source_file = .{ .cwd_relative = "zig_docs/Walk.zig" },
    });
    docs_wasm.root_module.addImport("Walk", Walk);
    return docs_wasm;
}

fn buildWebSite(b: *std.Build, docs_wasm: *std.Build.Step.Compile, debug: bool, include_drafts: bool) !struct {
    *std.Build.Step,
    *std.Build.Step,
} {
    const site: zine.Site =
        .{
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
        .debug = debug,
    };

    // Setup debug flags if the user enabled Zine debug.
    const opts: zine.ZineOptions = .{
        .optimize = if (site.debug) .Debug else .ReleaseFast,
    };

    const website_step = b.step(
        "website",
        "Builds the website",
    );
    zine.addWebsite(b, opts, website_step, site, include_drafts);

    const serve_step = b.step(
        "serve",
        "Starts the Zine development server",
    );

    const port = b.option(
        u16,
        "port",
        "port to listen on for the development server",
    ) orelse 1990;

    zine.addDevelopmentServer(b, opts, serve_step, .{
        .website_step = website_step,
        .host = "localhost",
        .port = port,
        .input_dirs = &.{
            site.layouts_dir_path,
            site.content_dir_path,
            site.assets_dir_path,
        },
    });
    return .{ website_step, serve_step };
}

/// build the Workspace Preparation tool
fn buildTool(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !*std.Build.Step.Compile {
    // text pre- and post-processor
    const exe = b.addExecutable(.{
        .name = "tool",
        .root_source_file = b.path("tools/tool.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("tool", "Run the workspace preparation tool");
    run_step.dependOn(&run_cmd.step);
    return exe;
}

fn addTests(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    pcre2_dep: *std.Build.Dependency,
) void {
    // tools/processor.zig
    const exe_test_processor = b.addTest(.{
        .root_source_file = b.path("tools/processor.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_test_processor.linkLibrary(pcre2_dep.artifact("pcre2-8")); // for unicode 8
    const run_test_processor = b.addRunArtifact(exe_test_processor);

    // tools/regex.zig
    const exe_test_regex = b.addTest(.{
        .root_source_file = b.path("tools/regex.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_test_regex.linkLibrary(pcre2_dep.artifact("pcre2-8")); // for unicode 8
    const run_test_regex = b.addRunArtifact(exe_test_regex);

    // tools/shell.zig
    const exe_test_shell = b.addTest(.{
        .root_source_file = b.path("tools/shell.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_test_shell = b.addRunArtifact(exe_test_shell);

    // tools/tool.zig
    const exe_test_tool = b.addTest(.{
        .root_source_file = b.path("tools/tool.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_test_tool = b.addRunArtifact(exe_test_tool);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_test_processor.step);
    test_step.dependOn(&run_test_regex.step);
    test_step.dependOn(&run_test_shell.step);
    test_step.dependOn(&run_test_tool.step);
}
