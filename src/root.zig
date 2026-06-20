const std = @import("std");
const lish = @import("lish");

pub const token = @import("token.zig");
pub const lexer = @import("lexer.zig");
pub const node = @import("node.zig");
pub const parser = @import("parser.zig");
pub const programme = @import("programme.zig");
pub const runner = @import("runner.zig");
pub const ops = @import("ops.zig");
pub const session = @import("session.zig");

pub const FolioSession = session.FolioSession;
pub const FolioSessionConfig = session.FolioSessionConfig;

/// Serialize folio's full vocabulary (lish core + folio runner ops) as
/// `--dump-ops` JSON to `writer`. Point lish-lsp's vocabulary at the output and
/// folio scripts get completion/hover/signature help for folio ops, with full
/// binding/scope analysis. Builds a registry directly from the op metadata (no
/// session, runner, or programme): folio ops are registered metadata-only here,
/// never executed.
pub fn dumpOps(writer: *std.Io.Writer, allocator: std.mem.Allocator) !void {
    var registry = lish.Registry.init(allocator);
    defer registry.deinit(allocator);

    try lish.builtins.registerAll(&registry, allocator);
    try ops.registerMetadataInto(&registry, allocator);

    try lish.introspect.serializeOperations(writer, &registry, allocator);
}

/// Compile a folio source string into an executable Programme.
/// Returns a `CompileResult` — call `.ok.deinit()` or `.err.deinit()` when done.
pub fn compileSource(source: []const u8, allocator: std.mem.Allocator) !programme.CompileResult {
    const tokens = try lexer.tokenize(source, allocator);
    defer allocator.free(tokens);
    var script = try parser.parse(tokens, allocator);
    defer script.deinit();
    return programme.compile(&script, allocator);
}

/// Read a file and compile it as a folio script.
/// Returns a `CompileResult` — call `.ok.deinit()` or `.err.deinit()` when done.
pub fn compileFile(io: std.Io, path: []const u8, allocator: std.mem.Allocator) !programme.CompileResult {
    const source = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1024 * 1024));
    defer allocator.free(source);
    return compileSource(source, allocator);
}

test {
    _ = token;
    _ = lexer;
    _ = node;
    _ = parser;
    _ = programme;
    _ = runner;
    _ = ops;
    _ = session;
}
