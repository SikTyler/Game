# Corehold Workbench — ledger

Status of every requirement in `WORKBENCH_SPEC.md`. Statuses: **verified** (demonstrated, evidence linked) · **implemented** (built, not yet demonstrated) · **partial** · **blocked** (say on what) · **not started**. Update rows when a status changes, and always at a milestone boundary.

**Current milestone:** 0 — Safe ground

## Decision log

| Date | # | Decision | Source |
| --- | --- | --- | --- |
| 2026-10-06 | D1 | Hub connects through Claude Code on Tyler's subscription login with no API key. It drives the `claude` CLI; the Agent SDK is excluded (its docs require an API key for third-party apps). | Tyler; spec §0, §13 |
| 2026-10-06 | D2 | Build locally on Tyler's PC in Claude Code, not in a cloud session | spec §0 |
| 2026-10-06 | D3 | Workbench lives in its own repo/folder outside the Godot project | spec §0, §2 |
| 2026-10-06 | D4 | Corehold stays a native Godot 4.6.3 .NET game | spec §0, §4 |
| 2026-10-06 | D5 | Fix save isolation before the Workbench runs any game harness | spec §0, §2 |
| 2026-10-06 | — | Master prompt v2 split into `WORKBENCH_CLAUDE.md` (rules), `WORKBENCH_SPEC.md` (full scope), and this ledger. No requirements dropped. Added Milestone 0, demo due-milestones, and the value check after B. | Tyler |

## Open questions (ask in short rounds, with recommendations)

| # | Question | Recommendation | Status |
| --- | --- | --- | --- |
| Q1 | Local paths: game checkout, and where the Workbench repo goes | Keep the existing game checkout and put the Workbench in a sibling folder, e.g. `…\corehold-workbench` | open |
| Q2 | Claude plan (Pro or Max)? Rate limits decide how many specialist sessions can run at once | Ask; default to one active session plus queued work | open |
| Q3 | Confirm the Claude Code route after Milestone A proves it | Hub drives `claude -p` stream-json, with a hub MCP server and a resumable `ask_user` (spec §13) | open, decide at the end of A |
| Q4 | UI-design tool: Penpot self-hosted (Docker), Penpot hosted (cloud), or Excalidraw plus live Godot UI | Excalidraw plus live Godot UI unless Tyler accepts Docker | open, decide before E |
| Q5 | GPU available for ComfyUI image generation? | Check hardware first. If it's weak, keep generation optional/off. | open, decide before E |
| Q6 | Usability/performance targets on the real machine | Measure during A, then agree numbers | open |

## Requirements

### Milestone 0 — Safe ground

| ID | Requirement | Spec | Status | Evidence / next |
| --- | --- | --- | --- | --- |
| 0.1 | Back up `%APPDATA%\Corehold-PC` before anything touches the game | §2, D5 | not started | — |
| 0.2 | Save isolation: harnesses (`selftest`, `uitest`, `_shots`, `playtest`, `smoke`, `horde_*`) use a dev save location; a check proves a real slot survives `MetaSave.clear()`; settings and Steam upload checked too | §2, §8, D5 | not started | Bug confirmed 2026-10-06; see spec §2 "Known facts" |
| 0.3 | Workbench repo created; `CLAUDE.md`, `docs/WORKBENCH_SPEC.md`, `docs/LEDGER.md` installed; game repo keeps only a pointer | §2, D3 | not started | — |
| 0.4 | Doctor: OS, Claude Code installed and logged in on the subscription (no API key), Godot 4.6.3 .NET, .NET 8, Git; actionable errors | §2 | not started | — |
| 0.5 | Windows-native check runner equivalent to `tools/test_all.sh` (or Git Bash plus a documented `timeout` substitute) | §2, §11 | not started | — |
| 0.6 | Inventory of Claude rules/hooks/skills/MCP (no credentials shown); conflicts or expensive settings explained | §2 | not started | — |
| 0.7 | Installed Claude Code capabilities recorded: models, effort levels, session flags, stream-json, image input, question handling, cancellation on Windows | §2, §13 | not started | — |

### Milestone A — Feasibility

| ID | Requirement | Spec | Status | Evidence / next |
| --- | --- | --- | --- | --- |
| A.1 | Launch and stop the native game with isolated dev saves under a hub-owned supervisor | §4, §8 | not started | — |
| A.2 | Capture rendered output; a selection stays correctly located across resize/DPI | §4 | not started | — |
| A.3 | Real request through the `claude` CLI on the subscription; streamed activity shown | §4, §13 | not started | — |
| A.4 | Structured question with Other; the task waits; the answer resumes the correct session | §4, §6, §13 | not started | — |
| A.5 | Tiny reversible change → relevant check → preview → undo only that change | §4, §11 | not started | — |
| A.6 | Capture, input, and audio paths and their limits documented; Godot C# web support status verified | §4 | not started | — |
| A.7 | Shell evaluated (claudecodeui, opcode, Claude Code mods, custom) and one foundation chosen | §4, §15 | not started | — |
| A.8 | Demo 1 | §17 | not started | — |

### Milestone B — Daily usable hub

| ID | Requirement | Spec | Status | Evidence / next |
| --- | --- | --- | --- | --- |
| B.1 | Play / Game Map / Tasks views; dockable panels; focused game and code views; persisted layout | §5 | not started | — |
| B.2 | Play / Inspect / Select / Draw; arrows, circles, rectangles, freehand, text, clear, undo; before/after | §8 | not started | — |
| B.3 | Structured context package (image, normalized coords, viewport, time, live/frozen, IDs, state, seed, build identity) | §8 | not started | — |
| B.4 | Persistent tasks with queued/running/waiting/paused/cancelled/failed/completed; completion separate from acceptance | §13 | not started | — |
| B.5 | Collaboration, Validation, and Permissions as independent settings, global and per task, changeable mid-task | §6 | not started | — |
| B.6 | Durable question records surviving restarts; "Use your recommendation"; "Remember this preference" | §6 | not started | — |
| B.7 | Uninterrupted mode records assumptions and still pauses for required decisions | §6 | not started | — |
| B.8 | Real edits; Fast/Standard/Harden check selection with a stated reason; per-edit and per-task diff review | §11 | not started | — |
| B.9 | Tested-content provenance (incl. uncommitted files); stale results invalidated; source vs. running-build indicator | §8, §11 | not started | — |
| B.10 | Safe undo with patches/snapshots, 3-way merge, and a conflict plan; tested with pre-existing, later manual, renamed/deleted, and asset changes | §11 | not started | — |
| B.11 | Launcher; first-time path; command palette; Open in Godot / editor / terminal | §5 | not started | — |
| B.12 | Optional per-task controls: scope, preserve, specialist, propose/investigate/implement, validation, model/effort | §5 | not started | — |
| B.13 | Cancellation stops the right process tree; recovery reconciles state after restart | §13 | not started | — |
| B.14 | Hub stays useful when Claude is unavailable or rate-limited | §1 | not started | — |
| B.15 | Demos 2, 3, 6, 7 | §17 | not started | — |
| B.16 | Value check with Tyler: is the hub making game work faster? Adjust C–F. | §16 | not started | — |

### Milestone C — Visual specialist workflow

| ID | Requirement | Spec | Status | Evidence / next |
| --- | --- | --- | --- | --- |
| C.1 | Game Map: feature tree plus file tree plus optional dependency graph, seeded from `design/V2_DESIGN.md` | §9 | not started | — |
| C.2 | Feature panel and actions (Request change, Explain, Open code, Show in game, Run checks) | §9 | not started | — |
| C.3 | Editable feature↔code manifest with confirmed/static/inferred labels plus evidence; stale/unmapped items shown | §9 | not started | — |
| C.4 | Proposed scope highlighted before a task; actual affected features and expansion shown after | §9 | not started | — |
| C.5 | Seven editable specialist profiles with direct chats (built on Claude Code subagents/skills where it fits) | §7 | not started | — |
| C.6 | Bounded delegation (depth, concurrency, retries, review rounds) with visible limits; one writer per directory; worktrees when worthwhile | §7 | not started | — |
| C.7 | Specialist-originated questions return to the right task | §6, §7 | not started | — |
| C.8 | Per-feature/task summaries and handoffs instead of one global transcript | §7 | not started | — |
| C.9 | External-change detection; stale edits revalidated | §7, §11 | not started | — |
| C.10 | Demos 4, 5 | §17 | not started | — |

### Milestone D — Game development tools

| ID | Requirement | Spec | Status | Evidence / next |
| --- | --- | --- | --- | --- |
| D.1 | Dev bridge in the game: selectable regions/hit testing → meaningful IDs; dev-only, excluded from exports; local session auth | §8 | not started | — |
| D.2 | Dev operations: state, scenarios, pause/step/speed, grants, spawns, screen shortcuts, screenshots, logs, tuning, checks, metrics | §8 | not started | — |
| D.3 | In-hub input bridge (if built) releases held input on blur, disconnect, mode switch, and cancel | §4 | not started | — |
| D.4 | Named scenarios: fresh play, crowded combat, full Forge inventory, developed Outpost | §10 | not started | — |
| D.5 | One-click bug capture; versioned restoration with unsupported parts labeled | §10 | not started | — |
| D.6 | Frame/sim timings, enemy counts, capture overhead; targets agreed on the machine | §10 | not started | — |
| D.7 | Balance workspace: jobs, seeds, `GF_TUNE`, queued comparisons with versioned results | §10 | not started | — |
| D.8 | Demo 8 | §17 | not started | — |

### Milestone E — Creative workspace

| ID | Requirement | Spec | Status | Evidence / next |
| --- | --- | --- | --- | --- |
| E.1 | Asset registry: stable IDs, sources, exports, versions, licenses, in-game uses; compare/revert; impact shown before replace | §12 | not started | — |
| E.2 | Editable Corehold style guide (from `ui/Kit.gd`) | §12 | not started | — |
| E.3 | UI design workflow (tool per Q4) | §12 | not started | Blocked on Q4 |
| E.4 | Sketch/annotation: Excalidraw | §12 | not started | — |
| E.5 | Sprites/animation: Pixelorama | §12 | not started | — |
| E.6 | Image generation: ComfyUI (per Q5) | §12 | not started | Blocked on Q5 |
| E.7 | Models/rendered sprites: Blender | §12 | not started | — |
| E.8 | Services start on demand; hub fully usable when they're off | §12 | not started | — |
| E.9 | Per-integration doc: operations, version/license, embed vs. launch, formats, setup, proof | §12 | not started | — |
| E.10 | Demo 9 | §17 | not started | — |

### Milestone F — Expandable suite

| ID | Requirement | Spec | Status | Evidence / next |
| --- | --- | --- | --- | --- |
| F.1 | Tool registry (schemas, versions, side effects, availability); same operations for users and agents | §13 | not started | — |
| F.2 | Skill manager: selective loading, editing, version history, explicit invocation | §13 | not started | — |
| F.3 | Effective rules view: sources, precedence, scope, conflicts | §13 | not started | — |
| F.4 | Context builder; usage (API-equivalent estimate labeled) and time breakdown per task | §13 | not started | — |
| F.5 | Plugin/adapter contract plus one working example | §13 | not started | — |
| F.6 | Teach Me, Explain this code, Show me how | §14 | not started | — |
| F.7 | "What the suite remembers" view; no silent promotion of inferences | §14 | not started | — |
| F.8 | Improvement inbox (Build / Adjust / Dismiss; related proposals consolidated) | §14 | not started | — |
| F.9 | Workbench changes developed separately; staged update and rollback; active tasks survive | §14 | not started | — |
| F.10 | Small agent benchmark for instruction/adapter changes | §14 | not started | — |
| F.11 | Export/restore of data and config; predictable disable/uninstall | §13 | not started | — |
| F.12 | Handoff deliverables: source, launcher/setup docs, pinned versions, data locations, extension docs, third-party notices | §17 | not started | — |
| F.13 | Demos 10, 11, 12 | §17 | not started | — |

## Continuation note

**2026-10-06 (planning, cloud session).** Spec, rules, and ledger written in the game repo under `design/workbench/` on branch `claude/sleepy-hopper-p2hn8k`. No Workbench code exists yet. Nothing has run on Tyler's machine. Next action: Tyler runs `design/workbench/KICKOFF.md` in Claude Code on his PC, opened in his local game checkout.
