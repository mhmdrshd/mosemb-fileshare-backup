# backup_docs.sh — Project Roadmap

A `backup_docs.sh` tool built the slow way on purpose: one concept per commit,
so the git history itself is a study log. Rebuilding piece by piece (instead of
dumping a finished script) means `git log --oneline` reads back as the learning
arc.

**Learner profile:** intermediate Linux sysadmin, "zero to hero" on Bash. Wants
the *why* behind every construct — the concrete failure each pattern prevents —
not just working code. Assume bash on modern Linux, not POSIX sh.

**Target:** production-grade, robust script. Google Shell Style Guide,
ShellCheck-clean, defensive scripting, secure defaults.

---

## The loop — run for every chunk

1. **Explore** — read files, discuss the concept. No code written yet.
2. **Plan** — agree scope of this chunk: inputs, outputs, side effects, failure
   modes. One concept per chunk.
3. **Code** — write only that chunk. Justify any construct not explicitly asked
   for.
4. **Verify** — `shellcheck backup_docs.sh`, then a manual run or dry-run.
5. **Commit** — one commit, one logical change, crafted message.

**Tooling split:** teach/plan in web claude.ai (long-form, preserves context);
build/verify/commit in Claude Code inside the repo (sees files, runs tools).

---

## Commit convention — Conventional Commits

Format: `type(scope): imperative summary` → blank line → body explaining **why**.
The body is where the learning notes live.

| type       | meaning                                          |
|------------|--------------------------------------------------|
| `feat`     | new capability the script didn't have before     |
| `fix`      | repair something that was broken                 |
| `refactor` | restructure with identical behavior              |
| `docs`     | README, comments, example config — no code       |
| `test`     | add/adjust tests, no behavior change             |
| `chore`    | housekeeping: .gitignore, tooling, deps          |

Rules: imperative mood ("add", not "added"); summary ≤ 50 chars; body wrapped at
72; **one logical change per commit** (a fix + a feature = two commits). Commit
without `-m` so the editor opens and you write the body deliberately; use
`git add -p` to stage hunks with intent.

---

## Milestones

Each milestone ≈ one Claude Code session, 1–3 commits.

- [x] **1. Skeleton** — shebang, `set -Eeuo pipefail`, `IFS=$'\n\t'`, `main()`
  entry point, `readonly` constants. A green, shellcheck-clean baseline.
  `feat(core): add script skeleton with strict mode`

- [ ] **2. Logging module** — `log()`, `err()`, timestamps, `-v` verbosity flag.
  First piece of the reusable library (→ `lib/log.sh` eventually). Route info to
  stdout, errors to stderr.
  `feat(log): add timestamped logging helpers`

- [ ] **3. Config loading** — commit `backup.conf.example`; source the real
  `backup.conf` and validate (fail fast if required vars unset, e.g.
  `${VAR:?message}`). Real config stays gitignored.
  `docs(config): add example config` · `feat(config): source and validate config`

- [ ] **4. Argument parsing** — `getopts` for `-n` (dry-run), `-v` (verbose),
  `-c <config>`, `-h` (help/usage). Validate inputs, clear error on bad flags.
  `feat(cli): add getopts argument parsing`

- [ ] **5. Preflight gate** — port `smb-mount-check.sh` logic in as a sourced
  module/function: DNS → ping → TCP 445 → mount verification. Backup refuses to
  run if checks fail. (The planned integration step.)
  `feat(preflight): gate backup on SMB connectivity checks`

- [ ] **6. Disk-space check + rsync core** — pre-flight free-space check,
  array-as-command pattern for rsync, filter rules for `.pdf/.doc/.docx`,
  `--dry-run` wired to `-n`.
  `feat(backup): add disk-space check and rsync copy`

- [ ] **7. Traps** — ERR trap reporting failing line number; EXIT trap for
  cleanup (temp files, mounts). Relies on `-E` set back in milestone 1.
  `feat(core): add ERR and EXIT traps`

- [ ] **8. Tests** — Bats-core basics. Test pure functions first (config
  validation, arg parsing) by sourcing the script.
  `test: add bats tests for config and arg parsing`

---

## Priming Claude Code (paste once per session)

```
We're in explore→plan→code mode. Explain the concept first, propose a
plan, wait for my OK, then write ONLY that chunk. Run shellcheck after.
Suggest a conventional commit message but let me edit before committing.
I'm a "zero to hero" learner — I want the WHY behind every construct,
not just the code. Follow the milestones in ROADMAP.md.
```

---

## Style guardrails (enforce on every chunk)

- Quote all variable expansions unless there's a deliberate documented reason.
- Functions + `main()` entry point, never top-level spaghetti.
- Validate all inputs; fail fast with clear error messages.
- ShellCheck-clean; avoid useless `cat`, unguarded `rm -rf`, word-splitting bugs.
- For anything that modifies the system: offer a dry-run and state the risk.

---

## Header cheat-sheet (milestone 1, keep for reference)

| construct           | prevents                                                  |
|---------------------|-----------------------------------------------------------|
| `#!/usr/bin/env bash` | running under sh / wrong bash path on another distro    |
| `set -e`            | continuing after a failed command (e.g. failed `cd`)      |
| `set -u`            | unset-var typo expanding to empty → `rm -rf /`            |
| `set -o pipefail`   | a mid-pipe failure being masked by a happy last stage     |
| `set -E`            | ERR trap silently not firing inside functions             |
| `IFS=$'\n\t'`       | `Q3 Report.pdf` splitting into two bad paths              |
| `main "$@"`         | untestable, unreadable top-level logic                    |
| `readonly`          | accidental reassignment of constants                      |
