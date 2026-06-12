const std = @import("std");
const folio = @import("folio");
const terminal_mod = @import("terminal.zig");

const posix = std.posix;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var stdout_writer = std.Io.File.stdout().writer(io, &.{});
    var stderr_writer = std.Io.File.stderr().writer(io, &.{});
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;


    var arg_iter = init.minimal.args.iterate();
    _ = arg_iter.next(); // skip argv[0]

    const script_path = arg_iter.next() orelse {
        stderr.writeAll("usage: folio <script.folio> [--scene <name>]\n") catch {};
        std.process.exit(1);
    };
    var scene_name: []const u8 = "main";

    while (arg_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--scene")) {
            scene_name = arg_iter.next() orelse break;
        }
    }


    var compile_result = folio.compileFile(io, script_path, allocator) catch |err| {
        stderr.print("folio: error loading \"{s}\": {s}\n", .{ script_path, @errorName(err) }) catch {};
        std.process.exit(1);
    };

    var prog = switch (compile_result) {
        .ok => |p| p,
        .err => |*errors| {
            defer errors.deinit();
            terminal_mod.printCompileErrors(errors, stderr);
            std.process.exit(1);
        },
    };
    defer prog.deinit();


    var terminal_target = terminal_mod.TerminalTarget{};
    const folio_session = try folio.FolioSession.init(&prog, terminal_target.renderTarget(), .{}, allocator);
    defer folio_session.deinit();


    stdout.print("folio: playing \"{s}\" (scene: {s})\n\n", .{ script_path, scene_name }) catch {};

    if (!folio_session.loadScene(scene_name)) {
        stderr.print("folio: scene \"{s}\" not found\n", .{scene_name}) catch {};
        std.process.exit(1);
    }


    const original_termios = terminal_mod.enableRawMode() catch {
        terminal_mod.runLoop(io, folio_session, false);
        return;
    };
    defer terminal_mod.disableRawMode(original_termios);

    terminal_mod.runLoop(io, folio_session, true);

    stdout.writeAll("\r\n") catch {};
}
