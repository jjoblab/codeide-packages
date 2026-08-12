# CodeIDE Packages

This repository provides the **minimal native runtime packages** and
**bootstrap environment** used by [CodeIDE](https://github.com/jjoblab) on
Android.

CodeIDE is an Android IDE aiming at compiling Android projects directly
on-device. This repo is the *terminal runtime* layer — a minimal
Termux-like environment with `bash`, `apt`, and the essential POSIX
utilities, natively compiled with the `jo.codeide` package identity.

---

## Quick start on Android (Termux)

If you received the `codeide-packages-minimal-aarch64.zip` archive and want to push it to your GitHub fork from an Android device (Termux), follow these steps.

> ⚠️ **Why this is needed**: when you extract a `.zip` on Android, the Unix executable bit on `.sh` files is **not preserved**. Running `./scripts/build-bootstraps.sh` then fails with `Permission denied`. The included `setup.sh` restores the exec bits before you commit them to git.

### Option A — one-shot helper (recommended)

```bash
# 1. Extract the zip on Android (Termux)
unzip /sdcard/Download/codeide-packages-minimal-aarch64.zip
cd codeide-packages

# 2. Run the all-in-one helper
bash android-push.sh
#   → restores +x on all .sh files
#   → git init
#   → git add -A (with correct 0755 mode in index)
#   → git commit
#   → renames branch to 'main' if needed
#   → adds remote https://github.com/jjoblab/codeide-packages.git

# 3. Push to GitHub
git push -u origin main
#   When prompted for credentials, use a Personal Access Token (PAT)
#   instead of your GitHub password.
#   Create one at: https://github.com/settings/tokens
```

### Option B — manual step-by-step

```bash
cd codeide-packages

# Restore exec bits lost during Android zip extraction
bash setup.sh

# Verify the bits are restored
ls -la build-package.sh scripts/build-bootstraps.sh

# Git init + commit with proper 0755 mode bits
git init
git config user.name "Your Name"
git config user.email "you@example.com"
git add -A
git commit -m "Initial commit: CodeIDE Packages minimal aarch64 bootstrap"

# Rename branch to 'main' (GitHub default — older git versions default to 'master')
git branch -M main

# Add remote and push
git remote add origin https://github.com/jjoblab/codeide-packages.git
git push -u origin main
```

### Why `git push -u origin main` fails with "src refspec main does not match any"

This error happens in two cases:

1. **Your local branch is named `master`, not `main`.** Older git versions default to `master` for `git init`. Fix: `git branch -M main` before pushing.
2. **You haven't committed anything yet.** You can't push an empty branch. Fix: `git add -A && git commit -m "..."` first.

### Why GitHub Actions might still fail

Even after a successful push, GitHub Actions needs:

- **Permissions**: the default `GITHUB_TOKEN` is enough for `contents: write` (release creation) and `contents: read` (checkout). No extra secrets needed for bootstrap building.
- **Actions enabled**: go to the repo's **Settings → Actions → General** and ensure "Allow all actions and reusable workflows" is selected.
- **Pages enabled** (for the APT repo workflow): go to **Settings → Pages** and set "Source" to "GitHub Actions" (not "Deploy from a branch" — the workflow handles deployment via `peaceiris/actions-gh-pages`).

### Verifying a built bootstrap locally

After the `Build Bootstrap (aarch64)` workflow runs, download the `bootstrap-aarch64.zip` artifact and run:

```bash
# On Android (Termux) or any Linux host
./test-bootstrap.sh bootstrap-aarch64.zip
# → checks zip size > 10 MB
# → checks bin/bash, bin/apt, bin/coreutils, ... are present
# → checks all ELF binaries are aarch64 (not x86_64 / ARM32)
# → checks zero 'com.termux' byte sequence in zip
# → checks 'jo.codeide' prefix is present
```

### Fixing a repo that was already pushed with broken permissions

If you already pushed `codeide-packages` to GitHub and the workflow fails with:

```
./scripts/run-docker.sh: Permission denied
Process completed with exit code 126.
```

…it means all your `.sh` files ended up as mode `100644` instead of `100755` in the git history. This typically happens because Android/Termux `git init` defaults to `core.filemode=false` on certain filesystems (e.g. `/sdcard` which is FAT-based), and `git add -A` then ignores the filesystem `+x` bit.

**One-shot fix** — run this on your Android (or any clone of the repo):

```bash
cd codeide-packages
bash fix-permissions.sh
git push
```

`fix-permissions.sh` uses `git update-index --chmod=+x`, which forces the exec bit in the git index **regardless of `core.filemode`**. After pushing, the GitHub Actions workflow will run a defensive `bash fix-permissions.sh --no-commit` step at the start, so even future commits with broken perms won't break the build.

You can verify the fix on GitHub with:

```bash
curl -s https://api.github.com/repos/jjoblab/codeide-packages/git/trees/main?recursive=1 \
  | grep -E '"mode": "100755"' | wc -l
# Should print a number > 3000
```

---

## Target architecture

**AArch64 only.** CodeIDE v1 does not target `arm`, `x86`, or `x86_64`.
Limiting to a single architecture keeps the bootstrap build under ~1 hour
in CI (vs 6+ hours for a full multi-arch build).

## Android package

```
jo.codeide
```

All runtime paths use:

```
/data/data/jo.codeide
/data/data/jo.codeide/files
/data/data/jo.codeide/files/usr   (PREFIX)
/data/data/jo.codeide/files/home   (HOME)
```

These are derived from `TERMUX_APP__PACKAGE_NAME="jo.codeide"` in
`scripts/properties.sh`. **No binary-patching, no runtime path rewriting —
every ELF binary is natively built with `jo.codeide` baked in.**

---

## Repository structure

```
.
├── README.md
├── LICENSE.md                 # GPLv3 — inherited from termux-packages
├── CONTRIBUTING.md            # Termux contributing guide (preserved)
├── bootstrap-packages.txt     # Minimal bootstrap package list (read by build-bootstraps.sh)
├── packages.txt               # APT repo installable package list (read by build-packages.yml)
├── repo.json                  # APT repo target config (URL, distribution, component)
├── build-package.sh           # Single-package builder (sourced from properties.sh)
├── build-all.sh               # Full-tree builder (NOT used by CodeIDE CI)
├── clean.sh                   # Cleans ~/.termux-build and built packages
├── setup.sh                   # ★ Restores +x bit on .sh files (run after zip extraction on Android)
├── android-push.sh            # ★ One-shot helper: setup + git init + commit + push for Android
├── test-bootstrap.sh          # Verifies a built bootstrap-aarch64.zip (run on any Linux host)
├── scripts/
│   ├── properties.sh          # Global vars (TERMUX_APP__PACKAGE_NAME=jo.codeide)
│   ├── build-bootstraps.sh    # ★ Bootstrap builder (reads bootstrap-packages.txt)
│   ├── generate-bootstraps.sh # Bootstrap from pre-compiled .deb (NOT USED — kept for reference)
│   ├── run-docker.sh          # Run a command inside ghcr.io/termux/package-builder
│   └── build/                 # 92 termux_*.sh build steps sourced by build-package.sh
├── packages/                  # ~1850 package recipes
├── x11-packages/              # X11 packages (not used by CodeIDE v1)
├── root-packages/             # Root-only packages (not used by CodeIDE v1)
└── disabled-packages/         # Disabled packages
```

---

## What's in the bootstrap

The bootstrap is intentionally **minimal**. See
[`bootstrap-packages.txt`](./bootstrap-packages.txt) for the exact list.

**Direct packages (16):**

| Package | Role |
|---------|------|
| `apt` | Package manager (essential) |
| `bash` | Default login shell |
| `dash` | POSIX `/bin/sh` |
| `coreutils` | `ls`, `cp`, `mv`, `rm`, `cat`, `mv`, `mkdir`, ... |
| `diffutils` | `diff`, `cmp` |
| `findutils` | `find`, `xargs`, `locate` |
| `grep` | Text search |
| `sed` | Stream editor |
| `tar` | Archive extraction (used by apt) |
| `gzip` | gzip compression |
| `unzip` | zip extraction |
| `libbz2` | bzip2 runtime library (used by tar / apt / unzip) |
| `termux-core` | Core CodeIDE/Termux runtime |
| `termux-exec` | `execve()` shim for prefix translation |
| `termux-keyring` | GPG keys for apt |
| `termux-tools` | `pkg`, `termux-*` helper scripts |

**Transitive dependencies** (auto-built by `build-package.sh` via
`scripts/buildorder.py` — not listed in `bootstrap-packages.txt`):

`dpkg`, `gpgv`, `libc++`, `libiconv`, `libgnutls`, `libgcrypt`, `liblzma`,
`liblz4`, `zstd`, `xxhash`, `zlib`, `openssl`, `libandroid-support`,
`libandroid-glob`, `libandroid-selinux`, `libandroid-posix-semaphore`,
`pcre2`, `readline`, `ncurses`, `libacl`, `libcap-ng`, `libsmartcols`,
`libgmp`, `libmpfr`, `bzip2`, `xz-utils`, `curl`, `dialog`, `termux-am`,
`termux-am-socket`, `termux-licenses`, `gawk`, `less`, `procps`, `psmisc`,
`util-linux`, ...

**Explicitly EXCLUDED** from the bootstrap (installable later via `apt install`):

`vim`, `neovim`, `nano`, `openssh`, `python`, `nodejs`, `cmake`, `ninja`,
`autoconf`, `automake`, `libtool`, `llvm`, `clang`, `git`, `make`, `gcc`,
`gdb`, `unrar`, `ed`, `dos2unix`, `inetutils`, `lsof`, `net-tools`, `patch`.

---

## GitHub Actions workflows

### `build-bootstrap-aarch64.yml`

Builds `bootstrap-aarch64.zip` from local package sources.

- **Trigger**: `workflow_dispatch` or push of a `bootstrap-*` tag.
- **Architecture**: `aarch64` only.
- **Output**: `bootstrap-aarch64.zip` artifact + GitHub Release on tag push.
- **Verifications**: zip size > 10 MB, `bin/bash` & `bin/apt` present,
  **zero** `com.termux` byte sequence in zip, ELF binaries are `aarch64`,
  prefix is `/data/data/jo.codeide/files/usr`.
- **Caching**: `~/.termux-build` and `/data` are cached across runs.

### `build-packages.yml`

Builds .deb for every package in `packages.txt` and publishes an APT
repository on GitHub Pages.

- **Trigger**: `workflow_dispatch`, `packages-*` tag push, or weekly cron.
- **Architecture**: `aarch64` only.
- **Output**: APT repo at `https://jjoblab.github.io/codeide-packages/apt/codeide-main`.
- **Native build**: no `-I` flag — dependencies are built from source to
  ensure 100% `jo.codeide` identity.

---

## Local development

### Prerequisites

- Docker (Linux or macOS — `run-docker.sh` handles both)
- ~5 GB free disk space for the build cache (`~/.termux-build`)
- The `ghcr.io/termux/package-builder` Docker image (auto-pulled by
  `run-docker.sh`)

### Build the bootstrap locally

```bash
# Default: aarch64, reads bootstrap-packages.txt
./scripts/run-docker.sh ./scripts/build-bootstraps.sh

# Force rebuild (ignore ~/.termux-build cache)
./scripts/run-docker.sh ./scripts/build-bootstraps.sh -f

# Add an extra package to the bootstrap (one-off)
./scripts/run-docker.sh ./scripts/build-bootstraps.sh --add openssh
```

The output `bootstrap-aarch64.zip` is placed at the repo root.

### Build a single package

```bash
./scripts/run-docker.sh ./build-package.sh -a aarch64 bash
```

### Build the full APT repository locally (slow)

```bash
./scripts/run-docker.sh ./build-all.sh -a aarch64
```

> ⚠️ `build-all.sh` builds the entire package tree (~1850 packages) and can
> take 6+ hours. For routine work, prefer building individual packages or
> use the GitHub Actions workflow.

---

## Configuring CodeIDE to use the APT repository

Once `build-packages.yml` has run at least once:

```bash
# Inside a running CodeIDE shell:
echo "deb https://jjoblab.github.io/codeide-packages/apt/codeide-main stable main" \
  > $PREFIX/etc/apt/sources.list.d/codeide.list
apt update
apt install <package>
```

---

## Differences from upstream Termux

This repository is derived from
[termux/termux-packages](https://github.com/termux/termux-packages).
The following modifications have been applied:

| Aspect | Termux upstream | CodeIDE Packages |
|--------|----------------|-------------------|
| Android package name | `com.termux` | `jo.codeide` |
| App namespace | `com.termux` | `jo.codeide` |
| Repo package name | `com.termux` | `jo.codeide` |
| Data dir | `/data/data/com.termux` | `/data/data/jo.codeide` |
| Prefix | `/data/data/com.termux/files/usr` | `/data/data/jo.codeide/files/usr` |
| Bootstrap builder | `generate-bootstraps.sh` (downloads .deb) | `build-bootstraps.sh` (native build from source) |
| Default archs | `aarch64`, `arm`, `i686`, `x86_64` | `aarch64` only |
| Bootstrap package list | Hardcoded (~30 pkgs incl. nano, ed, lsof) | `bootstrap-packages.txt` (16 direct pkgs, minimal) |
| APT repo URL | `packages-cf.termux.dev` | `jjoblab.github.io/codeide-packages/apt/codeide-main` |
| Workflows | ~10 (CodeQL, dependabot, autobuilds, ...) | 2 (`build-bootstrap-aarch64.yml`, `build-packages.yml`) |

The Termux build infrastructure (`build-package.sh`, `buildorder.py`,
Docker image, dependency resolver) is preserved unchanged — only what was
necessary to switch identity, reduce scope, and target `aarch64` has been
modified.

---

## Credits & license

This project is based on [termux/termux-packages](https://github.com/termux/termux-packages)
under the **GNU General Public License v3**. See [`LICENSE.md`](./LICENSE.md)
for the full text.

All Termux copyright notices and contributor credits are preserved — see
[`CONTRIBUTING.md`](./CONTRIBUTING.md) and `git log` for the upstream
history.

CodeIDE-specific modifications © jjoblab — same license (GPLv3).
