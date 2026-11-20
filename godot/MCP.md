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

## Sods2 godot-mcp — server verified; editor addon not installed in this project

[Sods2/godot-mcp](https://github.com/Sods2/godot-mcp) (MIT), v1.3.0, 84 tools.
A Node stdio server. File-based tools (scene parsing, `.tscn` editing,
resources, directory listing, test detection, script validation) work
without an editor; live tools talk to its own editor addon on TCP 6008.

Verified in the cloud container (Node 22, Godot 4.4.1):

- Built from source (`npm install && npm run build`) and driven over real
  MCP stdio calls: `tools/list` returned 84 tools; `godot_list_directory`
  and `godot_detect_test_framework` ("builtin") worked against this project.
- `godot_validate_script` works but, without its editor addon running,
  falls back to `--check-only`, which does not load autoloads; it reports
  `Settings` as unknown. That is the tool's documented limitation, not a
  bug in the game. Use the project's own `--import` plus the test run.
- Its own end-to-end editor test (`npm run test:bridge` under `xvfb-run`
  with `--rendering-driver opengl3`) passed 16/16: scene tree, add node,
  set property, rename, signals, animation, screenshot, save.

Not installed into the project: its addon folder is also named
`addons/godot_mcp_bridge`, which would overwrite the rezaahmadn bridge
above. Beckett already covers live-editor work here. To use the Sods2 live
tools, swap the folder in deliberately (and disable the other bridge).

```
claude mcp add godot-sods -e GODOT_PATH=/usr/local/bin/godot \
  -e GODOT_PROJECT_PATH=$PWD -- node /path/to/godot-mcp/build/index.js
```

## Skills

- **GodoMaster** (`npm install -g godomaster-skill`): installed; copies a
  21-chapter Godot 4 reference to `~/.claude/skills/godomaster/`. That is
  user-level, outside the repo, so a fresh container needs it reinstalled.
- **GodotPrompter 2d-essentials**
  (`npx -y skills add jame581/GodotPrompter --skill 2d-essentials --agent claude-code`):
  installed into the repo at `.claude/skills/2d-essentials/`.

What was taken from them: the 2D normal-map, parallax and draw-order
guidance. This game lights tiles with a CPU light map rather than
`Light2D` nodes (far cheaper on the Compatibility renderer on Android),
so surface lighting reads that light map in the shaders instead of
adding per-object lights.

GitHub was searched for further Godot 4 2D wind, foliage and normal-map
tools; nothing found was licensed, maintained and better than writing
the shaders directly, so nothing more was installed.

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
