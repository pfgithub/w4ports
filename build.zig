const std = @import("std");
const builtin = @import("builtin");

// try WAMR (wasm micro runtime)
// supports jit execution

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // eventually we can do this @ runtime w/ tcc & dyn linking
    const elf = b.addSystemCommand(&.{
        "vendor/wasm2c/bin/wasm2c",
        "vendor/plctfarmer.wasm",
        "-o", "artifact/game.c",
    });

    const obj = b.addExecutable(.{
        .name = "w4ports",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    obj.linkLibC();
    obj.addIncludePath("vendor/wasm2c/include");
    obj.addIncludePath("artifact");
    obj.addCSourceFiles(&.{
        "artifact/game.c",
    }, &.{});
    obj.linkSystemLibrary("raylib");
    //obj.emit_h = true;

    obj.step.dependOn(&elf.step);
    //b.default_step.dependOn(&obj.step);
    b.installArtifact(obj);

    const run_cmd = b.addRunArtifact(obj);
    run_cmd.step.dependOn(b.getInstallStep());
    if(b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run");
    run_step.dependOn(&run_cmd.step);
}
