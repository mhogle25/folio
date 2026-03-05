const std = @import("std");
const posix = std.posix;
const lish = @import("lish");
const folio = @import("folio");
const terminal_mod = @import("terminal.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stderr = lish.session.fdWriter(posix.STDERR_FILENO);
    const stdout = lish.session.fdWriter(posix.STDOUT_FILENO);

    // ── Parse CLI args ──

    const argv = std.os.argv;

    if (argv.len < 2) {
        stderr.writeAll("usage: folio <script.folio> [--scene <name>]\n") catch {};
        std.process.exit(1);
    }

    const script_path = std.mem.span(argv[1]);
    var scene_name: []const u8 = "main";

    var arg_index: usize = 2;
    while (arg_index < argv.len) : (arg_index += 1) {
        const arg = std.mem.span(argv[arg_index]);
        if (std.mem.eql(u8, arg, "--scene") and arg_index + 1 < argv.len) {
            arg_index += 1;
            scene_name = std.mem.span(argv[arg_index]);
        }
    }

    // ── Load and compile script ──

    var compile_result = folio.compileFile(script_path, allocator) catch |err| {
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

    // ── Set up session ──

    var terminal_target = terminal_mod.TerminalTarget{};
    const folio_session = try folio.FolioSession.init(&prog, terminal_target.renderTarget(), .{}, allocator);
    defer folio_session.deinit();

    // ── Load initial scene ──

    stdout.print("folio: playing \"{s}\" (scene: {s})\n\n", .{ script_path, scene_name }) catch {};

    if (!folio_session.loadScene(scene_name)) {
        stderr.print("folio: scene \"{s}\" not found\n", .{scene_name}) catch {};
        std.process.exit(1);
    }

    // ── Enable raw mode ──

    const original_termios = terminal_mod.enableRawMode() catch {
        terminal_mod.runLoop(folio_session, false);
        return;
    };
    defer terminal_mod.disableRawMode(original_termios);

    terminal_mod.runLoop(folio_session, true);

    _ = posix.write(posix.STDOUT_FILENO, "\r\n") catch 0;
}
