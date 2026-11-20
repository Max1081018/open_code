# MCP servers for Lanternbound

Both MCP projects were installed and **verified by speaking MCP to them**,
not just by seeing a port open. Verified in a Linux x86_64 cloud container
with Godot 4.4.1 and Node 22 — **not** on an Android phone (see the end).

## Beckett — installed and enabled

`addons/beckett/` (v1.17.0, Lite, MIT). An MCP server that runs *inside* the
Godot editor: no Node, no Python. It does **not** need the graphical editor:
`BECKETT_ENABLE=1` forces the server on in a headless editor.

```sh
tools/mcp/start_beckett.sh        # starts a headless editor, prints the URL
claude mcp add --transport http beckett <printed URL>
```

The URL carries a per-project auth token (`.beckett/token`, git-ignored).
`.mcp.json` is git-ignored too, because it would carry that token.

Verified: MCP initialize → 56 tools listed → `get_godot_version` returned
4.4.1-stable → `get_scene_tree` returned this project's `Main` node.

Beckett strips itself from exports: only an inert `BeckettRuntime` stub
autoload ships, and it does nothing outside the editor. The 44 tests and the
game run unchanged with it enabled.

## godot-mcp-bridge — installed, disabled by default

`addons/godot_mcp_bridge/` (MIT) plus a Node server built from
https://github.com/rezaahmadn/godot-mcp-bridge (`npm install && npm run build`).
Claude Code starts the bridge over stdio; the editor addon dials it on
`ws://127.0.0.1:6505`.

Verified: MCP initialize → 174 tools listed → with a headless editor running,
the addon connected within 15 s and `get_project_info` returned this
project's autoloads.

**Why it is disabled:** enabling it injects three autoloads into
`project.godot` (`MCPGameInspector`, `MCPInputService`, `MCPScreenshot`) that
would ship inside the APK. Turn it on only for a session:

```sh
tools/mcp/start_bridge.sh         # enable + start a headless editor
claude mcp add --scope user godot -- node /abs/path/godot-mcp-bridge/dist/index.js
tools/mcp/stop_bridge.sh          # before exporting: removes the autoloads
```

The export preset also excludes `addons/godot_mcp_bridge/`.

## On an Android phone (Termux) — not verified

No phone was reachable from the session that did this work, so none of the
following has been tried on one. What should work, and why:

- Neither server needs a display; both work with a **headless** editor.
- Godot publishes official `linux.arm64` builds. Termux is not glibc-based,
  so run Godot inside `proot-distro` (e.g. Debian), which shares Termux's
  network, so `127.0.0.1:8770` is reachable from Claude Code in Termux.
- Beckett then needs nothing else. The bridge additionally needs Node in
  Termux (`pkg install nodejs`).
- These endpoints are **localhost only**. They are not remote MCP URLs and
  cannot be reached from another device.
