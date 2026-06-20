const std = @import("std");
const lish = @import("lish");
const runner_mod = @import("runner.zig");

const Allocator = std.mem.Allocator;
const Args = lish.Args;
const ExecError = lish.exec.ExecError;
const Operation = lish.Operation;
const Param = lish.Param;
const Registry = lish.Registry;
const Runner = runner_mod.Runner;

const on_off = [_]Param{Param.optional("$on|$off")};

const op_instant  = "instant";
const op_ffwd     = "ffwd";
const op_speed    = "speed";
const op_delay    = "delay";
const op_scene    = "scene";
const op_skip     = "skip";
const op_continue = "continue";
const op_clear    = "clear";
const op_end      = "end";

// Op metadata (signature + description) lives here once, shared by the live
// registration below (which binds each op to the runner) and the metadata-only
// registration used by `--dump-ops`, so the dumped signatures cannot drift from
// the real ops.
const meta_instant = Operation.Meta{
    .signature   = .{ .params = &on_off, .returns = "$none" },
    .description = "Toggle instant mode, or set it by truthiness.",
};
const meta_ffwd = Operation.Meta{
    .signature   = .{ .params = &on_off, .returns = "$none" },
    .description = "Toggle skip confirmation (fast-forward), or set it by truthiness.",
};
const meta_speed = Operation.Meta{
    .signature   = .{ .params = &.{Param.optional("n|name")}, .returns = "$none" },
    .description = "Set typewriter speed: chars/sec, or \"slow\"/\"normal\"/\"fast\"; no arg resets to default.",
};
const meta_delay = Operation.Meta{
    .signature   = .{ .params = &.{Param.value("ms|name")}, .returns = "$none" },
    .description = "Pause the typewriter: milliseconds, or \"short\"/\"medium\"/\"long\".",
};
const meta_scene = Operation.Meta{
    .signature   = .{ .params = &.{Param.value("name")}, .returns = "$none" },
    .description = "Jump to a named scene.",
};
const meta_skip = Operation.Meta{
    .signature   = .{ .returns = "$none" },
    .description = "Flush and advance to the next beat without waiting for confirm.",
};
const meta_continue = Operation.Meta{
    .signature   = .{ .returns = "$none" },
    .description = "Flush the current beat to waiting state without advancing.",
};
const meta_clear = Operation.Meta{
    .signature   = .{ .returns = "$none" },
    .description = "Clear the render target.",
};
const meta_end = Operation.Meta{
    .signature   = .{ .returns = "$none" },
    .description = "Immediately end the scene, bypassing remaining beats.",
};

/// Register all folio runner ops into the given registry, bound to the given runner.
pub fn registerAll(registry: *Registry, runner: *Runner, allocator: Allocator) Allocator.Error!void {
    const g = registry.group(allocator, "folio");
    try g.register(op_instant,  Operation.fromBoundFn(Runner, instantOp,  runner, meta_instant));
    try g.register(op_ffwd,     Operation.fromBoundFn(Runner, ffwdOp,     runner, meta_ffwd));
    try g.register(op_speed,    Operation.fromBoundFn(Runner, speedOp,    runner, meta_speed));
    try g.register(op_delay,    Operation.fromBoundFn(Runner, delayOp,    runner, meta_delay));
    try g.register(op_scene,    Operation.fromBoundFn(Runner, sceneOp,    runner, meta_scene));
    try g.register(op_skip,     Operation.fromBoundFn(Runner, skipOp,     runner, meta_skip));
    try g.register(op_continue, Operation.fromBoundFn(Runner, continueOp, runner, meta_continue));
    try g.register(op_clear,    Operation.fromBoundFn(Runner, clearOp,    runner, meta_clear));
    try g.register(op_end,      Operation.fromBoundFn(Runner, endOp,      runner, meta_end));
}

/// Register only the metadata for folio's ops (no runner binding), so a registry
/// can describe folio's vocabulary without standing up a live session. Used by
/// `--dump-ops` to expose folio ops to editor tooling. The registered call is a
/// no-op: these entries describe the ops, they are never executed.
pub fn registerMetadataInto(registry: *Registry, allocator: Allocator) Allocator.Error!void {
    const g = registry.group(allocator, "folio");
    try g.register(op_instant,  Operation.fromFn(metadataNoop, meta_instant));
    try g.register(op_ffwd,     Operation.fromFn(metadataNoop, meta_ffwd));
    try g.register(op_speed,    Operation.fromFn(metadataNoop, meta_speed));
    try g.register(op_delay,    Operation.fromFn(metadataNoop, meta_delay));
    try g.register(op_scene,    Operation.fromFn(metadataNoop, meta_scene));
    try g.register(op_skip,     Operation.fromFn(metadataNoop, meta_skip));
    try g.register(op_continue, Operation.fromFn(metadataNoop, meta_continue));
    try g.register(op_clear,    Operation.fromFn(metadataNoop, meta_clear));
    try g.register(op_end,      Operation.fromFn(metadataNoop, meta_end));
}

fn metadataNoop(_: Args) ExecError!?lish.Value {
    return null;
}


/// Toggle instant mode (0 args), or set it by truthiness (1 arg).
fn instantOp(self: *Runner, args: Args) ExecError!?lish.Value {
    switch (args.count()) {
        0 => self.instant_mode = !self.instant_mode,
        1 => self.instant_mode = (try args.at(0).get()) != null,
        else => return args.env.fail(.arity_mismatch, op_instant ++ " takes 0 or 1 argument"),
    }
    return null;
}

/// Toggle confirm_skips (0 args), or set it by truthiness (1 arg).
fn ffwdOp(self: *Runner, args: Args) ExecError!?lish.Value {
    switch (args.count()) {
        0 => self.config.confirm_skips = !self.config.confirm_skips,
        1 => self.config.confirm_skips = (try args.at(0).get()) != null,
        else => return args.env.fail(.arity_mismatch, op_ffwd ++ " takes 0 or 1 argument"),
    }
    return null;
}

/// Set the typewriter speed. Accepts a number (chars/sec) or one of:
///   "slow" = 30, "normal" = 60, "fast" = 120
/// With no arguments, resets to the host-configured default.
fn speedOp(self: *Runner, args: Args) ExecError!?lish.Value {
    if (args.count() == 0) {
        self.config.chars_per_sec = self.base_chars_per_sec;
        return null;
    }
    const value = try args.resolveSingle();
    switch (value) {
        .string => |str| {
            if (std.mem.eql(u8, str, "slow")) {
                self.config.chars_per_sec = 30.0;
            } else if (std.mem.eql(u8, str, "normal")) {
                self.config.chars_per_sec = 60.0;
            } else if (std.mem.eql(u8, str, "fast")) {
                self.config.chars_per_sec = 120.0;
            } else {
                return args.env.fail(.invalid_argument, op_speed ++ ": unknown constant, expected \"slow\", \"normal\", or \"fast\"");
            }
        },
        .int => |n| self.config.chars_per_sec = @floatFromInt(n),
        .float => |f| self.config.chars_per_sec = f,
        .list => return args.env.fail(.invalid_argument, op_speed ++ ": expected a number or speed constant"),
    }
    return null;
}

/// Pause the typewriter for a duration. Accepts a number (milliseconds) or one of:
///   "short" = 250, "medium" = 500, "long" = 1000
fn delayOp(self: *Runner, args: Args) ExecError!?lish.Value {
    const value = try args.resolveSingle();
    switch (value) {
        .string => |str| {
            if (std.mem.eql(u8, str, "short")) {
                self.pause_remaining = 250.0;
            } else if (std.mem.eql(u8, str, "medium")) {
                self.pause_remaining = 500.0;
            } else if (std.mem.eql(u8, str, "long")) {
                self.pause_remaining = 1000.0;
            } else {
                return args.env.fail(.invalid_argument, op_delay ++ ": unknown constant, expected \"short\", \"medium\", or \"long\"");
            }
        },
        .int => |n| self.pause_remaining = @floatFromInt(n),
        .float => |f| self.pause_remaining = f,
        .list => return args.env.fail(.invalid_argument, op_delay ++ ": expected a number or delay constant"),
    }
    return null;
}

/// Jump to a named scene.
fn sceneOp(self: *Runner, args: Args) ExecError!?lish.Value {
    var name_buf: [256]u8 = undefined;
    const name = try (try args.single()).resolveString(&name_buf);
    if (!self.loadScene(name)) {
        return args.env.fail(.invalid_argument, op_scene ++ ": unknown scene name");
    }
    return null;
}

/// Flush and immediately advance to the next beat without waiting for confirm.
fn skipOp(self: *Runner, args: Args) ExecError!?lish.Value {
    _ = args;
    self.skipBeat();
    return null;
}

/// Flush the current beat to waiting state without advancing.
fn continueOp(self: *Runner, args: Args) ExecError!?lish.Value {
    _ = args;
    self.continueBeat();
    return null;
}

/// Clear the render target.
fn clearOp(self: *Runner, args: Args) ExecError!?lish.Value {
    _ = args;
    self.render_target.clear();
    return null;
}

/// Immediately end the scene, bypassing any remaining beats.
fn endOp(self: *Runner, args: Args) ExecError!?lish.Value {
    _ = args;
    self.endScene();
    return null;
}


const testing = std.testing;

test "registerMetadataInto exposes exactly folio's ops" {
    var registry = Registry.init(testing.allocator);
    defer registry.deinit(testing.allocator);
    try registerMetadataInto(&registry, testing.allocator);

    // Every op registered live by registerAll must also be described here (they
    // share the op-name consts and meta_* values), so the dump can't omit one.
    const names = [_][]const u8{
        op_instant, op_ffwd,     op_speed, op_delay, op_scene,
        op_skip,    op_continue, op_clear, op_end,
    };
    for (names) |name| try testing.expect(registry.getOperation(name) != null);

    // And no extras: exactly these folio-category ops, nothing stray.
    var folio_count: usize = 0;
    var it = registry.operations.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.category) |category| {
            if (std.mem.eql(u8, category, "folio")) folio_count += 1;
        }
    }
    try testing.expectEqual(names.len, folio_count);
}
