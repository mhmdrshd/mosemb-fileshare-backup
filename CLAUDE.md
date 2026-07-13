# CLAUDE.md

Solo learning repo: homelab backup tooling in Bash. Owner is learning Bash — the process rules below matter more than speed.

## Project
- `backup_docs.sh` — scans CIFS-mounted SMB shares for documents, copies to external drive via rsync.
- `smb-mount-check.sh` — 4-stage SMB connectivity preflight; will be integrated as a gate in `backup_docs.sh`.
- Milestones, commit convention, learner profile: see ROADMAP.md (source of truth — do not duplicate here).

## Environment
- bash 5.x on Linux + WSL; Windows AD domain; CIFS/SMB mounts.
- Tools: rsync, mount.cifs, shellcheck, shfmt, bats.
- Secrets (CIFS credential files, keys): never read, print, or commit.

## Commands
- Lint: `shellcheck *.sh && shfmt -d .`
- Test: `bats test/`
- Backup: dry-run only (`--dry-run` / `rsync -n`). Never run a real backup or touch the destination unprompted.

## Style
- Header: `#!/usr/bin/env bash`, `set -Eeuo pipefail`, `IFS=$'\n\t'`, `readonly` constants, `main()` entry point.
- `snake_case.sh` filenames; verb-first function names; quote all expansions.
- Shared helpers go in `lib/` — no copy-paste between scripts.
- shellcheck-clean is a requirement, not a suggestion.

## Workflow (learning mode — strict)
- Before writing any construct, name the failure it prevents.
- One concept per commit. Owner writes all commit messages and stages with `git add -p` himself — never commit on his behalf.
- Concept-dense changes: owner types, you review. Mechanical changes: draft, then walk through line by line.
- Tests pass before a milestone counts as done.

## Ask first
- Deleting files, restructuring the repo, adding dependencies, anything touching a backup destination or mounted share.
- Small in-file fixes: proceed without asking.
