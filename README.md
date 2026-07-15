# mosemb-fileshare-backup

A defensive Bash tool that backs up documents from Windows SMB file shares
to an external drive — built so that the *worst* thing it can ever do is
refuse to run.

```
config ──▶ preflight gate ──▶ destination gate ──▶ rsync
 fail        DNS · ping        mounted? · under      docs only,
 fast        TCP 445 ·         mount? · writable?    incremental,
 at load     mounts live?      space floor?          never deletes
```

Every stage can say no. Nothing copies until everything says yes.

## Why bother?

Most backup scripts are five lines of rsync that work until the day they
don't — and that day looks like this:

- The CIFS share silently unmounted, so rsync saw an **empty directory**
  and happily mirrored the emptiness.
- The external drive wasn't plugged in, so the "backup" quietly **filled
  the root filesystem** — and reported success.
- A VPN client hijacked DNS, the server name stopped resolving, and the
  error blamed SMB instead of the actual cause.
- Windows users saved `Report.PDF` and `Notes.Doc`, and the case-sensitive
  filter **skipped them silently, forever**.

This script exists because each of those is a real failure mode (one of
them is a documented incident in this very homelab). Each one is guarded,
tested, and explained in a commit message.

## Quick start

```bash
git clone <this repo> && cd mosemb-fileshare-backup
cp backup.conf.example backup.conf   # fill in your paths; stays gitignored
./backup_docs.sh -n                  # dry-run: full gate + what WOULD copy
./backup_docs.sh                     # the real thing
```

First time on real hardware? Follow [RUNBOOK.md](RUNBOOK.md) — the
step-by-step plan for mounts, credentials, filesystem choice, and the
first supervised run.

## Usage

```
Usage: backup_docs.sh [-n] [-v] [-c CONFIG] [-h]

  -n           dry-run: show what would be copied, change nothing
  -v           verbose: show debug messages
  -c CONFIG    config file to use (default: backup.conf next to the script)
  -h           show this help and exit
```

Exit codes follow convention: `0` success, `1` runtime failure (a gate
refused, or rsync failed), `2` usage error, `127`-style codes pass through
unmangled. Flags bundle (`-nv`) like any Unix tool.

## Configuration

Copy `backup.conf.example` to `backup.conf` (gitignored — machine paths and
share names never enter history) and set six variables:

| Variable | What it is |
|---|---|
| `SOURCE_DIRS` | Bash **array** of CIFS mountpoints to back up (arrays survive spaces in paths — `Q3 Reports` stays one path) |
| `SMB_SERVER` | File server **FQDN** — not IP; IP mapping breaks Kerberos |
| `BACKUP_MOUNT` | Mountpoint of the external drive — verified before every run |
| `BACKUP_DEST` | Where copies land; must live under `BACKUP_MOUNT` (validated) |
| `MIN_FREE_GB` | Refuse to run below this free-space floor; `0` disables |
| `LOG_FILE` | Reserved for file logging (validated, not yet consumed) |

Every variable is checked at startup — a missing or malformed value fails
in the first second with a message naming the variable, not twenty minutes
in with a stack of rsync errors.

## What actually gets copied

Documents only — `.pdf`, `.doc`, `.docx` in **any casing** (rsync has no
case-insensitive filters, so the patterns are character classes:
`*.[pP][dD][fF]`). Empty directory skeletons are pruned. Copies are
incremental: unchanged files (by size + mtime) are skipped, so run two is
minutes where run one was hours. Nothing is ever deleted from the
destination — a deletion on the share does not propagate to your backup.

## Testing & development

```bash
bats test/                    # 27 tests: parsing, config, gates, preflight
shellcheck *.sh lib/*.sh      # must pass clean - project law
shfmt -d .                    # formatting enforced via .editorconfig
```

The script is testable because sourcing it loads functions without running
them (`BASH_SOURCE` entry guard), and `lib/preflight.sh` runs under any
caller that provides three logger functions — the tests use stubs.

**Requirements:** bash 5.x, `rsync`, `cifs-utils`; everything else
(`getent`, `ping`, `timeout`, `mountpoint`) ships with any Linux.
Dev extras: `shellcheck`, `shfmt`, `bats`.

## Repository layout

| Path | Purpose |
|---|---|
| `backup_docs.sh` | The tool |
| `lib/preflight.sh` | SMB connectivity checks (sourced module) |
| `backup.conf.example` | Config template — copy, edit, keep private |
| `test/` | bats suite |
| `RUNBOOK.md` | First-real-backup procedure: mounts, filesystem, verification |
| `ROADMAP.md` | The 8-milestone build plan (complete) and commit conventions |
| `CLAUDE.md` | Workflow and safety rules for AI-assisted sessions |

## The other thing this repo is

This tool was built the slow way on purpose: **one concept per commit**,
each commit body explaining the concrete failure the new construct
prevents. That makes the Git history itself the documentation — and a
readable Bash course:

```bash
git log --oneline --reverse   # strict mode → logging → config → CLI →
                              # preflight → rsync core → traps → tests
```

If a design choice looks over-engineered for a backup script, read the
commit that introduced it. There's a failure story in every one.

## Safety principles

Project law, enforced by code and workflow — not good intentions:

1. **Refuse over guess.** Unresolvable server, dead mount, absent drive,
   low disk — the run aborts with a named reason. No partial heroics.
2. **Dry-run first.** `-n` runs the entire gauntlet and itemizes what
   would change, touching nothing.
3. **Never delete.** No `--delete`, by design. The destination only grows.
4. **Secrets stay out.** Credentials live in root-owned files outside the
   repo; the real config is gitignored.
5. **Fail loud.** `set -Eeuo pipefail` plus an ERR trap that reports the
   exit code, line, function, and exact command of any unplanned death.

## Status

All 8 roadmap milestones are complete and tested (27/27). Remaining:
first validation run against real hardware — see [RUNBOOK.md](RUNBOOK.md).

## License

[MIT](LICENSE)
