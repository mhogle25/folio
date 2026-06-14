//! Runs the shared scanner-boundary corpus against folio's scanBraceContent.
//!
//! Cases come from `lish.scanner_corpus` — same shared contract every embedder
//! consumes. folio only knows about the `}` terminator (its job is finding
//! lish-inline region boundaries inside sigil regions like `{...}`). The `|`
//! cases are exercised by lish-zig's own test runner against the same module.
//!
//! scanBraceContent now delegates to `lish.findExpressionBoundary`, so this is
//! an integration smoke test that folio drives the shared function correctly
//! (region wrapping, content trimming, position advance) rather than a check of
//! independent boundary logic.

const std = @import("std");
const folio = @import("folio");
const lish = @import("lish");

test "scanner corpus: every `}` case matches folio's scanBraceContent" {
    const allocator = std.testing.allocator;
    var brace_count: usize = 0;

    for (lish.scanner_corpus.cases) |case| {
        const parsed = try lish.scanner_corpus.parse(case.text);
        if (parsed.terminator != '}') continue;
        brace_count += 1;

        // Synthesize a folio source where the case body lives inside a sigil
        // region. The leading scene header is required so folio's lexer accepts
        // the input; `{` opens the lish_inline that scanBraceContent will scan.
        const prefix = "::main\n{";
        var synth: std.ArrayList(u8) = .empty;
        defer synth.deinit(allocator);
        try synth.appendSlice(allocator, prefix);
        try synth.appendSlice(allocator, parsed.source);

        const tokens = try folio.lexer.tokenize(synth.items, allocator);
        defer allocator.free(tokens);

        try std.testing.expect(tokens.len >= 2);
        try std.testing.expectEqual(folio.token.TokenType.lish_inline, tokens[1].token_type);

        // The corpus boundary is the byte offset of `}` within the case source.
        // folio's scanBraceContent returns the content up to but not including
        // the terminator, trimmed of surrounding whitespace. The trimmed prefix
        // must equal the token's value.
        const expected_value = std.mem.trim(u8, parsed.source[0..parsed.expected_boundary], " \t\r\n");
        try std.testing.expectEqualStrings(expected_value, tokens[1].value);
    }

    try std.testing.expect(brace_count > 0);
}
