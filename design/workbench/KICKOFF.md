# Corehold Workbench — kickoff

**How to use:** open **Claude Code on your PC** (terminal, desktop app, or IDE; not a cloud session) in your local Corehold game folder. Make sure Claude Code is logged in with your Claude Max account (not an API key): run `claude` and check `/status`. Then paste the prompt below. You only paste it once. After Milestone 0 the Workbench repo's own `CLAUDE.md` loads automatically, and "continue" is enough.

---

```text
We're starting Corehold Workbench, a local development hub for my game. It's my own custom front-end built on top of the claude CLI, running on my Claude Max plan (no API key).

If design/workbench/ doesn't exist in this checkout, fetch it first: `git fetch origin claude/sleepy-hopper-p2hn8k` and bring the design/workbench/ folder in without touching my other files (ask me if anything would be overwritten).

Read these in order:
1. design/workbench/WORKBENCH_CLAUDE.md (your working rules for this project; follow them from now on)
2. design/workbench/LEDGER.md (status, decisions, open questions)
3. §0 and §2 of design/workbench/WORKBENCH_SPEC.md (read other sections only when a milestone needs them)

Then do Milestone 0:
- Inspect this machine and repo per spec §2: OS, git state, toolchain, and how Claude Code is logged in. Don't print any credentials.
- Back up my saves folder (%APPDATA%\Corehold-PC) to a dated folder before anything else touches the game.
- Save isolation (D5) was fixed on branch claude/sleepy-hopper-p2hn8k (ledger row 0.2). After the backup, bring that branch's changes into my checkout without touching my uncommitted work (ask me how if there's any conflict). Then re-verify on this machine: run selftest with the local Godot (the bash gate is Linux-only until ledger 0.5) and confirm my real save files are byte-identical afterwards. Don't run selftest, uitest, _shots, playtest or the gate before the fix is in this checkout.
- Ask me the first short round of open questions from the ledger, with your recommendations. Only ask the ones that matter now.
- After I answer: create the Workbench repo where we agreed. Install WORKBENCH_CLAUDE.md as its CLAUDE.md, and the spec and ledger as docs/WORKBENCH_SPEC.md and docs/LEDGER.md. Replace design/workbench/ in the game repo with a short README pointing to the new location. Make local commits only; don't push.
- Update the ledger and continue into Milestone A.
```
