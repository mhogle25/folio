const std = @import("std");
const lish = @import("lish");
const runner_mod = @import("runner.zig");
const prog_mod = @import("programme.zig");
const ops_mod = @import("ops.zig");

const Allocator = std.mem.Allocator;
const Programme = prog_mod.Programme;
const RenderTarget = runner_mod.RenderTarget;
const Runner = runner_mod.Runner;
const RunnerConfig = runner_mod.RunnerConfig;
const RunnerState = runner_mod.RunnerState;

pub const FolioSessionConfig = struct {
    /// Extra registry fragments to load after builtins (e.g. host-defined ops).
    fragments: []const lish.RegistryFragment = &.{},
    /// Scope available to all lish expressions at runtime.
    scope: *const lish.Scope = &lish.Scope.EMPTY,
    /// Typewriter speed, skip behaviour, etc.
    runner_config: RunnerConfig = .{},
};

/// A self-contained folio playback context. Heap-allocated so that the runner's
/// registry pointer and the ops' runner pointer both stay valid for its lifetime.
pub const FolioSession = struct {
    programme: *const Programme,
    registry: lish.Registry,
    runner: Runner,
    allocator: Allocator,

    /// Create a new session. The caller retains ownership of `programme` and
    /// must ensure it outlives the session. Call `deinit()` when done.
    pub fn init(
        programme: *const Programme,
        render_target: RenderTarget,
        config: FolioSessionConfig,
        allocator: Allocator,
    ) !*FolioSession {
        const self = try allocator.create(FolioSession);
        errdefer allocator.destroy(self);

        self.* = .{
            .programme = programme,
            .registry = .{},
            .runner = undefined,
            .allocator = allocator,
        };

        try lish.builtins.registerAll(&self.registry, allocator);

        for (config.fragments) |fragment| {
            try fragment(&self.registry, allocator);
        }

        // runner borrows &self.registry — stable because self is heap-allocated.
        self.runner = Runner.init(
            programme,
            &self.registry,
            config.scope,
            render_target,
            config.runner_config,
            allocator,
        );

        // ops are bound to &self.runner — also stable.
        try ops_mod.registerAll(&self.registry, &self.runner, allocator);

        return self;
    }

    pub fn deinit(self: *FolioSession) void {
        self.runner.deinit();
        self.registry.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn loadScene(self: *FolioSession, name: []const u8) bool {
        return self.runner.loadScene(name);
    }

    pub fn advance(self: *FolioSession, delta_ms: f64) RunnerState {
        return self.runner.advance(delta_ms);
    }

    pub fn confirm(self: *FolioSession) void {
        self.runner.confirm();
    }

    pub fn getState(self: *const FolioSession) RunnerState {
        return self.runner.getState();
    }
};
