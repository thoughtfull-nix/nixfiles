# Binary cache: architecture

This document describes how the `thoughtfull-nix` fleet upgrades itself. For
operational procedures (provisioning, rotations, debugging), see
[`binary-cache-runbook.md`](./binary-cache-runbook.md).

## Goals

Hosts in the fleet are upgraded daily without:

- Each host fetching the flake source from GitHub (no per-host PAT needed).
- Each host re-evaluating and compiling NixOS (a Raspberry Pi 4 building
  `tislit` is unhappy).
- Operating a separate build server (no EC2 instance to keep alive).

GitHub Actions is the trusted builder. AWS S3 is the only piece of cloud
infrastructure. Every host pulls a pre-built, signed system closure directly
from S3 once a day.

## Topology

```
┌───────────────────────────────────────────────────────────────────┐
│ GitHub Actions  (.github/workflows/build-and-push.yml)            │
│   daily cron, push-to-main, workflow_dispatch                     │
│   matrix: {sedna, ubuntu-24.04} {tislit, ubuntu-24.04-arm}        │
│                                                                    │
│   1. nix-installer-action with KRYPTONIX_ACCESS_TOKEN              │
│      + extra-substituters s3://… (incremental builds)              │
│   2. nix build --override-input nixpkgs <branch tip>               │
│        .#nixosConfigurations.${host}.config.system.build.toplevel  │
│   3. nix store sign --recursive --key-file (CACHE_SIGNING_KEY)     │
│   4. nix copy --to "s3://bucket?…&secret-key=…" $out               │
│   5. write latest.json + aws s3 cp to hosts/${host}/latest.json    │
└───────────────────────────────────────────────────────────────────┘
                              │ HTTPS (IAM user nixfiles-ci, write+read)
                              ▼
                  ┌─────────────────────────┐
                  │ AWS S3: thoughtfull-    │
                  │   nix-cache (private)   │
                  │   /<hash>.narinfo       │
                  │   /nar/...              │
                  │   /nix-cache-info       │
                  │   /hosts/${host}/       │
                  │       latest.json       │
                  └─────────────────────────┘
                              │ HTTPS (IAM user nixfiles-host, read-only)
                              ▼
                  ┌─────────────────────────┐
                  │ sedna, tislit (clients) │  daily systemd timer
                  │  - aws s3 cp latest.json│
                  │  - nix-store --realise  │   (s3:// substituter)
                  │  - nix-env --set        │
                  │  - switch-to-config…    │
                  └─────────────────────────┘
```

## Trust model

The signing key is the trust root. Any store path signed with it is trusted
by every host. The bucket being private is only a *confidentiality* control
(prevents store-path enumeration by outsiders); a public bucket would be
safe to *trust* but would leak hostnames, software versions, and config
shape.

Two IAM users:

- `nixfiles-ci`: write access (`s3:PutObject`, `s3:GetObject`,
  `s3:ListBucket`). Credentials live in GitHub Actions secrets
  `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`.
- `nixfiles-host`: read-only (`s3:GetObject`, `s3:ListBucket`).
  Credentials live in
  `nixosConfigurations/shared/secrets/nix-cache-host-credentials.age`,
  decrypted by agenix into `EnvironmentFile`-format and supplied to
  `nix-daemon` and to the `system-pull` systemd unit.

The signing key lives in two places:

- GitHub Actions secret `CACHE_SIGNING_KEY` (the private half, used at
  build time).
- `nixosConfigurations/shared/secrets/cache-signing-key.age`:
  disaster-recovery backup. No host needs the private key at runtime.

The public half is committed in cleartext as the default value of the
`publicKey` option in `nixosModules/binary-cache.nix`.

## Data flow per daily run

1. GitHub Actions matrix triggers at 02:00 UTC (and on every push to `main`).
2. Each matrix job builds
   `.#nixosConfigurations.<host>.config.system.build.toplevel`, with
   `--override-input nixpkgs github:NixOS/nixpkgs/nixos-25.11` so the daily
   build picks up the latest tip of the release branch.
3. The build step uses the S3 cache itself as an additional substituter
   (`extra-substituters` in the installer config), so already-pushed paths
   are downloaded instead of rebuilt. Magic Nix Cache handles build-time
   intermediates that never end up in the system closure.
4. `nix store sign --recursive` signs the closure with the private signing
   key.
5. `nix copy --to s3://bucket?…` uploads any newly built NARs + narinfos
   (existing paths are no-ops).
6. `aws s3 cp` atomically writes
   `hosts/<host>/latest.json = {storePath, gitRev, builtAt}` with
   `Cache-Control: no-cache`.
7. At 03:00 UTC (headless) / 12:00 local (graphical), the `system-pull.timer`
   on each host fires. The script `pkgs.thoughtfull.system-pull`:
   - Fetches `hosts/<hostname>/latest.json` with `aws s3 cp`.
   - Compares the target `storePath` with `readlink /run/current-system`;
     exits early if equal.
   - `nix-store --realise <storePath>` (substituter fetches signed NAR from
     S3, signature verified against the trusted public key).
   - `nix-env -p /nix/var/nix/profiles/system --set <storePath>` registers
     the generation so `nixos-rebuild list-generations` and rollback work.
   - `<storePath>/bin/switch-to-configuration switch` activates it.

## What updates daily vs only on commit

| Input | Source of fresh-ness |
|---|---|
| `nixpkgs` | `--override-input` to the release-branch tip on every CI run. |
| `nixfiles` (this repo) | `actions/checkout@v4` always reads the current tip of `main`. |
| `kryptonix`, `agenix`, `disko`, `impermanence`, `nixos-hardware`, `flake-utils`, `systems`, `devenv`, `unstable` | Pinned by `flake.lock`. Only update via a PR that runs `nix flake update <input>`. |

## File-system layout per host

- `/etc/ssh/ssh_host_ed25519_key` (or `/persistent/etc/ssh/ssh_host_ed25519_key`
  on impermanence-enabled hosts)—agenix identity for decrypting `.age`
  files at activation.
- `/run/agenix/nix-cache-host-credentials`—decrypted IAM credentials,
  referenced as `EnvironmentFile` by `nix-daemon` and `system-pull`.
- `/nix/var/nix/profiles/system`—generation pointer updated by `system-pull`.
- `/run/current-system`—symlink to the active generation.

## S3 bucket layout

```
s3://thoughtfull-nix-cache/
├── nix-cache-info               # written by `nix copy --to s3://…`
├── <hash>.narinfo               # one per store path
├── nar/<hash>.nar.xz            # NAR blobs
└── hosts/
    ├── sedna/latest.json        # { storePath, gitRev, builtAt }
    └── tislit/latest.json
```

Lifecycle rule: NAR blobs under `nar/` older than 60 days expire. (Naive v1
GC—dangling narinfos will simply make their entries cache-misses, and the
substituter falls back to building or to upstream caches.)

## Why no EC2 server

Earlier drafts of this design used a dedicated EC2 instance running
`harmonia` (or `nginx` proxying S3). Estimated cost ~$24/month for a
properly sized instance + EBS volume + bandwidth. The current S3-direct
design costs ~$5–7/month (storage + egress only) and removes:

- An always-on instance to keep updated and patched.
- A DNS record + ACME / Let's Encrypt cert.
- A long-running daemon (`harmonia` / `nginx`) to monitor.
- An EBS volume to size + grow + snapshot.

Tradeoff: every host needs an AWS IAM credential. Rotation requires
agenix re-encryption and a deploy to every host (see runbook).
