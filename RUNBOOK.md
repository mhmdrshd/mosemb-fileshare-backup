# RUNBOOK — First Real Backup (Arch laptop → SMB share → 4TB external SSD)

Setup today, first real run tomorrow. `backup_docs.sh` is the engine; this
runbook covers everything around it. Placeholders in `<angle brackets>` —
real values go in the gitignored `backup.conf` and `/etc/cifs-credentials`,
never in this file.

---

## 1. Strategy & sizing (the shot-calls)

**Engine: rsync via `backup_docs.sh`.** Not restic/borg — honest tradeoff:
those give deduplication, encryption, and built-in verify, but store backups
in an opaque repository format. A plain rsync mirror is browsable with a file
manager on any Linux box, which is the property you want most when the server
is on fire. Revisit restic if versioning needs outgrow `--link-dest`.

**Sizing reality for the 4TB SSD:**

| item | value |
|---|---|
| Marketing 4TB | 3.64 TiB real |
| ext4 with `-m 1` (1% reserved, not the default 5%) | ~3.55 TiB usable |
| Full 2TB share mirror | leaves ~1.5 TiB headroom |
| Docs-only subset (what the script filters today) | far less; measure with the `--stats` dry-run below |

**Growth control, in order of defense:**
1. The script's `MIN_FREE_GB` floor — set it to **200** for a 4TB drive. The
   run refuses before the drive fills, and the message prints need-vs-have.
2. No `--delete`: the mirror only grows. Renamed folders on the share arrive
   as duplicates (old + new). Budget for it; prune manually when noticed.
3. Retention (once `--link-dest` snapshots land, post-roadmap): keep
   7 daily / 4 weekly / 6 monthly; a snapshot costs only changed bytes plus
   ~0.5–1 GB of hardlink metadata per million files. Prune oldest snapshots
   whenever free space drops under 2× MIN_FREE_GB. **Hardlinks require the
   ext4 decision below — this future is impossible on exFAT.**

**First-run duration estimate:** wired GbE moves ~110 MB/s → a full 2 TB pull
is 5–6 h; the docs-only subset will be a fraction of that. Wi-Fi can triple
it — use the cable for the first run.

---

## 2. Destination filesystem: reformat exFAT → ext4

exFAT is the wrong tool for a Linux backup target, on four counts:
- **No hardlinks** → no `--link-dest` snapshots, ever.
- **2-second mtime granularity + local-time storage** → rsync's quick-check
  misfires around DST/reboots; you'd need `--modify-window=2` forever and
  still get spurious recopies.
- **No POSIX permissions** — everything fake-owned, nothing enforceable.
- **No journal** → a yanked cable mid-write risks the whole directory tree,
  not just the file in flight.

Tradeoff accepted: the SSD stops being natively readable on Windows.
For a backup drive driven by Linux tooling that's fine (WSL2 or ext4 drivers
exist for emergencies).

```bash
# Identify the SSD - TRIPLE CHECK the device letter. lsblk sizes don't lie.
lsblk -f

# DESTRUCTIVE from here: wipes the exFAT SSD. Only <SSD_DEV>, e.g. /dev/sdb.
sudo wipefs -a <SSD_DEV>
sudo parted <SSD_DEV> -- mklabel gpt mkpart backup ext4 0% 100%
sudo mkfs.ext4 -L backupssd -m 1 <SSD_DEV>1     # -m 1: reclaim ~150GB from the 5% root reserve
```

Persistent, safe mounting — by LABEL (device letters shuffle), `nofail` so a
disconnected SSD never hangs boot:

```bash
sudo mkdir -p /mnt/backup
echo 'LABEL=backupssd  /mnt/backup  ext4  defaults,noatime,nofail,x-systemd.device-timeout=10  0 2' | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount /mnt/backup
mkdir -p /mnt/backup/docs        # BACKUP_DEST, created once, on the mounted drive
```

---

## 3. SMB access (setup today)

```bash
sudo pacman -S cifs-utils smbclient    # cifs-utils = mount; smbclient = diagnostics
```

**Credentials** — root-owned, mode 600, outside every repo and every home dir:

```bash
sudo install -m 600 -o root -g root /dev/null /etc/cifs-credentials
sudoedit /etc/cifs-credentials
```
```
username=<AD_USER>
password=<PASSWORD>
domain=<AD_DOMAIN>
```

**Mount via fstab + systemd automount** (mounts on first access, retries
gracefully, no boot-order fights). One line per share — note **`ro`**: a
backup source should be impossible to damage from this laptop:

```
//<SMB_SERVER>/<SHARE_NAME>  /mnt/smb/<SHARE_NAME>  cifs  credentials=/etc/cifs-credentials,ro,uid=<LOCAL_USER>,gid=<LOCAL_USER>,file_mode=0644,dir_mode=0755,iocharset=utf8,vers=3.1.1,noauto,x-systemd.automount,x-systemd.idle-timeout=300,_netdev,nofail  0 0
```

```bash
sudo mkdir -p /mnt/smb/<SHARE_NAME>
sudo systemctl daemon-reload
ls /mnt/smb/<SHARE_NAME>        # first access triggers the automount
```

If `vers=3.1.1` fails, step down to `vers=3.0` (see troubleshooting).

**Health check = the script's own preflight.** `./backup_docs.sh -n` runs
DNS → ping → TCP 445 → mountpoint checks before touching anything. That's
what it was built for.

---

## 4. Tomorrow's runbook

```bash
cd <REPO_DIR>

# 0. Config: copy the example, fill real values. Gitignored - keep it that way.
cp backup.conf.example backup.conf && $EDITOR backup.conf
#    SOURCE_DIRS=(/mnt/smb/<SHARE_NAME> ...)   BACKUP_MOUNT="/mnt/backup"
#    BACKUP_DEST="/mnt/backup/docs"            MIN_FREE_GB=200
#    SMB_SERVER="<SMB_SERVER_FQDN>"            LOG_FILE="$HOME/backup_docs.log"

# 1. Both mounts up?
findmnt /mnt/backup && findmnt /mnt/smb/<SHARE_NAME>

# 2. Free space with your own eyes (the script re-checks):
df -h /mnt/backup

# 3. DRY-RUN, logged. Full preflight + itemized would-be copies:
./backup_docs.sh -vn 2>&1 | tee ~/backup-dryrun-$(date +%F).log

# 4. Read the dry-run log before anything real:
grep -c '^>f' ~/backup-dryrun-*.log       # file count about right?
grep 'ERROR' ~/backup-dryrun-*.log        # must be empty
# Spot-check the itemized list: paths sane? spaces intact? no junk?

# 5. Exact size the real run needs (rsync --stats on one source, dry):
rsync -rtn --stats --prune-empty-dirs --include='*/' \
  --include='*.[pP][dD][fF]' --include='*.[dD][oO][cC]' --include='*.[dD][oO][cC][xX]' \
  --exclude='*' /mnt/smb/<SHARE_NAME>/ /mnt/backup/docs/<SHARE_NAME>/ | grep 'total size'
# Compare against df from step 2. Abort here if it doesn't fit comfortably.

# 6. THE REAL RUN, logged:
./backup_docs.sh -v 2>&1 | tee ~/backup-run-$(date +%F).log

# 7. Verify (see section 5 for the full plan):
./backup_docs.sh -vn 2>&1 | tail -20      # re-dry-run: should itemize ~nothing
```

**Log reading:** every line is timestamped. `[ERROR] ... rsync failed for
<src> (exit N)` — the codes that matter:
| exit | meaning | action |
|---|---|---|
| 23 | partial transfer (some files unreadable/permission) | grep the rsync output for the filenames; usually server-side ACLs |
| 24 | files vanished mid-run (live share) | benign churn — rerun; second pass picks up survivors |
| 11/28 | destination I/O / no space | `df -h`; the floor should have caught it — check MIN_FREE_GB |
| 255 | connection died mid-run | see troubleshooting: timeouts |

---

## 5. Best practices applied

- **Ownership:** the `uid=/gid=` mount options make every share file appear
  owned by you; ext4 stores you as owner at dest. `-rt` copies no ownership —
  by design (CIFS ownership is synthetic). **NTFS ACLs are not preserved**:
  this backup protects *content*, not Windows permission trees. Accepted.
- **Symlinks:** don't exist on default CIFS mounts; `-rt` wouldn't follow
  them anyway. Non-issue.
- **Consistency on a live share:** rsync copies each file point-in-time; an
  Office file being edited mid-copy can arrive torn. Strategy: run outside
  office hours, and treat exit 24 / a noisy re-dry-run as "run it again."
- **Junk:** the whitelist filter already drops Thumbs.db, desktop.ini, etc.
  One known wrinkle: Office lock files (`~$Report.docx`) *do* match the docx
  pattern. Harmless few-KB files — or add `--exclude='~$*'` as the first
  filter in `run_backup` (one-line patch, do it before the run if it bothers).
- **Verification (silent-incompleteness defense), in order of strength:**
  1. Re-dry-run itemizes ~nothing → source and dest agree by size+mtime.
  2. Counts per type: `find /mnt/smb/<SHARE> -iname '*.pdf' | wc -l` vs the
     same `find` on the dest — numbers should match.
  3. Open a handful of files from the *dest* (oldest, newest, one with
     spaces in the path). A backup you haven't opened a file from is a hope,
     not a backup.
  4. `du -sh` source vs dest — same ballpark (dest slightly smaller: ext4
     vs CIFS block accounting).

---

## 6. Troubleshooting

| symptom | first commands | usual cause |
|---|---|---|
| mount error(13): Permission denied | `sudo dmesg \| tail`; check `/etc/cifs-credentials` syntax (no quotes, no trailing spaces) | wrong password/domain; or account lacks share access |
| mount error(95)/(2) or "Operation not supported" | retry with `vers=3.0`, then `vers=2.1` in fstab | server rejects 3.1.1 dialect |
| mount hangs / error(115) timeout | `getent hosts <SMB_SERVER>`; `ping <IP>`; `timeout 3 bash -c ':>/dev/tcp/<SMB_SERVER>/445'` | DNS (VPN hijack — check `resolv.conf`!), firewall, wrong VLAN |
| name resolves wrong / not at all | `cat /etc/resolv.conf` — should list the AD DNS, not 8.8.8.8 | the S:-drive incident, Linux edition; disconnect VPN |
| "host is down" after sleep/resume | `sudo umount -l /mnt/smb/<SHARE>; ls /mnt/smb/<SHARE>` (automount remounts) | CIFS session died during suspend |
| rsync exit 23, "Permission denied" on specific files | note the paths; try `smbclient //server/share -c 'get <file>'` with same creds | server-side ACL excludes your account from those folders |
| destination full mid-run | `df -h /mnt/backup`; raise floor, prune, rerun | floor set too low / renamed-folder duplication |
| wrong share path | `smbclient -L <SMB_SERVER> -U <AD_USER>` lists real share names | typo'd share name in fstab |

---

## 7. Open questions (answers change the commands above)

1. Windows Server version → is `vers=3.1.1` accepted, or do we pin 3.0?
2. Scope tomorrow: docs-only (script as built) — or is the full 2TB mirror
   also wanted? (Changes sizing, duration, and whether filters get a bypass.)
3. Is there anything on the exFAT SSD today that must be saved before wipefs?
4. Which AD account mounts the share, and is read-only access acceptable
   (`ro` in fstab — recommended)?
5. Wired GbE available for the first pull, or Wi-Fi only?
