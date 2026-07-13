# mosemb-fileshare-backup

Bash tooling to back up documents from `MOSEMB.LOCAL` SMB file shares to external SSD storage.

Runs on Linux (including WSL) inside a Windows Active Directory environment, reading from CIFS-mounted shares and copying with `rsync`.

> **Status: early development (v0.1.0).** The script skeleton and logging module are in place; scanning and copying are not implemented yet. See the roadmap below.

## What this repo also is

This is a working homelab tool **and** a structured Bash learning project. The rules that follow from that:

- Every construct in the code exists because of a concrete failure it prevents — not "best practice" for its own sake.
- One concept per commit. Commit bodies are learning-journal entries; the Git history doubles as a study log.
- [Conventional Commits](https://www.conventionalcommits.org/) throughout (`feat`, `fix`, `docs`, `refactor`, `chore`, `test`).

If a design choice looks over-engineered for a 47-line script, that is why. It is being built to production-grade standards on purpose.

## Repository layout

| File | Purpose |
|---|---|
| `backup_docs.sh` | The backup tool (main script) |
| `ROADMAP.md` | Milestones, commit conventions, and project context |
| `CLAUDE.md` | Workflow and safety rules for AI-assisted sessions (Claude Code) |
| `LICENSE` | MIT |

## Usage

```bash
./backup_docs.sh              # normal run
VERBOSE=1 ./backup_docs.sh    # with debug output (env hook; getopts flags planned)
```

Currently the script starts, logs, and exits — the backup logic lands in upcoming milestones.

### Requirements

- Bash 5.x on Linux or WSL
- `rsync`
- `cifs-utils` (SMB shares mounted via CIFS)
- `shellcheck` (development)

## Roadmap

| Milestone | Scope | Status |
|---|---|---|
| 1 | Script skeleton: strict mode, constants, `main()` entry point | ✅ Done |
| 2 | Logging module: `log` / `err` / `debug`, stdout vs stderr, verbosity | ✅ Done |
| 3 | SMB preflight gate (integrate `smb-mount-check.sh` connectivity checks) | Planned |
| 4 | Argument parsing with `getopts` (`--dry-run`, verbosity flags) | Planned |
| 5+ | Document scanning, rsync copy logic, filters | Planned |

Full details in [ROADMAP.md](ROADMAP.md).

## Safety principles

These are project law, enforced by workflow rules (and, eventually, Claude Code hooks):

1. **Dry-run first.** No `rsync` against a real destination without a prior `--dry-run` pass.
2. **Never delete on the destination** without explicit, per-run confirmation.
3. **Secrets stay out.** CIFS credential files are never read, printed, or committed.
4. **Fail fast, fail loud.** `set -Eeuo pipefail`, input validation, clear errors on stderr.

## Development

```bash
shellcheck backup_docs.sh   # must pass clean before any milestone is "done"
```

## License

[MIT](LICENSE)
