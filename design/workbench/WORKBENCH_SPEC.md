# Corehold Workbench — full specification

This is the complete destination for Corehold Workbench. It is reference material: read the sections the current milestone needs, not the whole file every session. The always-on working rules are in `WORKBENCH_CLAUDE.md` (which becomes the Workbench repo's `CLAUDE.md`), and the status of every requirement is in `LEDGER.md`.

The section numbers match the original master prompt (v2). §3 and the working rules from §16 describe how to build rather than what to build, so they moved to `WORKBENCH_CLAUDE.md`. §16 keeps the milestone table. Changing scope requires Tyler's agreement, and any change gets a row in the ledger.

## 0. Decisions already made

| # | Decision | Notes |
| --- | --- | --- |
| D1 | **The hub is Tyler's own custom front-end on top of the `claude` CLI, running on his Claude Max plan login. No Anthropic API key.** | In normal use Tyler works only in the hub's interface; the CLI runs headless underneath and he never has to use the Claude Code terminal. The hub drives the `claude` CLI, which is documented as running on the subscription. The Agent SDK is excluded because its docs require an API key for third-party apps. See §13, "Claude Code connection". If a feature cannot work without an API key, stop and tell Tyler. Don't add a key path. |
| D2 | The Workbench is built locally on Tyler's PC, in Claude Code (terminal, desktop app or IDE), not in a cloud session. | A cloud container has no display, no Windows and no access to the real game window. |
| D3 | Workbench code lives in its own repo/folder outside the Godot project. Only a small dev bridge and config live in the game. | §2 |
| D4 | Corehold stays a native Godot 4.6.3 .NET game. No JavaScript rewrite, no reliance on web export, no casual engine upgrade. | §4 |
| D5 | Fixing save isolation comes before any Workbench work touches the game. | §2, "Known facts" |

Open decisions for the first question round, which are also listed in the ledger: local paths; confirming the recommended Claude Code route (§13) once feasibility proves it; the UI-design tool (§12, Penpot vs. Docker); generation hardware (§12, ComfyUI); usability and performance targets on the real machine.

## 1. Outcome and operating principles

The everyday workflow is:

**Play → select or draw → describe the change → answer design questions → implement → focused verification → compare → keep, revise, or revert.**

Tyler can also begin from a feature in the Game Map, a file, an asset, or a chat with a specialist. Everything operates on ordinary local code. Local Git provides history and checkpoints; GitHub is an optional remote, not the runtime or an obligatory step in making an edit.

Keep the default interface simple. Show advanced controls progressively. Support direct manual editing, the native Godot editor, and an ordinary terminal. The hub should remain useful when AI is disconnected, rate-limited, or unavailable.

Priorities when requirements compete:

1. Preserve Tyler's existing work and personal game saves.
2. Make the local game/edit/review loop work on his actual computer.
3. Make questions, changes, and agent activity understandable and controllable.
4. Keep routine development fast and verification proportional to the change.
5. Expand through maintainable adapters and plugins.

Implement all requested capabilities over the milestones. A first usable milestone is not full completion. Track every incomplete capability in the ledger, and change the final scope only with Tyler's agreement.

## 2. Start with the machine and repository

Inspect the actual environment before prescribing a stack or installing dependencies.

- Identify the local project path, active branch, working-tree changes, applicable instructions, launch commands, and toolchain. Ask for the path if it is ambiguous. If no checkout exists, offer to clone https://github.com/SikTyler/Game/ into an appropriate local folder.
- Confirm the actual host OS. Windows is the working assumption, not a verified fact. Avoid requiring WSL or Docker unless a selected dependency needs it and Tyler accepts that tradeoff.
- Detect Claude Code (the `claude` CLI and its login state), Godot .NET, .NET SDK, Git, and relevant runtimes. Provide a doctor/setup action that checks versions and gives actionable errors.
- Prefer the existing checkout. Preserve uncommitted/untracked work. Never reset, clean, overwrite, or force-push unrelated changes.
- Keep Workbench code in its own repository or a clearly separate package outside Godot's resource scan. Keep only the necessary development bridge and configuration inside the game. Document both paths and revisions.
- Inspect relevant project/global Claude rules, hooks, skills, and MCP configuration without exposing credentials. Explain conflicting or expensive instructions. Prefer project-scoped fixes to changing unrelated global settings.
- Verify what the installed Claude Code build supports: model identifiers, effort controls, session resumption, question handling, streaming, tools, and image input. Do not hard-code or assume the meaning of "Opus 5.5," "Ultracode," "Max," or "Extra." Display the actual selected model and supported settings.
- Distinguish local application/data storage from cloud model inference. Show where requests go; do not describe cloud Claude as offline or as private on-device inference.

### Known facts from inspection (2026-10-06, cloud checkout of `main` @ 6237f31)

Current code is authoritative. Re-verify these on the local machine.

- `Corehold.csproj` uses `Godot.NET.Sdk/4.6.3`, and the README says .NET 8. Game files at the repo root include `Main.gd`, `TowerState.gd`, `HordeWorld.cs`, `MetaSave.gd`, `Tune.gd`, `selftest.gd`, `uitest.gd`, `smoke.gd`, `horde_fp.gd`, `horde_prof.gd`, `playtest.gd`, `_shots.gd`, `tests/st_*.gd`, and `tools/test_all.sh`.
- **Save isolation bug (D5). Fixed on branch `claude/sleepy-hopper-p2hn8k`**: `MetaSave.root()` sends `--script` runs, and any run with `COREHOLD_DEV_SAVES=1`, to `user://dev/`. When the hub launches the game for development, it sets `COREHOLD_DEV_SAVES=1`. What the bug was: `project.godot` sets `custom_user_dir_name="Corehold-PC"`, so harnesses and real play share `%APPDATA%\Corehold-PC`. `MetaSave.clear()` deletes the active slot (`slot_1.json` plus `.bak`/`.tmp`) and the legacy `save.json`. It is called by `selftest.gd`, `uitest.gd`, `_shots.gd` and `playtest.gd`. selftest also deletes all three slots, and uitest rewrites `settings.cfg`. Running the test gate on the machine where Tyler plays wiped his saves. Fix this in the game (harnesses use a dev save location) before the Workbench runs any of these scripts. Also check `Settings.gd`/`settings.cfg` and `SteamService.gd`, which uploads every `slot_*.json`.
- **Repo tooling is Linux-only.** `tools/setup_godot.sh` downloads the Linux mono build, and `tools/test_all.sh` is bash and uses `timeout`. The Windows doctor/setup and check runner need Windows-native equivalents, or Git Bash plus a documented `timeout` substitute. Don't assume WSL.
- The game repo's `CLAUDE.md` holds the rules for game changes (determinism and the `HORDE_FP_GOLDEN` hash, where tests go, UI text contrast, the test ledger in `design/V2_PROGRESS.md`). Follow it whenever the Workbench edits the game. `design/V2_DESIGN.md` is the best seed for the Game Map (§9).

## 3. Collaboration and authorization

→ Moved to `WORKBENCH_CLAUDE.md` (rules for how to build).

## 4. Prove the difficult connections before building a large UI

Run a narrow, working feasibility exercise for the chosen architecture:

1. Launch and stop the actual native game using isolated development saves.
2. Capture its rendered output and correctly locate a selection across resize/DPI changes.
3. Send a real request through Tyler's Claude Code subscription connection and display streamed activity.
4. Surface a structured question with Other, wait, submit the answer, and continue the correct task.
5. Make a tiny reversible change, run a relevant check, preview the result, and undo only that change.

Choose the dashboard/runtime after this proves the route. Evaluate an existing extensible shell first; if it obstructs these requirements, explain the concrete tradeoff and select a small custom shell. Choose one foundation, not several overlapping agent frameworks.

Do not rewrite Corehold into JavaScript or depend on browser export to create a preview. Verify current Godot C# web support, and preserve the native game architecture. Desktop capture/native embedding and game input are distinct problems: identify the supported capture path, input path, audio behavior, permissions, and limitations.

A stream alone does not provide bidirectional game input. If full in-hub gameplay requires a bridge, implement it and release held keys/buttons on blur, disconnect, mode switch, or cancellation. Keep native-window play available. A frozen screenshot is an annotation surface, never a pretend live game.

## 5. Interface and usability

Use a desktop-oriented workspace with **Play**, **Game Map**, and **Tasks** as primary views. Add **Assets** as a focused workspace. Specialists, files, terminal, code/diff, checks, logs, selected-object details, and configuration are collapsible or dockable panels.

Default layout: game/working canvas in the center; feature tree or specialists on the left; current task/chat on the right; optional tools below. Support a focused game view and a focused code view. Persist layout preferences. Use clear empty/loading/error states, readable text, accessible controls, and concise labels.

Provide a command palette and direct "Open in Godot," "Open in editor," and "Open terminal" actions. Normal use should not require knowing about MCP, worktrees, schemas, or agent orchestration.

The first-time path: choose project → detect/setup dependencies → connect Claude Code (confirm it is logged in to Tyler's subscription) → launch game → make a visual request. Provide a reliable launcher so normal startup does not require several terminal commands.

Per task, offer optional controls for scope, what to preserve, specialist, propose/investigate/implement behavior, validation mode, and model/effort where Claude Code supports them. Keep micro-control available without making every control mandatory.

## 6. Questions must actually pause and resume work

Separate three settings:

- **Collaboration:** Collaborative or Uninterrupted.
- **Validation:** Fast, Standard, or Harden.
- **Tool permissions:** what operations are authorized.

Changing one must not silently change the others.

Collaborative is the default. Ask focused questions about unresolved behavior, appearance, scope, and tradeoffs; include a recommended choice, short reasons, alternatives, and Other/free text. Allow "Use your recommendation" and an explicit "Remember this preference." Group related questions into short rounds. Do not ask again about settled choices or invent ambiguity to justify an interruption.

Implement questions as structured, durable task records with question ID, task/session ID, originating specialist, options, answer, and status. The dependent action must wait. A dismissed card or disconnected browser is not a default answer. Persist pending questions and answers across restarts.

Use a verified Claude Code mechanism. Test `AskUserQuestion` through `--permission-prompt-tool` first; the fallback is the hub's resumable `ask_user` tool (§13, "Route to prove in Milestone A"). Parsing question marks from chat is insufficient. Do not select an unattended permission configuration that removes the question capability from Collaborative tasks.

Verify specialist question routing: if delegated subagents cannot ask the user directly, route a structured clarification through the task owner, or implement that specialist as a separately addressable session. Demonstrate that the answer returns to the right task.

Uninterrupted resolves optional choices within scope and records assumptions. It still pauses for genuinely required user decisions or missing authorization. The toggle applies globally and per task, can change mid-task, and does not retroactively authorize destructive actions.

## 7. Specialists and bounded cooperation

Provide editable profiles for:

| Specialist | Responsibility |
| --- | --- |
| Combat | Waves, targeting, weapons, enemies, crowd simulation |
| Gear & Loot | Generation, affixes, Forge, drops, inventory |
| Outpost & Progression | Buildings, research, levels, prestige, idle economy |
| UI & Feel | Screens, controls, tooltips, animation, sound |
| Balance | Seeded experiments, pacing, difficulty, economy |
| Integration | Cross-system work and checkpoint verification |
| Workbench | The development suite itself |

Each profile has editable responsibilities, instructions, file/feature mappings, tools, skills, checks, memory, and history. Tyler can chat directly with it and inspect its configuration. Where it fits, build profiles on Claude Code's own primitives (subagent definitions, skills, project rules) rather than a parallel agent framework.

Profiles are not automatically always-running agents. Use one task owner and only the specialists needed. Start with one writer per working directory. Bound delegation depth, concurrent jobs, retries, and review rounds; show configurable limits and a reason when more work is needed. Avoid routine agent-to-agent critique loops.

Distinguish persistent specialist conversations from short delegated workers. Maintain summaries/decisions per feature and task instead of continually growing one global transcript. Share necessary handoff context, not every specialist's entire history.

Responsibility mapping guides work; it must not trap cross-system features. Coordinate shared-file edits and dependencies. Use separate worktrees for independent work when worthwhile. Define how their changes reach the active play checkout and how conflicts are resolved.

Honor ownership through the actual editing/execution path, not just a sentence in a prompt. Never claim that advisory file locks constrain arbitrary external terminal edits. Detect outside changes and revalidate before applying stale edits.

## 8. Live game, selections, and development bridge

Implement Play / Inspect / Select / Draw modes; arrows, circles, rectangles, freehand, text, clear, and undo; frame capture; before/after review; selected-object details; and contextual edit requests.

Attach a compact structured context package: captured image, normalized annotation coordinates, viewport dimensions, capture time, live/frozen state, selected object/feature ID, relevant game state, scenario/seed, and exact source/build identity. Keep the image Claude sees consistent with the annotation.

Corehold has code-drawn elements, so add explicit development-only selectable regions or hit testing. Resolve a turret, gear item, tooltip, or screen to meaningful IDs. Label inferred or unknown mappings. Screenshots alone do not prove which file owns an element.

Expose structured development operations for selection/state inspection, scenario launch, pause/resume/step/speed, resource grants, enemy spawning, screen shortcuts, screenshots, errors/logs, temporary tuning, selected checks, and available performance metrics. Reuse existing game entry points and harnesses (`_shots.gd`, `playtest.gd`, `Tune.gd`/`GF_TUNE`, `horde_prof.gd`).

Run native processes under a hub-owned supervisor. Game lifetime must not accidentally depend on an agent turn staying alive. Label when the running build differs from source changes; require rebuild/restart when appropriate. Do not promise universal C# or simulation hot reload.

Keep development functionality out of production exports (`export_presets.cfg`). Bind runtime control locally with a session credential. Isolate test/dev saves and verify that isolation before executing scripts that clear or modify saves (D5). Never test against personal progress.

## 9. Game Map and code understanding

Build a semantic feature tree connected to a normal file tree, plus an optional dependency graph. Start with Combat, Gear & Loot, Outpost, Progression, Screens & Controls, Audio & Effects, Saves, and Development Tools. Seed it from `design/V2_DESIGN.md` and the README layout table.

A feature panel shows description, implementation files/symbols and data, related features, dependencies, tests, owning specialist, active tasks, and changes. Actions: Request change, Explain, Open code, Show in game, and Run relevant checks.

Use an editable feature-to-code manifest together with incremental code/file analysis. Track whether each relationship is manually confirmed, statically detected, or inferred, and what evidence supports it. Support renaming, moving, and correcting mappings. Show unmapped/stale items. Avoid an expensive whole-repo LLM analysis after every edit.

Before a task, highlight proposed scope. Afterward, show actual affected features and meaningful scope expansion. Inspect interactions without rendering an unreadable graph of every symbol.

## 10. Reproduction, debugging, performance, and balance

Create named scenarios for fresh play, crowded combat, full Forge inventory, and developed Outpost. Reuse deterministic seeds, fixtures, screenshots, tuning overrides, and bot jobs already present.

One-click bug capture records relevant logs, screenshot, seed, scenario/state, available input history, environment, and tested source/build. Implement versioned restoration appropriate to each scenario. A seed is not an exact mid-run snapshot; restore or clearly label unsupported parts such as RNG streams, timers, input, and crowd state.

Provide development pause/step/speed and resource controls; available frame/simulation timings and enemy counts; and concise performance comparisons. Measure capture/bridge overhead and offer lower-overhead settings. On the target machine, agree useful performance targets and report measurements rather than inventing universal numbers.

The Balance workspace selects jobs, seeds, and `GF_TUNE` or equivalent overrides, queues comparisons, and displays outcomes with code, bot, fixture, and parameter versions. Use short targeted experiments by default. Cache reusable snapshots only with valid identities. Full multi-hour balance runs (`playtest.gd -- workers=4`, ~2.5 h) are explicit experiments, not correctness gates for routine edits.

Human play remains the judge of feel, clarity, and enjoyment. Distinguish bot metrics from those judgments.

## 11. Checks, change provenance, and safe undo

| Mode | Behavior |
| --- | --- |
| Fast | Small focused edit; cheapest relevant verification |
| Standard | Targeted tests plus affected integration/smoke checks |
| Harden | Broader checkpoint/release checks or justified high-risk verification |

Select checks by changed behavior and dependencies, not just filename count. Explain escalation briefly. Keep full correctness checks available; do not weaken tests to create passing results.

Inspect the actual runners, check exit status/timeouts as well as expected results, add useful suite selection and timings, and consolidate redundant work where correctness is preserved. Reuse `tests/st_*.gd` and existing harnesses before adopting another framework. Separate game checks from hub checks. Keep unrelated failures visible without silently expanding the task.

Record the exact tested working-tree content, including relevant uncommitted/untracked files, plus toolchain, configuration, and scenario. A commit SHA alone is insufficient during local development. Invalidate stale results, ensure running jobs use a stable input snapshot, and show the source revision versus running build.

Record task baseline, files changed, patches, assets, and resulting content. Implement review of individual edits and a coherent task change set. A partial acceptance may require dependency warnings and rechecking.

Undo must preserve earlier user edits and later unrelated work. Use task patches/snapshots with expected-content checks and three-way resolution as appropriate. Do not use blanket reset or restore against an unknown working tree. If changes overlap or depend on each other, show a concrete conflict/revert plan. Test with pre-existing edits, subsequent manual edits, renamed/deleted files, and assets.

Scope controls and preserved requirements must be checked against the actual result, not merely stored in a prompt.

## 12. Creative tools and Asset Studio

Provide shared user/agent workflows for UI design, sketching, sprites/animation, image generation, and 3D/rendered assets. Evaluate these initial candidates:

| Role | Candidate and intended connection | Known constraint to resolve with Tyler |
| --- | --- | --- |
| UI design | Penpot: design workspace plus supported plugin/MCP/API adapter | Self-hosting is documented mainly through Docker, which conflicts with "avoid Docker". The hosted version avoids Docker but keeps designs in the cloud. Ask before choosing. Fallback: design in Excalidraw plus live Godot UI. |
| Sketch/annotation | Excalidraw: embedded drawing surface | — |
| Sprites and animation | Pixelorama: connected editor/web build plus supported export or extension bridge | — |
| Image generation | ComfyUI: optional local service with repeatable jobs and previews | Needs a capable GPU. Check the hardware before committing to it. |
| Models/rendered sprites | Blender: connected desktop app with Python/CLI jobs | — |

The roles are required full-scope capabilities; the named implementations are candidates, not a requirement to adopt every framework. Explain and ask before substituting a materially different creative workflow. Build adapters incrementally. Hardware-heavy services and editors start only when enabled or needed; their absence must not prevent using the core hub.

For each integration, document supported user and agent operations, version/license, embedding versus launch/control, source/export formats, setup, and proof. Opening a website is not a completed AI integration. Do not claim arbitrary editing if only export is supported. Separate model licenses/hardware needs from the surrounding application's license.

Track assets by stable ID, editable source, exports, dimensions, animation data, origin/license, versions, and uses in the game. Support generation/import, variants, manual edits, preview, export, game import, and comparison/revert. Keep originals. Show impact on references before replacement.

Create an editable Corehold style guide covering palette, typography, icon conventions, dimensions, and visual references to support consistent outputs (start from `ui/Kit.gd`, the neon UI kit). Avoid asking image generation to replace precise editable UI construction. Translate selected designs into actual Godot code/resources and check the live result.

## 13. Backend, tools, skills, rules, and extensibility

### Claude Code connection (D1)

The hub is a **custom front-end over the `claude` CLI, signed in with Tyler's Claude Max plan**. The hub's own interface (game view, annotations, task and question cards, specialist chats) is what Tyler sees. Underneath, each task is a headless Claude Code session the hub starts and talks to over stream-json. It never asks for, stores, or falls back to an Anthropic API key. Tyler's existing Claude Code configuration (CLAUDE.md files, skills, hooks, MCP servers, subagents) is the agent engine. The hub adds a game-aware interface around it rather than a second agent framework.

**What the docs said (checked 2026-10-06; re-verify with `claude --help` and https://code.claude.com/docs on the machine):**

- **The `claude` CLI runs on the subscription.** The authentication docs say a token from `claude setup-token` "authenticates with your Claude subscription" for "scripts, or other environments where interactive browser login isn't available". The hub may also inherit the normal interactive login on the same machine. Verify which one is needed.
- **The Claude Agent SDK is out under D1.** Its overview says: "Anthropic does not allow third party developers to offer claude.ai login or rate limits for their products, including agents built on the Claude Agent SDK. Use the API key authentication methods…" Don't build on the SDK. Reading its source to understand the CLI's stream-json protocol is fine.
- **Headless integration surface:** `claude -p` with `--output-format stream-json` and `--input-format stream-json`, `--session-id <uuid>` / `--resume <id>`, `--model`, `--effort`, `--permission-mode`, `--allowedTools`, `--permission-prompt-tool <mcp tool>`, `--mcp-config`, `--append-system-prompt[-file]`, and `--max-turns`. Read the real values from the installed build and show them. Don't hard-code them.
- **Questions:** `AskUserQuestion` exists, but the documented way for a host to answer it is the SDK's `canUseTool` callback, which is ruled out. The docs also say it "is not currently available in subagents". Verify what the CLI does with it in stream-json mode.
- **Cancellation:** SIGINT ends a turn gracefully, while SIGTERM exits mid-turn. Verify both on Windows, where signals behave differently and the hub must stop the whole process tree.
- **Usage:** the final `result` message reports `total_cost_usd`. On a subscription that figure is an API-equivalent estimate, not Tyler's bill, so label it that way.
- **Working alongside an interactive session:** Claude Code plugins/mods can add panes and commands in the terminal and desktop app, but not in `-p` mode. Remote Control steers a local session from a browser or phone on a subscription. MCP servers expose tools on request, but the docs show no way for an MCP server to push messages into a running session.

**Route to prove in Milestone A** (recommended; change it only with Tyler's agreement):

1. **The hub drives the `claude` CLI.** A hub-owned supervisor runs `claude -p` in stream-json mode for each task, using an explicit `--session-id` that is stored in the task record. It runs in the right working directory, so Tyler's CLAUDE.md files, skills, hooks and subagents apply as usual. Keep one long-lived process per session, writing user messages to stdin, rather than a new process per turn. On Windows, resolve the `claude` binary the way claudecodeui does (`server/shared/claude-cli-path.ts`, which handles the `.cmd` shim); reimplement it rather than copying it, since that code is AGPL.
2. **The hub's own MCP server gives Claude game abilities.** It is passed with `--mcp-config` and exposes tools such as `game_launch`, `game_capture`, `get_selection`, `run_checks`, and `ask_user`. Users and agents share these same operations (tool registry, below).
3. **Questions. Test the native route first:** `--permission-prompt-tool mcp__hub__approve`, served by the hub's MCP server, receives `AskUserQuestion` and permission requests. Answering would mean returning `{behavior: "allow", updatedInput: {…answers}}`. The SDK uses this same mechanism internally, but it is unverified for the CLI flag, so it gets tested first in A.4. **Fallback: the hub's own `ask_user` tool.** It writes a durable question record (§6), with the specialist ID taken from the calling context, and tells Claude to end the turn. When Tyler answers, the hub resumes that exact session with `--resume <id>` and the answer. This works in `-p` mode, survives restarts, and doesn't depend on an `AskUserQuestion` host hook. If subagents can't call MCP tools, routing through the task owner covers them (§6). If a native `AskUserQuestion` route is documented for the CLI, it can be used instead.
4. **Images:** send captures as base64 `image` content blocks inside stream-json user messages. claudecodeui does this through the same CLI; verify it in A. Never pass images on the command line (Windows length limits). Otherwise save the capture into the task folder and reference its path so Claude reads it with the Read tool, which keeps the image and annotation consistent (§8).
5. **Optional extra:** a Claude Code mod/pane plus the same MCP server, so game tools also work in Tyler's ordinary interactive Claude Code sessions.

### Backend

Prefer one modest local service and durable local storage unless the chosen shell already provides them. Avoid unnecessary distributed orchestration.

Maintain a project registry, stable task/session/job IDs, structured event stream, file watcher, task database, and versioned configuration. Distinguish queued, running, waiting for user, paused, cancelled, failed, and completed states. Keep task completion separate from user acceptance.

Persist pending questions, tool results, decisions, artifacts, and recovery information. After interruption, reconcile job/process state and outputs before retrying. Use idempotency/readback for repeatable operations; do not claim exactly-once execution for arbitrary external tools. Cancellation must stop the correct process tree or show that work is still stopping.

The provider adapter supports verified model selection, sessions, streaming, questions, tools, cancellation, and usage where Claude Code reports it. Keep it replaceable without duplicating the agent engine. Persist explicit session IDs; never resume whichever unrelated session happens to be latest. Recheck context after external edits.

Expose a tool registry with schemas, versions, side effects, current availability, settings, and results. Users and agents use the same operations. Expose a skill manager with selective loading, editable workflows, version history, and explicit invocation. Tools execute repeatable actions; skills explain how/when to use them.

Show effective local rules, their sources, precedence, scope, and known conflicts. Separate declared configuration, observed skill/tool use, and information Claude Code does not expose. Do not promise access to hidden internal model reasoning or exact hidden prompts.

Create a compact context builder attaching only relevant files/features, selected image/state, task answers, and current decisions. Exclude secrets and unnecessary generated binaries/log history. State where requests go and show whatever usage information is available, with unavailable values clearly marked. On a subscription, show plan-limit/usage information if Claude Code exposes it. Label `total_cost_usd` as an API-equivalent estimate, not a bill. Show per-task time spent in agent activity versus builds, tests, capture, and generation.

Provide a documented plugin/adapter contract with lifecycle, settings, capability discovery, UI extension points, job/artifact reporting, and version compatibility. Include one small working example. Installed plugins are trusted local code unless actually isolated; do not advertise a sandbox you have not implemented. Inspect executable hooks/plugins before enabling unfamiliar downloads.

Keep local execution endpoints authenticated to the intended session and bound to localhost. Separate credentials from browser code, chat logs, and exportable configuration, and never read or copy Claude Code's stored login credentials. Make project data/config exportable and restorable; keep startup recovery and uninstall/disable behavior predictable.

## 14. Learning, memory, and improvement of the suite

Teach Me mode gives brief explanations of what changed, why, how it was checked, and one useful concept. Add Explain this code and Show me how actions. Keep teaching optional per task and globally.

Store curated decisions/preferences with source, scope, date, and relevance. Provide an editable "What the suite remembers" view. Separate game facts, preferences, specialist notes, and abandoned ideas. Never silently promote an inference into a permanent instruction.

Agents may recommend suite improvements from repeated friction. Put proposals in a quiet inbox with the observed need, benefit, scope, UI impact, maintenance cost, and verification. Tyler can Build, Adjust, or Dismiss; related suggestions should consolidate.

The Workbench specialist can implement accepted suite tasks in a separate branch/process context. Do not hot-patch the live hub's own code or database during unrelated game work. Support build/verify/restart or staged update and rollback, including configuration/database compatibility. Preserve active task recovery.

Use a small representative agent benchmark for significant changes to instructions/adapters: focused UI edit, game-rule change, question/resume, and cross-system task. Measure task correctness, time, unnecessary edits, and verification. Do not run this benchmark on every game task.

## 15. Reuse and research

Investigate only candidates relevant to the current milestone, using official documentation and actual source. Pin the versions/commits you select. Repositories worth evaluating:

- https://github.com/siteboon/claudecodeui (now "CloudCLI UI"). **Evaluated 2026-10-06 (v1.37.3, active, AGPL-3.0): not a base.**
  - Its core imports the Agent SDK (`claude-runtime.provider.js`), which conflicts with D1. It is also large (~119k lines) and multi-provider.
  - Worth borrowing: question/permission cards with no timeout, base64 image blocks, Windows `claude` path resolution, and a tab-plugin model.
- https://github.com/winfunc/opcode. **Evaluated 2026-10-06 (v0.2.0, dormant since 2025-10, AGPL-3.0): not a base.**
  - It spawns the raw CLI, but every call uses `--dangerously-skip-permissions`, so it has no question or permission handling.
  - Images travel as data URLs on the command line, there's PostHog telemetry, and it has no plugin system.
- Recommendation from that evaluation: **a small custom shell** that borrows patterns from claudecodeui (§13, "Route to prove in Milestone A"). Confirm with Tyler once A proves the route.
- https://github.com/anthropics/claude-agent-sdk-typescript: reference only. Its docs require API-key auth for third-party apps, which conflicts with D1 (§13). It's still useful for understanding the CLI's stream-json protocol.
- https://github.com/anthropics/skills: workflow references; inspect individual licenses.
- https://github.com/modelcontextprotocol/inspector: integration diagnostics.
- https://github.com/letsagents/godot-mcp and https://github.com/Coding-Solo/godot-mcp: game/editor adapters to verify against this project.
- https://github.com/excalidraw/excalidraw
- https://github.com/penpot/penpot
- https://github.com/Orama-Interactive/Pixelorama
- https://github.com/Comfy-Org/ComfyUI
- Blender's official source/documentation.
- https://github.com/langfuse/langfuse: optional observability when simple local logs are insufficient.

This list is not an installation checklist or a promise of compatibility. Verify maintainability, Windows behavior, question handling, image input, licenses, and extension points. Prefer an adapter/plugin to a deep fork. Read source to understand behavior; prefer supported interfaces over fragile undocumented integrations. For any shell that wraps Claude Code, confirm how it authenticates and that it works with a subscription login under D1.

## 16. Milestones and persistent execution

| Milestone | Required working result |
| --- | --- |
| 0 — Safe ground | Save isolation fixed in the game (D5); Workbench repo created with these docs; doctor confirms toolchain and Claude Code login on the real machine |
| A — Feasibility | Real local game launch/capture, real Claude Code connection on the subscription, question round-trip, one reversible edit; chosen architecture and setup route |
| B — Daily usable hub | Play/annotation request loop, persistent Tasks, Collaborative/Uninterrupted modes, actual edits/checks/diff/undo, launcher and external editor/terminal access |
| C — Visual specialist workflow | Game Map, direct specialist chats, bounded routing/handoffs, scope highlighting, external-change detection |
| D — Game development tools | Selectable game bridge, scenarios, reproduction, debug controls, performance, balance experiments |
| E — Creative workspace | Asset registry and working adapters covering UI, sketching, sprites/animation, generation, and 3D/rendered assets; on-demand services |
| F — Expandable suite | Tool/skill/rules managers, teach/memory views, improvement inbox, separate Workbench development, extension example, recovery/update polish |

After B there is one value check with Tyler: is the hub making game work faster? Adjust C–F based on the answer. This is not a ritual approval gate. The rules for working through milestones are in `WORKBENCH_CLAUDE.md`.

## 17. Acceptance demonstrations and handoff

Maintain executable or repeatable evidence for the cases below. Use real Claude Code calls sparingly for integration proof and test doubles for routine contract tests, and label them accurately. The milestone column says which demo proves which milestone. A demo is due when its milestone closes, not before.

| # | Demonstration | Due |
| --- | --- | --- |
| 1 | Select local project, start the hub, connect Claude Code on the subscription with the actual configured model, and launch the game with isolated saves. | A |
| 2 | Select/annotate a real element, ask for a change, answer a question with Other, implement a local edit, run focused checks, restart/replay, compare, and keep or revert. | B |
| 3 | Resize/change display scale and switch Play/Inspect; annotations remain aligned and no input stays stuck. | B |
| 4 | Start from a Game Map feature; inspect/edit through its specialist. Perform a cross-system handoff and a specialist-originated question without a wrong-session answer or conflicting overwrite. | C |
| 5 | Edit code manually outside the hub; mappings/context/check freshness update and the running-build indicator remains truthful, including uncommitted changes. | C |
| 6 | Demonstrate undo with pre-existing edits and later overlapping edits. Preserve unrelated content and resolve conflicts explicitly. | B |
| 7 | Close/restart while waiting for an answer or while a job is interrupted; recover the correct state without a duplicate destructive action. | B |
| 8 | Launch scenarios, capture a bug, run a short balance comparison, inspect performance, and verify personal saves remain untouched. | D |
| 9 | Perform real asset workflows covering the requested roles; display unavailable hardware/services honestly and keep the hub usable when they are off. | E |
| 10 | Inspect/edit a skill and rule, identify its source and actual invocation, use Teach Me, and correct a remembered preference. | F |
| 11 | Submit an improvement proposal, implement an accepted Workbench change separately, restart safely, and demonstrate recovery/rollback. | F |
| 12 | Launch using the documented normal startup path and disable/uninstall optional tools without breaking the core project. | F |

Agree practical usability/performance targets on the actual machine during discovery. Demonstrate the main loop without requiring repeated terminal setup. Screenshots of a polished mockup do not count as live integration evidence.

Deliver working source, launcher/setup instructions, pinned dependency/tool versions, configuration and data locations, extension documentation/example, third-party notices, results tied to source identity, and a truthful requirement-by-requirement status in the ledger: implemented, verified, partial, blocked, or not started.
