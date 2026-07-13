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
│   matrix: hydor + sedna (x86_64), tislit (aarch64)                │
│                                                                    │
│   1. nix-installer-action with KRYPTONIX_ACCESS_TOKEN              │
│      + extra-substituters s3://… (incremental builds)              │
│   2. Assume NixCacheWriter via GitHub OIDC                         │
│      + pass the session to nix-daemon                              │
│   3. nix build --override-input nixpkgs <branch tip>               │
│        .#nixosConfigurations.${host}.config.system.build.toplevel  │
│   4. nix store sign --recursive --key-file (CACHE_SIGNING_KEY)     │
│   5. nix copy --to "s3://bucket?…&secret-key=…" $out               │
│   6. write latest.json + aws s3 cp to hosts/${host}/latest.json    │
└───────────────────────────────────────────────────────────────────┘
                              │ HTTPS (OIDC role, write+read)
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
                              │ HTTPS (IAM user <host>, read-only)
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

Three least-privilege AWS identities:

- `NixCacheWriter`: IAM role with `s3:PutObject`, `s3:GetObject`,
  and `s3:ListBucket`. Its OIDC trust policy only accepts GitHub Actions
  tokens for this repository's `main` branch. `build-and-push.yml` assumes it
  through `aws-actions/configure-aws-credentials`.
- `NixCacheReader`: IAM role with `s3:GetObject` and `s3:ListBucket`.
  `flake-check.yml` and the Pages build assume it through GitHub OIDC. Its
  trust policy accepts this repository's `main` and `pull_request` subjects.
- `<host>`: read-only IAM user, with `s3:GetObject` and
  `s3:ListBucket`, created **once per host** rather than shared. Each host's
  long-lived credentials live in its own
  `nixosConfigurations/<host>/secrets/nix-cache-credentials.age`,
  encrypted so only that host's own SSH key (plus the master keys) can
  decrypt it, then decrypted by agenix into `EnvironmentFile`-format and
  supplied to `nix-daemon` and to the `system-pull` systemd unit. Because
  each host holds a distinct access key, revoking or rotating one host's
  credentials has no effect on the others.

GitHub Actions stores no long-lived AWS access keys. Jobs request a GitHub
OIDC token using `id-token: write`, exchange it with AWS STS, and receive
temporary role credentials for that job. The writer and reader role
identifiers are non-secret workflow configuration.

The credentials action writes the temporary session to the runner's
mode-`0600` default AWS profile without exporting credential environment
variables. Each workflow copies that profile to a root-only file under
`/run`, points `nix-daemon.service` at it with
`AWS_SHARED_CREDENTIALS_FILE`, and restarts the daemon. Build and Push
refreshes both copies after the build, but only on the aarch64 matrix leg,
since that's the one long enough to occasionally outlast the default one-hour
STS session; the x86_64 hosts build well within it. An `always()` cleanup
step removes both credential files when the job finishes.

The reader trust policy deliberately authorizes the repository's
`pull_request` subject. PR jobs can therefore read the private cache but
cannot modify it. Keep the writer role restricted to `main`; broadening
its subject would allow proposed workflow code to obtain `s3:PutObject`.

The signing key lives in two places:

- GitHub Actions secret `CACHE_SIGNING_KEY` (the private half, used at
  build time).
- `nixosConfigurations/shared/secrets/cache-signing-key.age`:
  disaster-recovery backup. No host needs the private key at runtime.

The public half is committed in cleartext as the default value of the
`publicKey` option in `nixosModules/binary-cache.nix`. Its key name is
`nix-cache.thoughtfull.systems-1`; every `trusted-public-keys` entry must use
that exact name because Nix matches signatures by name as well as key
material.

## Data flow per daily run

1. GitHub Actions matrix triggers at 02:00 UTC (and on every push to `main`).
2. Each matrix job exchanges its GitHub OIDC token for temporary credentials
   from the `NixCacheWriter` role and passes them to the Nix daemon.
3. Each matrix job builds
   `.#nixosConfigurations.<host>.config.system.build.toplevel`, with
   `--override-input nixpkgs github:NixOS/nixpkgs/nixos-26.05` so the daily
   build picks up the latest tip of the release branch.
4. The build step uses the S3 cache itself as an additional substituter
   (`extra-substituters` in the installer config), so already-pushed paths
   are downloaded instead of rebuilt. The configured upstream caches provide
   their respective build products.
5. The job refreshes its OIDC session and the daemon's credentials after the
   build.
6. `nix store sign --recursive` signs the closure with the private signing
   key.
7. `nix copy --to s3://bucket?…` uploads any newly built NARs + narinfos
   (existing paths are no-ops).
8. `aws s3 cp` atomically writes
   `hosts/<host>/latest.json = {storePath, gitRev, builtAt}` with
   `Cache-Control: no-cache`.
9. At 03:00 UTC (headless) / 12:00 local (graphical), the `system-pull.timer`
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
- `/run/agenix/nix-cache-credentials`—decrypted IAM credentials,
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

Tradeoff: every host still needs its own long-lived AWS IAM credential.
Rotating one host's key requires agenix re-encryption and a deploy to that
host only (see runbook); other hosts are unaffected. CI uses short-lived
OIDC role sessions and has no AWS key rotation procedure.
