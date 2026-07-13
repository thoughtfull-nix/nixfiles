# Binary cache: runbook

Operational procedures for the daily build-and-pull pipeline. See
[`binary-cache.md`](./binary-cache.md) for the architecture this acts on.

Each section is self-contained. Prerequisites and exact commands first, then
verification.

---

## 1. Initial provisioning

One-time setup, performed by an operator with AWS console access and the
master agenix identity.

**Prerequisites:** AWS account, repo checked out, `direnv allow` to enter
the dev shell.

1. **Generate the cache signing key locally.** Never rotate this casually
   (see section 11).
   ```bash
   nix key generate-secret --key-name nix-cache.thoughtfull.systems-1 \
     > /tmp/cache-priv
   nix key convert-secret-to-public < /tmp/cache-priv > /tmp/cache-pub
   ```

2. **Commit the public half** as the default value of `publicKey` in
   `nixosModules/binary-cache.nix` and in the
   `extra-trusted-public-keys` values in `.github/workflows/`. Replace
   `REPLACE_WITH_BASE64_PUBLIC_KEY` in each place. Keep the exact
   `nix-cache.thoughtfull.systems-1` name in every location; Nix rejects a
   signature when the trusted key has a different name, even if its base64 key
   material matches.

3. **Encrypt and commit the signing-key backup.** No host needs it at
   runtime, but this is the disaster-recovery copy.
   ```bash
   nixfiles secret encrypt shared cache-signing-key < /tmp/cache-priv
   shred -u /tmp/cache-priv
   ```

4. **Paste the signing key into GitHub Actions.** Decrypt the just-encrypted
   backup and paste the multiline value:
   ```bash
   age -d -i master-identities.txt \
       nixosConfigurations/shared/secrets/cache-signing-key.age
   ```
   In the repo settings → Secrets and variables → Actions → New repository
   secret: `CACHE_SIGNING_KEY` ← paste the value.

5. **Create the S3 bucket.** AWS console or CLI:
   ```bash
   aws s3api create-bucket --bucket thoughtfull-nix-cache --region us-east-1
   aws s3api put-public-access-block --bucket thoughtfull-nix-cache \
     --public-access-block-configuration \
     "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
   ```
   Add a lifecycle rule: expire objects under prefix `nar/` after 60 days.

6. **Create the CI AWS identities.** CI uses short-lived GitHub OIDC roles;
   hosts each use their own long-lived read-only IAM user, created
   individually per host in section 2 (there is no single shared
   `nix-cache-host` user—see issue #215).

   The reader and publisher roles below share this read-only policy:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": "s3:ListBucket",
         "Resource": "arn:aws:s3:::thoughtfull-nix-cache"
       },
       {
         "Effect": "Allow",
         "Action": "s3:GetObject",
         "Resource": "arn:aws:s3:::thoughtfull-nix-cache/*"
       }
     ]
   }
   ```

   Add `https://token.actions.githubusercontent.com` as an IAM OIDC
   provider with audience `sts.amazonaws.com`. Then create these roles:

   - `NixfilesCacheReader`: the policy above; used by Flake Check and
     Pages.
   - `NixfilesCacheWriter`: the policy above plus `s3:PutObject` on
     `arn:aws:s3:::thoughtfull-nix-cache/*`; used by Build and Push.

   Use this trust-policy condition for `NixfilesCacheReader`:
   ```json
   "Condition": {
     "StringEquals": {
       "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
       "token.actions.githubusercontent.com:sub": [
         "repo:thoughtfull-nix/nixfiles:ref:refs/heads/main",
         "repo:thoughtfull-nix/nixfiles:pull_request"
       ]
     }
   }
   ```

   Restrict `NixfilesCacheWriter` to `main`:
   ```json
   "Condition": {
     "StringEquals": {
       "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
       "token.actions.githubusercontent.com:sub": "repo:thoughtfull-nix/nixfiles:ref:refs/heads/main"
     }
   }
   ```

   Both trust policies use the federated principal:
   `arn:aws:iam::481411455398:oidc-provider/token.actions.githubusercontent.com`
   and action `sts:AssumeRoleWithWebIdentity`.

7. **Verify the workflow role identifiers.** They're non-secret configuration
   committed in `.github/workflows/`:
   ```text
   arn:aws:iam::481411455398:role/NixfilesCacheReader
   arn:aws:iam::481411455398:role/NixfilesCacheWriter
   ```
   Do not create `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` GitHub
   Actions secrets. The workflows use `id-token: write` and
   `aws-actions/configure-aws-credentials` to obtain temporary credentials.
   The action writes a mode-`0600` default profile instead of exporting
   credential environment variables. Because `nix-daemon` runs under
   systemd, the workflows copy that profile to the root-only
   `/run/nix-daemon-aws-credentials`, set `AWS_SHARED_CREDENTIALS_FILE` in a
   service drop-in, and restart the daemon. Build and Push refreshes both
   profile copies after the build so long ARM builds don't upload with
   expired credentials. An `always()` step removes both files after use.
   When migrating an existing repository, delete those legacy secrets after
   a successful OIDC-authenticated run.

8. **Create and wire each host's own `nix-cache-host` IAM user and
   credentials**—see section 2, steps 3-4. Do this once per host in the
   initial fleet.

9. **Smoke-test the workflow.**
    ```bash
    gh workflow run build-and-push.yml
    gh run watch
    ```
    All matrix jobs should land. Then:
    ```bash
    AWS_PROFILE=<host-profile> aws s3 cp \
      s3://thoughtfull-nix-cache/hosts/sedna/latest.json -
    ```
    Returns a `{storePath, gitRev, builtAt}` JSON object.

10. **Roll out the credentials option to hosts** by `nixos-rebuild
    --target-host` from a workstation (operator still has the GitHub PAT
    in their env). After the first switch, the host's `system-pull.timer`
    is wired up and takes over.

---

## 2. Onboarding a new host

**Prerequisites:** host's `nixosConfigurations/<host>.nix` and any host-
specific secrets are committed.

1. Add `<host>` to the matrix in `.github/workflows/build-and-push.yml`,
   matching the runner type to the system arch
   (`ubuntu-24.04` for x86_64, `ubuntu-24.04-arm` for aarch64).
2. Trigger the workflow: `gh workflow run build-and-push.yml`. Wait for
   the host's build to push its closure and write
   `hosts/<host>/latest.json`.
3. **Create this host's own `nix-cache-host` IAM user.** In AWS IAM, create
   a user named `nix-cache-host-<host>` with the read-only policy from
   section 1 step 6, and generate an access key for it. Each host gets its
   own IAM user and key so that revoking or rotating one host's access
   never affects another host.
4. **Encrypt and wire this host's credentials.** Write the file in
   `EnvironmentFile` format and encrypt it to this host alone:
   ```bash
   cat > /tmp/creds <<EOF
   AWS_ACCESS_KEY_ID=AKIA...
   AWS_SECRET_ACCESS_KEY=...
   AWS_DEFAULT_REGION=us-east-1
   EOF
   nixfiles secret encrypt <host> nix-cache-host-credentials < /tmp/creds
   shred -u /tmp/creds
   ```
   Then point that host's config at its own encrypted file:
   ```nix
   thoughtfull.binaryCache.awsCredentialsFile =
     ./<host>/secrets/nix-cache-host-credentials.age;
   ```
5. Bootstrap the host with `nixos-anywhere` or the installer image. During
   the first deploy, the operator's environment must have the GitHub PAT
   so the flake fetches private inputs.
6. After first boot, the host's daily `system-pull.timer` is the
   self-updating mechanism. Confirm:
   ```bash
   systemctl start system-pull.service
   journalctl -u system-pull
   ```

---

## 3. Removing a host

1. Remove the host from the matrix in
   `.github/workflows/build-and-push.yml`.
2. Delete its pointer file (otherwise `system-pull` on a re-imaged host
   with the same name might pick up a stale closure):
   ```bash
   aws s3 rm s3://thoughtfull-nix-cache/hosts/<host>/latest.json
   ```
3. Archive the `nixosConfigurations/<host>.nix` and `<host>/` directory
   (delete or move).
4. Delete the host's `nix-cache-host-<host>` IAM user and access key in
   AWS IAM—it's no longer referenced by any other host's config.
5. Run `nixfiles` re-encrypt step if the host's SSH key was one of the
   recipients on any `.age` file.

---

## 4. Failed `system-pull` on a client

```bash
journalctl -u system-pull -n 100
# Manual rerun:
systemctl start system-pull.service
```

Common causes:

| Symptom | Likely cause | Fix |
|---|---|---|
| `AccessDenied` on `aws s3 cp` | Host IAM key revoked / rotated. | Run rotation procedure (section 8). |
| `pointer file did not contain a storePath` | CI job failed and never wrote `latest.json`, or write was partial. | Check workflow status (section 5); manually re-trigger. |
| `path … is required, but no substituter has it` | Closure was pushed but signature is wrong, or NAR was lifecycle-expired. | Check `nix-store --query --requisites $target` against the bucket; manually re-run the build (section 6). |
| Network-unreachable | Host offline / S3 endpoint blocked. | Verify connectivity; the timer's `Persistent=true` will retry on next boot/connectivity. |

Rollback if `switch-to-configuration` left the system in a bad state:
```bash
nixos-rebuild --rollback switch
```

---

## 5. Failed GitHub Actions build

Open the run on the GitHub Actions UI. Common causes:

- **`KRYPTONIX_ACCESS_TOKEN` expired.** Rotate per section 9.
- **OIDC role assumption failed.** Verify the provider, trust policy, and
  workflow subject per section 7.
- **S3 returned `AccessDenied` after role assumption.** Verify the assumed
  role's S3 policy and bucket ARN.
- **Transient nixpkgs eval failure**—re-run the job: `gh run rerun <id>`.
- **An aarch64 build genuinely too slow for the 6-hour limit.** Re-trigger
  off-hours after the cache has warmed up from related builds; the second
  attempt usually completes via S3 substituter hits.

To manually re-trigger: `gh workflow run build-and-push.yml`.

---

## 6. Manual unscheduled rebuild + pull

When you need a host to pick up a fresh commit immediately:

```bash
# 1. push the commit
git push origin main

# 2. wait for / trigger the build
gh workflow run build-and-push.yml
gh run watch

# 3. on the target host, force the pull now
systemctl start system-pull.service
```

---

## 7. Maintaining CI OIDC access

There are no long-lived CI AWS credentials to rotate. AWS STS issues a new
short-lived session for each job.

For `Not authorized to perform sts:AssumeRoleWithWebIdentity`:

1. Confirm the AWS account has the GitHub provider
   `https://token.actions.githubusercontent.com` with audience
   `sts.amazonaws.com`.
2. Confirm the role trust policy's `sub` matches the workflow context:
   `repo:thoughtfull-nix/nixfiles:ref:refs/heads/main` for main or
   `repo:thoughtfull-nix/nixfiles:pull_request` for a PR.
3. Confirm the job grants `id-token: write` and `contents: read`.
4. Confirm `role-to-assume` names the correct reader or publisher role.
5. Confirm `$HOME/.aws/credentials` and
   `/run/nix-daemon-aws-credentials` exist with mode `0600`, the
   `nix-daemon.service` drop-in sets `AWS_SHARED_CREDENTIALS_FILE` to the
   latter, and the daemon restarted after role assumption.

For an unexpected `AccessDenied` from S3 after assumption succeeds, inspect
the role's S3 permissions rather than its trust policy. Reader jobs need
`s3:GetObject` and `s3:ListBucket`; Build and Push additionally needs
`s3:PutObject`.

If the AWS CLI succeeds but Nix reports `Path is invalid` followed by an S3
403, the runner has credentials but `nix-daemon` does not. Check the root-only
profile copy, `AWS_SHARED_CREDENTIALS_FILE`, and daemon restart. If upload
fails only after a long build, check that the workflow refreshed both profile
copies immediately before `nix copy`.

After changing a trust or permissions policy, trigger
`gh workflow run build-and-push.yml` and verify the role session in the job
log. To revoke CI access immediately, remove the matching GitHub subject from
the role trust policy; there are no access keys to delete.

If the repository still has legacy `AWS_ACCESS_KEY_ID` or
`AWS_SECRET_ACCESS_KEY` Actions secrets from the pre-OIDC setup, delete them
after confirming all workflows use role assumption.

---

## 8. Rotating host AWS credentials

Each host has its own IAM user and key (section 2, step 3), so rotation is
per host and never touches other hosts' credentials.

1. In AWS IAM, generate a new access key for `nix-cache-host-<host>`.
2. Write the new credentials as `EnvironmentFile` format and re-encrypt to
   that host alone:
   ```bash
   cat > /tmp/creds <<EOF
   AWS_ACCESS_KEY_ID=AKIA...
   AWS_SECRET_ACCESS_KEY=...
   AWS_DEFAULT_REGION=us-east-1
   EOF
   nixfiles secret encrypt <host> nix-cache-host-credentials < /tmp/creds
   shred -u /tmp/creds
   git commit -am "Rotate <host> cache host AWS credentials"
   git push
   ```
3. Trigger the workflow so the next pull-from-S3 source is the just-committed
   `main`.
4. On `<host>`, run `systemctl start system-pull.service`. (Or wait one day
   for the timer.)
5. Once that host has switched generations, delete its old access key in
   IAM.

If the host can't pull (e.g., it was offline during rotation), keep the old
key alive temporarily and rotate it out-of-band with
`nixos-rebuild --target-host`.

---

## 9. Rotating the `KRYPTONIX_ACCESS_TOKEN`

1. Generate a new PAT on GitHub with `repo` scope.
2. Update the `KRYPTONIX_ACCESS_TOKEN` GitHub Actions secret.
3. Delete the old PAT.

Workstations no longer use this token (they pull closures, not source), so
no per-host action is needed.

---

## 10. Pinning the fleet to a known-good generation

When something broke and you want every host on yesterday's build until you
ship a fix:

```bash
# find yesterday's storePath from the CI run log or from S3:
aws s3 cp s3://thoughtfull-nix-cache/hosts/sedna/latest.json - | jq .

# manually write a pinned pointer for each host:
jq -n --arg p "/nix/store/<yesterday-hash>-nixos-system-sedna-…" \
      --arg r "<commit-sha>" \
      --arg t "$(date -u +%FT%TZ)" \
      '{storePath:$p, gitRev:$r, builtAt:$t}' \
  > /tmp/pinned.json
aws s3 cp /tmp/pinned.json \
  s3://thoughtfull-nix-cache/hosts/sedna/latest.json \
  --cache-control no-cache

# Repeat for tislit.
```

Disable the GitHub Actions workflow until you have a fix:
```bash
gh workflow disable build-and-push.yml
```

Don't forget to re-enable it after.

---

## 11. **DO NOT** rotate the signing key casually

The signing key is the trust root. Rotating it makes every previously pushed
closure untrusted by every host. If you must (suspected compromise):

1. Generate a new keypair (section 1.1).
2. Update `nixosModules/binary-cache.nix` (`publicKey` default) and
   `.github/workflows/build-and-push.yml`
   (`extra-trusted-public-keys`).
3. Re-encrypt `cache-signing-key.age` with the new private half. Update
   the `CACHE_SIGNING_KEY` GitHub Actions secret.
4. Empty the bucket (or leave it; old narinfos become unverifiable noise):
   ```bash
   aws s3 rm --recursive s3://thoughtfull-nix-cache/
   ```
5. **Clients cannot self-pull across this rotation**—they won't trust
   the new signature until they activate a generation with the updated
   `binary-cache.nix` (which trusts the new key). For each host, deploy
   from a workstation:
   ```bash
   nixos-rebuild --target-host sedna --use-remote-sudo switch \
     --flake .#sedna
   ```
6. Trigger the workflow to repopulate the bucket:
   `gh workflow run build-and-push.yml`.

---

## 12. Forcing manual S3 garbage collection

The lifecycle rule expires `nar/*` after 60 days. To clean up sooner:

```bash
# List objects under nar/ older than N days:
aws s3api list-objects-v2 --bucket thoughtfull-nix-cache --prefix nar/ \
  --query "Contents[?LastModified<='$(date -u -d '7 days ago' +%FT%TZ)'].Key" \
  --output text > /tmp/old-objects.txt
# Review, then delete:
xargs -a /tmp/old-objects.txt -I {} aws s3 rm "s3://thoughtfull-nix-cache/{}"
```

A more careful GC (walk `latest.json` per host, mark reachable closures,
delete the rest) is a v2 follow-up.

---

## 13. Updating other flake inputs

Inputs other than `nixpkgs` are pinned in `flake.lock` and only update via
explicit PRs.

```bash
nix flake update kryptonix  # or agenix, disko, impermanence, …
git checkout -b update-<input>
git commit -am "Update <input>"
gh pr create
# After merge: the next daily build picks up the new pin from main.
```

---

## 14. Disabling the cache temporarily

If the cache is broken and you want a host to continue receiving updates
via the legacy local-evaluation path:

```nix
# In nixosConfigurations/<host>.nix
thoughtfull = {
  systemPull.enable = false;
  binaryCache.enable = false;
  githubToken.tokenFile = ../nixosConfigurations/shared/secrets/github-access-token.age;
};
system.autoUpgrade.enable = true;
```

`nixos-rebuild --target-host` to apply. Revert when the cache is healthy
again.
