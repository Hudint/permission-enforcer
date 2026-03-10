# permission-watcher

A lightweight, event-driven Docker container that monitors directories and automatically fixes file ownership using inotify.

## Why?

Running `chown -R` on a timer is wasteful. It hammers the filesystem, burns CPU cycles, and still leaves a gap between runs where permissions are wrong. **permission-watcher** replaces that pattern with an event-based approach: the Linux kernel tells us exactly when a file changes, and we fix only what needs fixing — instantly.

## Features

- **Event-based, not polling** — uses `inotifywait` (inotify) to react to filesystem events in real time with near-zero idle CPU usage
- **Initial scan on startup** — catches any files that were created while the watcher was down
- **Minimal footprint** — Alpine Linux base image, ~8–9 MB total
- **UID/GID based** — uses numeric IDs instead of usernames, so it works correctly across container boundaries
- **Configurable via environment variables** — no need to rebuild the image for different setups
- **POSIX shell only** — runs on `/bin/sh` (ash), no bash dependency
- **Graceful logging** — timestamps and before/after ownership info for every fix

## How It Works

```
┌─────────────────────────────────────────────────┐
│              Container Startup                   │
│                                                  │
│  1. Read WATCH_DIR, TARGET_UID, TARGET_GID       │
│  2. Run initial full scan with `find`            │
│     └─ Fix any files with wrong ownership        │
│  3. Start `inotifywait` in monitor mode          │
│     └─ Listen for: create, moved_to, attrib      │
│  4. On event:                                    │
│     ├─ Check current UID:GID of the file         │
│     ├─ Compare against TARGET_UID:TARGET_GID     │
│     └─ Run `chown` only if they differ           │
└─────────────────────────────────────────────────┘
```
The watcher monitors three inotify event types:

- **create** — a new file or directory is created
- **moved_to** — a file is moved into the watched directory
- **attrib** — file attributes (including ownership) change

## Quick Start
```
docker run -d \
    --name ghcr.io/hudint/permission-enforcer:latest \
    -e TARGET_UID=1000 \
    -e TARGET_GID=1000 \
    -e TARGET_PERMISSIONS=775 \
    -v /path/to/your/directory:/data \
    permission-watcher
```

## Docker Compose
```
services:
  permission-watcher:
    build: .
    container_name: permission-watcher
    restart: unless-stopped
    environment:
      - TARGET_UID=1000
      - TARGET_GID=1000
      - TARGET_PERMISSIONS=775
    volumes:
      - /path/to/your/directory:/data
```

## Excluding Paths

You can exclude specific paths or filename patterns from both the initial scan and the live watcher using the `EXCLUDE_PATTERNS` environment variable.

`EXCLUDE_PATTERNS` accepts a **colon-separated list** of shell glob patterns. Any file or directory whose path matches one of the patterns will be skipped entirely — no `chown` or `chmod` will be applied.

### Examples

Exclude a specific directory:
```
EXCLUDE_PATTERNS=/data/logs
```

Exclude multiple patterns:
```
EXCLUDE_PATTERNS=/data/logs:/data/tmp/*:/data/cache
```

Exclude SQLite journal and WAL files (useful for live databases):
```
EXCLUDE_PATTERNS=/data/db/*.sqlite-journal:/data/db/*.sqlite-wal
```

### In Docker Compose

```yaml
services:
  permission-enforcer:
    image: ghcr.io/hudint/permission-enforcer:latest
    environment:
      - TARGET_UID=1000
      - TARGET_GID=1000
      - EXCLUDE_PATTERNS=/data/db/*.sqlite-journal:/data/tmp/*
    volumes:
      - /path/to/your/directory:/data
```

### Pattern Syntax

Patterns use standard POSIX shell glob matching:

| Pattern | Matches |
|---|---|
| `/data/logs` | Exactly `/data/logs` |
| `/data/tmp/*` | All files directly inside `/data/tmp/` |
| `/data/**` | Not supported — use `/data/subdir/*` per level |
| `*.sqlite-journal` | Only if the full path matches (anchored to root) |

> **Note:** Patterns are matched against the full absolute path of each file. Always use the full path as it appears inside the container (e.g. `/data/...`).

---

## inotify Limits

The Linux kernel limits the number of inotify watches per user. Each subdirectory in the watched tree consumes one watch. If your directory tree is large, you may hit the default limit.
The default is typically `8192` or `65536` depending on the distribution.

### Symptoms of hitting the limit

If you see errors like the following in the container logs, you need to increase the limit:

Failed to watch /data/some/deep/path; upper limit on inotify watches reached!