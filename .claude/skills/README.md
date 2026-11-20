# Vendored Claude Code skills

Third-party output-shaping skills, copied in from upstream. Only the `SKILL.md`
instruction files were taken — no hooks, scripts, proxies, or telemetry.

| Skill | Upstream | License | Commit |
|---|---|---|---|
| `caveman`, `ultracave`, `megacave` | [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) | Apache-2.0 | `a192894` |
| `i-have-adhd` | [ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd) | MIT | `1ecea19` |
| `ponytail`, `ponytail-review`, `ponytail-audit`, `ponytail-debt`, `ponytail-gain`, `ponytail-help` | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) | MIT | `96608e0` |

## What each one does

- **caveman** — terse voice. Answer first, filler gone, code/paths/errors kept
  verbatim. `ultracave` and `megacave` are the more extreme levels.
- **i-have-adhd** — action-first output: next action on line one, numbered
  steps, state restated each turn, no preamble or recap. Manual invocation only
  (`disable-model-invocation: true`), so call it with `/i-have-adhd`.
- **ponytail** — lazy-senior-dev coding rules: smallest complete change, YAGNI,
  stdlib before dependencies. The companions are one-shot reports
  (`-review` on a diff, `-audit` on a repo, `-debt` lists deferred shortcuts).

## Heads-up: caveman and i-have-adhd overlap

Both rewrite prose style and both claim the whole session. Running them together
gives contradictory instructions (caveman wants fragments and no tables,
i-have-adhd wants numbered steps and time estimates). Pick one at a time.

`ponytail` is orthogonal — it governs the code written, not the prose — so it
composes fine with either.

## What was deliberately left out

- `caveman-compress`, `caveman-stats`, `cavecrew` — need the plugin's Python
  scripts and session hooks to function.
- All upstream hooks. Notably ponytail's plugin ships a `webhookUrl` /
  `webhookToken` config that posts per-task metrics (including task names) to a
  remote endpoint, and a local CSV ledger under `~/.config/ponytail/`. None of
  that is installed here.

## Getting the full plugins instead

To install upstream complete, with hooks, slash commands and auto-updates, in
your own Claude Code:

```
/plugin marketplace add JuliusBrussee/caveman
/plugin install caveman@caveman

/plugin marketplace add ayghri/i-have-adhd
/plugin install i-have-adhd@i-have-adhd

/plugin marketplace add DietrichGebert/ponytail
/plugin install ponytail@ponytail
```

If you do that, delete the matching directories here to avoid two copies of the
same skill competing.
