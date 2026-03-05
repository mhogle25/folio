const std = @import("std");

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
pub fn compileFile(path: []const u8, allocator: std.mem.Allocator) !programme.CompileResult {
    const source = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
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
