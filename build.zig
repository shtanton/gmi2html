const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const strip = b.option(bool, "strip", "Set to true to strip binary") orelse false;

    const exe = b.addExecutable("gmi2html", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.strip = strip;
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
