# folio

A dialogue scripting DSL for games. folio lets you write scenes and beats as plain text, embed lish expressions for logic and side-effects, and drive playback through a host-controlled Runner. It is designed to be embedded in game engines or other interactive applications.

Built on [lish](https://github.com/mhogle25/lish).

## Script Syntax

A folio script is a collection of named **scenes**, each composed of **beats**. A beat is one page of content — the player sees it, confirms, and moves on.

### Scenes and Beats

```
::main
Hello there.
;;
Are you still with me?
;;
Good.
;;

::elsewhere
This is a different scene.
;;
```

- `::name` declares a new scene. Scripts must have a `main` scene.
- `;;` separates beats within a scene.
- Every script must contain a `::main` scene.

### Comments

Lines beginning with `//` are comments and are ignored entirely — they produce no output and no blank line:

```
::main
// this beat introduces the vendor
#"Vendor:"
Something catch your eye?
;;
```

`//` is only recognised at the start of a line (after optional leading whitespace). Mid-line `//` is treated as plain text.

### Text Sigils

| Sigil | Name | Behavior |
|-------|------|----------|
| *(text)* | text | Typewriter character-by-character. Affected by `instant` mode. |
| `#"..."` | instant string | Displayed all at once, bypasses typewriter. |
| `@"..."` | char string | Always typewriter, even when instant mode is on. |
| `{...}` | lish inline | Evaluates a lish expression at typewriter position (before the next character). Side-effects only. |
| `%{...}` | lish defer | Queues a lish expression to fire when the player confirms. Side-effects only. |
| `#{...}` | instant lish | Evaluates a lish expression and displays the result instantly as text. |
| `@{...}` | char lish | Evaluates a lish expression and displays the result character-by-character. |

Both `"double-quoted"` and `'single-quoted'` forms are accepted for all string sigils (`#"..."`, `#'...'`, `@"..."`, `@'...'`). Quoted strings support escape sequences:

| Sequence | Character |
|----------|-----------|
| `\\` | Backslash |
| `\"` | Double quote |
| `\'` | Single quote |
| `\n` | Newline |
| `\r` | Carriage return |
| `\t` | Tab |
| `\0` | Null |
| `\a` | Bell |
| `\b` | Backspace |
| `\e` | Escape (0x1B) |
| `\f` | Form feed |
| `\v` | Vertical tab |

### Example Script

```
::main
#"Stranger:"
You there.
;;
Yes, you. Don't look so alarmed.
;;
#"Stranger:"
I just need...{ delay medium } directions.
;;
The stranger pulls out a crumpled map.
;;
#"Stranger:"
The market. Do you know it?
;;
#"You:"
Follow the main road south — you can't miss it.
;;
The stranger folds the map and walks away.%{ scene market }
;;

::market
#{ concat "The market is " "loud and bright" } — a stark contrast to the cold square.
;;
```

In this example:
- `#"Stranger:"` displays the speaker label instantly.
- `{ delay medium }` pauses the typewriter mid-sentence.
- `%{ scene market }` jumps to the `market` scene when the player confirms the current beat.
- `#{ concat ... }` evaluates a lish expression and inserts the result as instant text.

## Installation

Requires **Zig 0.15.2** or later.

Add as a dependency in your `build.zig.zon`:

```
zig fetch --save git+https://github.com/mhogle25/folio.git
```

Wire it up in `build.zig` alongside lish:

```zig
const lish_dep = b.dependency("lish", .{ .target = target, .optimize = optimize });
const lish_mod = lish_dep.module("lish");

const folio_dep = b.dependency("folio", .{ .target = target, .optimize = optimize });
const folio_mod = folio_dep.module("folio");

your_module.addImport("lish", lish_mod);
your_module.addImport("folio", folio_mod);
```

## Usage

### Compiling a Script

`compileFile` and `compileSource` collapse tokenize → parse → compile into a single call:

```zig
const folio = @import("folio");

var compile_result = try folio.compileFile("scene.folio", allocator);

var prog = switch (compile_result) {
    .ok => |p| p,
    .err => |*errors| {
        defer errors.deinit();
        for (errors.items) |node_err| {
            for (node_err.errors) |verr| {
                std.debug.print("[{s} beat {d}] {s}\n", .{
                    node_err.scene, node_err.beat_index, verr.message,
                });
            }
        }
        return error.CompileFailed;
    },
};
defer prog.deinit();
```

Use `compileSource` if you already have the source text in memory:

```zig
var compile_result = try folio.compileSource(source_text, allocator);
```

### Session Integration

`FolioSession` is the primary integration point. It owns the registry and runner, registers all built-in ops automatically, and exposes a simple frame-driven API.

```zig
const folio = @import("folio");

// 1. Implement RenderTarget.Vtable
const MyTarget = struct {
    fn renderTarget(self: *MyTarget) folio.runner.RenderTarget {
        return .{ .context = self, .vtable = &vtable };
    }

    const vtable = folio.runner.RenderTarget.Vtable{
        .appendChar = appendChar,
        .appendText = appendText,
        .clear = clear,
        .reportError = reportError,
    };

    fn appendChar(ctx: *anyopaque, char: u8) void {
        const self: *MyTarget = @ptrCast(@alignCast(ctx));
        _ = self;
        // emit one character to your renderer
    }

    fn appendText(ctx: *anyopaque, text: []const u8) void {
        const self: *MyTarget = @ptrCast(@alignCast(ctx));
        _ = self;
        // emit a full string at once (instant display)
    }

    fn clear(ctx: *anyopaque) void {
        const self: *MyTarget = @ptrCast(@alignCast(ctx));
        _ = self;
        // clear the display (called between beats)
    }

    fn reportError(ctx: *anyopaque, message: []const u8) void {
        const self: *MyTarget = @ptrCast(@alignCast(ctx));
        _ = self;
        // display or log a lish runtime error
        _ = message;
    }
};

// 2. Create session — builtins and folio ops registered automatically
var my_target = MyTarget{};
const session = try folio.FolioSession.init(&prog, my_target.renderTarget(), .{}, allocator);
defer session.deinit();

// 3. Load a scene and drive the loop
_ = session.loadScene("main");

// Call advance() every frame with elapsed time in milliseconds
const state = session.advance(delta_ms);

// When state is .waiting, show a prompt and wait for the player
if (state == .waiting) {
    session.confirm();
}
```

Pass `FolioSessionConfig` to customise the session:

```zig
const session = try folio.FolioSession.init(&prog, my_target.renderTarget(), .{
    .runner_config = .{ .chars_per_sec = 30.0, .confirm_skips = false },
    .scope = &my_scope,
    .fragments = &.{ my_ops.registerAll },
}, allocator);
```

### Advanced: Manual Runner Setup

For hosts that need full control over the registry (e.g. multiple independent runners, custom op sets), you can construct the `Runner` directly:

```zig
const lish = @import("lish");
const folio = @import("folio");

var registry = lish.Registry{};
defer registry.deinit(allocator);
try lish.builtins.registerAll(&registry, allocator);

var my_target = MyTarget{};
var runner = folio.runner.Runner.init(
    &prog,
    &registry,
    &lish.Scope.EMPTY,
    my_target.renderTarget(),
    .{ .chars_per_sec = 60.0 },
    allocator,
);
defer runner.deinit();

try folio.ops.registerAll(&registry, &runner, allocator);
_ = runner.loadScene("main");
```

### Runner State Machine

```
loadScene()
     │
     ▼
┌──────────┐◄──────────────────────────────┐
│ emitting │     confirm() (next beat)     │
└──────────┘                               │
     │ advance() — beat fully emitted      │
     ▼                                     │
┌─────────┐  confirm() (more beats)        │
│ waiting │─────────────────────────────── ┘
└─────────┘
     │ confirm() (last beat)
     ▼
  ┌──────┐
  │ done │
  └──────┘
```

- `advance(delta_ms)` drives the typewriter each frame. When the beat is fully emitted, the runner transitions to `waiting`.
- `confirm()` in `waiting` loops back to `emitting` if more beats remain, or transitions to `done` on the last beat.
- `confirm()` in `emitting` (when `confirm_skips` is true) flushes the current beat instantly and transitions to `waiting`.
- The `end` op transitions to `done` immediately from any state.

| State | Meaning |
|-------|---------|
| `emitting` | Typewriter is actively outputting characters |
| `waiting` | Current beat is fully displayed; waiting for `confirm()` |
| `done` | All beats played; scene is complete |

### RunnerConfig

```zig
pub const RunnerConfig = struct {
    /// Characters emitted per second during typewriter effect. Default: 60.0
    chars_per_sec: f64 = 60.0,
    /// If true, confirm() while emitting flushes the current beat instantly. Default: true
    confirm_skips: bool = true,
    /// If true, text nodes are emitted instantly on scene load. Default: false
    instant_mode: bool = false,
};
```

## Built-in Ops

`folio.ops.registerAll` registers these operations into your lish registry:

| Op | Args | Description |
|----|------|-------------|
| `instant` | 0\|1 | Toggle instant mode (0 args), or set it by truthiness (1 arg) |
| `ffwd` | 0\|1 | Toggle fast-forward mode (0 args), or set it by truthiness (1 arg). When enabled, confirm() while the typewriter is emitting flushes the beat instantly. |
| `speed` | 0\|1 | Set typewriter speed: `"slow"` (30), `"normal"` (60), `"fast"` (120), or a number (chars/sec). No arguments resets to the host-configured default. |
| `delay` | 1 | Pause typewriter: `"short"` (250ms), `"medium"` (500ms), `"long"` (1000ms), or a number (ms) |
| `scene` | 1 | Jump to a named scene |
| `skip` | 0 | Flush current beat and immediately advance to the next |
| `continue` | 0 | Flush current beat to waiting state without advancing |
| `clear` | 0 | Clear the render target |
| `end` | 0 | Immediately end the scene, bypassing any remaining beats |

These map directly to runner behavior — no game-specific rendering logic is included.

## Scope Integration

Pass game state into folio scripts via a `lish.Scope`. Variables set on the scope are accessible from any embedded lish expression using `:varname`.

```zig
var scope = lish.Scope{};

// Bind a static value (evaluated once)
try scope.setValue(allocator, "playerName", .{ .string = "Aiden" });

// Bind a lazily-evaluated expression (re-evaluated each access)
const greet_expr = ...; // lish.exec.Expression
try scope.setExpression(allocator, "greeting", greet_expr);

var runner = Runner.init(&prog, &registry, &scope, target, .{}, allocator);
```

In the script:
```
Hello, #{ proc :playerName }.
```

## Terminal Player

folio ships a terminal player for previewing scripts during development.

```sh
# Build
zig build

# Play a script
zig build run -- demo.folio

# Start from a specific scene
zig build run -- demo.folio --scene market
```

**Controls:**

| Key | Action |
|-----|--------|
| Space / Enter | Advance beat (or skip typewriter if still emitting) |
| `q` / Ctrl+C | Quit |

The terminal player prints `---` between beats and shows a `▶` prompt when waiting for input.

## Building

```sh
# Run all tests
zig build test

# Build library + terminal player
zig build
```

## Architecture

| File | Purpose |
|------|---------|
| `root.zig` | Public API — re-exports, `compileSource`, `compileFile` |
| `token.zig` | Token types and syntax constants |
| `lexer.zig` | Tokenizer — converts folio source to tokens |
| `node.zig` | AST node types: `Script`, `Scene`, `Beat`, `Node` |
| `parser.zig` | Converts token stream into a `Script` |
| `programme.zig` | Compiles a `Script` into an executable `Programme` |
| `runner.zig` | Drives a `Programme` via `RenderTarget`; typewriter, beats, deferred ops |
| `ops.zig` | folio built-in lish operations (instant, ffwd, speed, delay, scene, skip, continue, clear, end) |
| `session.zig` | `FolioSession` — heap-allocated session owning registry and runner |
| `main.zig` | Terminal player entry point |

## License

[MIT](LICENSE)
