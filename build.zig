const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lish_dep = b.dependency("lish", .{
        .target = target,
        .optimize = optimize,
    });
    const lish_mod = lish_dep.module("lish");

    const mod = b.addModule("folio", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "lish", .module = lish_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "folio",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "lish", .module = lish_mod },
                .{ .name = "folio", .module = mod },
            },
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the folio terminal player");
    run_step.dependOn(&run_cmd.step);

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Scanner corpus: enforces the shared lexical-boundary contract documented
    // in ../lish/src/scanner_corpus/. Cases come in via @embedFile so no
    // filesystem access is needed at test time, but the relative path assumes
    // lish is a sibling of folio in the same parent directory.
    const corpus_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/scanner_corpus_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "folio", .module = mod },
                .{ .name = "lish", .module = lish_mod },
            },
        }),
    });
    const run_corpus_tests = b.addRunArtifact(corpus_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_corpus_tests.step);
}
