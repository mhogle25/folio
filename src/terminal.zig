const std = @import("std");
const posix = std.posix;
const folio = @import("folio");
const runner_mod = folio.runner;

const RenderTarget = runner_mod.RenderTarget;
const RunnerState = runner_mod.RunnerState;

// Raw syscall write to a fd. Used by signal handlers and render callbacks
// that don't have access to a std.Io context.
fn rawWrite(fd: posix.fd_t, bytes: []const u8) void {
    _ = std.os.linux.write(fd, bytes.ptr, bytes.len);
}


var global_original_termios: ?posix.termios = null;

fn sigintHandler(_: posix.SIG) callconv(.c) void {
    if (global_original_termios) |original| {
        posix.tcsetattr(posix.STDIN_FILENO, .FLUSH, original) catch {};
    }
    rawWrite(posix.STDOUT_FILENO, "\n");
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
            rawWrite(posix.STDOUT_FILENO, "\r\n");
        } else {
            rawWrite(posix.STDOUT_FILENO, &[1]u8{char});
        }
    }

    fn appendText(_: *anyopaque, text: []const u8) void {
        var remaining = text;
        while (std.mem.indexOfScalar(u8, remaining, '\n')) |idx| {
            rawWrite(posix.STDOUT_FILENO, remaining[0..idx]);
            rawWrite(posix.STDOUT_FILENO, "\r\n");
            remaining = remaining[idx + 1 ..];
        }
        if (remaining.len > 0) {
            rawWrite(posix.STDOUT_FILENO, remaining);
        }
    }

    fn clear(_: *anyopaque) void {
        rawWrite(posix.STDOUT_FILENO, "\r\n\r\n---\r\n\r\n");
    }

    fn reportError(_: *anyopaque, message: []const u8) void {
        rawWrite(posix.STDOUT_FILENO, "\r\n\x1b[31m[error] ");
        rawWrite(posix.STDOUT_FILENO, message);
        rawWrite(posix.STDOUT_FILENO, "\x1b[0m\r\n");
    }
};


pub fn printCompileErrors(errors: *const folio.programme.CompileErrors, writer: *std.Io.Writer) void {
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


pub fn runLoop(io: std.Io, folio_session: *folio.FolioSession, is_terminal: bool) void {
    var last = std.Io.Timestamp.now(io, .awake);
    var waiting_prompt_shown = false;

    while (folio_session.getState() != .done) {
        const now = std.Io.Timestamp.now(io, .awake);
        const delta_ns = last.durationTo(now).nanoseconds;
        last = now;
        const delta_ms = @as(f64, @floatFromInt(delta_ns)) / 1_000_000.0;
        _ = folio_session.advance(delta_ms);

        if (folio_session.getState() == .waiting and !waiting_prompt_shown) {
            rawWrite(posix.STDOUT_FILENO, "\r\n\u{25b6} ");
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
