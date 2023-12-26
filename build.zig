const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const cover = b.option(bool, "test-cover", "Enable code coverage") orelse false;
    const cover_out = b.option(
        []const u8,
        "test-cover-out",
        "Output directory for coverage data",
    ) orelse b.pathFromRoot("cover");

    _ = b.addModule("txtar", .{
        .source_file = .{ .path = "src/txtar.zig" },
    });

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/txtar.zig" },
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run tests");
    const run_unit_tests = b.addRunArtifact(unit_tests);

    if (cover) {
        run_unit_tests.has_side_effects = true;
        run_unit_tests.argv.insertSlice(0, &[_]std.build.RunStep.Arg{
            .{ .bytes = b.dupe("kcov") },
            .{ .bytes = b.fmt("--include-path={s}", .{b.pathFromRoot("src")}) },
            .{ .bytes = b.fmt("--strip-path={s}", .{b.pathFromRoot(".")}) },
            .{ .bytes = b.dupe(cover_out) },
        }) catch @panic("OOM");
    }

    test_step.dependOn(&run_unit_tests.step);

    const docs_step = b.step("docs", "Generate docs.");
    const install_docs = b.addInstallDirectory(.{
        .source_dir = unit_tests.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs_step.dependOn(&install_docs.step);
}
