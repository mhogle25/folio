const std = @import("std");
const posix = std.posix;
const folio = @import("folio");
const runner_mod = folio.runner;

const RenderTarget = runner_mod.RenderTarget;
const RunnerState = runner_mod.RunnerState;

// ── Raw mode ──

var global_original_termios: ?posix.termios = null;

fn sigintHandler(_: c_int) callconv(.c) void {
    if (global_original_termios) |original| {
        posix.tcsetattr(posix.STDIN_FILENO, .FLUSH, original) catch {};
    }
    _ = posix.write(posix.STDOUT_FILENO, "\n") catch 0;
    std.process.exit(130);
}

pub fn enableRawMode() !posix.termios {
    const original = try posix.tcgetattr(posix.STDIN_FILENO);
    global_original_termios = original;

    const act = posix.Sigaction{
        .handler = .{ .handler = &sigintHandler },
        .mask = posix.sigemptyset(),
        .flags = 0,
    };
    posix.sigaction(posix.SIG.INT, &act, null);

    var raw = original;
    raw.iflag.ICRNL = false;
    raw.iflag.IXON = false;
    raw.oflag.OPOST = false;
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.lflag.ISIG = false;
    raw.lflag.IEXTEN = false;
    // Non-blocking reads
    raw.cc[@intFromEnum(posix.V.MIN)] = 0;
    raw.cc[@intFromEnum(posix.V.TIME)] = 0;

    try posix.tcsetattr(posix.STDIN_FILENO, .FLUSH, raw);
    return original;
}

pub fn disableRawMode(original: posix.termios) void {
    posix.tcsetattr(posix.STDIN_FILENO, .FLUSH, original) catch {};
    global_original_termios = null;
}

// ── TerminalTarget ──

pub const TerminalTarget = struct {
    pub fn renderTarget(self: *TerminalTarget) RenderTarget {
        return .{ .context = self, .vtable = &vtable };
    }

    const vtable = RenderTarget.Vtable{
        .appendChar = appendChar,
        .appendText = appendText,
        .clear = clear,
        .reportError = reportError,
    };

    fn appendChar(_: *anyopaque, char: u8) void {
        if (char == '\n') {
            _ = posix.write(posix.STDOUT_FILENO, "\r\n") catch 0;
        } else {
            _ = posix.write(posix.STDOUT_FILENO, &[1]u8{char}) catch 0;
        }
    }

    fn appendText(_: *anyopaque, text: []const u8) void {
        var remaining = text;
        while (std.mem.indexOfScalar(u8, remaining, '\n')) |idx| {
            _ = posix.write(posix.STDOUT_FILENO, remaining[0..idx]) catch 0;
            _ = posix.write(posix.STDOUT_FILENO, "\r\n") catch 0;
            remaining = remaining[idx + 1 ..];
        }
        if (remaining.len > 0) {
            _ = posix.write(posix.STDOUT_FILENO, remaining) catch 0;
        }
    }

    fn clear(_: *anyopaque) void {
        _ = posix.write(posix.STDOUT_FILENO, "\r\n\r\n---\r\n\r\n") catch 0;
    }

    fn reportError(_: *anyopaque, message: []const u8) void {
        _ = posix.write(posix.STDOUT_FILENO, "\r\n\x1b[31m[error] ") catch 0;
        _ = posix.write(posix.STDOUT_FILENO, message) catch 0;
        _ = posix.write(posix.STDOUT_FILENO, "\x1b[0m\r\n") catch 0;
    }
};

// ── Compile error display ──

pub fn printCompileErrors(errors: *const folio.programme.CompileErrors, writer: std.io.AnyWriter) void {
    for (errors.items) |node_err| {
        for (node_err.errors) |script_err| {
            writer.print("folio: [{s} beat {d} node {d}] {s}\n", .{
                node_err.scene,
                node_err.beat_index,
                node_err.node_index,
                script_err.message,
            }) catch {};
        }
    }
}

// ── Run loop ──

pub fn runLoop(folio_session: *folio.FolioSession, is_terminal: bool) void {
    var timer = std.time.Timer.start() catch return;
    var waiting_prompt_shown = false;

    while (folio_session.getState() != .done) {
        const delta_ns = timer.lap();
        const delta_ms = @as(f64, @floatFromInt(delta_ns)) / 1_000_000.0;
        _ = folio_session.advance(delta_ms);

        if (folio_session.getState() == .waiting and !waiting_prompt_shown) {
            _ = posix.write(posix.STDOUT_FILENO, "\r\n\u{25b6} ") catch 0;
            waiting_prompt_shown = true;
        }

        if (!is_terminal) {
            if (folio_session.getState() == .waiting) {
                waiting_prompt_shown = false;
                folio_session.confirm();
            }
            continue;
        }

        var fds = [1]posix.pollfd{.{
            .fd = posix.STDIN_FILENO,
            .events = posix.POLL.IN,
            .revents = 0,
        }};
        _ = posix.poll(&fds, 16) catch continue;
        if (fds[0].revents & posix.POLL.IN == 0) continue;

        var byte: u8 = undefined;
        const n = posix.read(posix.STDIN_FILENO, (&byte)[0..1]) catch break;
        if (n == 0) continue;

        switch (byte) {
            '\r', ' ' => {
                if (folio_session.getState() == .waiting) {
                    waiting_prompt_shown = false;
                    folio_session.confirm();
                } else if (folio_session.getState() == .emitting) {
                    folio_session.confirm();
                }
            },
            'q', 0x03 => break,
            else => {},
        }
    }
}
