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
   `nixosModules/binary-cache.nix` and as the `extra-trusted-public-keys`
   value in `.github/workflows/build-and-push.yml`. Replace
   `REPLACE_WITH_BASE64_PUBLIC_KEY` in both places.

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

6. **Create two IAM users.** `nix-cache-ci` (write) and `nix-cache-host`
   (read-only), with policies scoped to
   `arn:aws:s3:::thoughtfull-nix-cache` and `/*`.

   Policy for `nix-cache-ci`:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Action": ["s3:PutObject", "s3:GetObject", "s3:ListBucket"],
       "Resource": [
         "arn:aws:s3:::thoughtfull-nix-cache",
         "arn:aws:s3:::thoughtfull-nix-cache/*"
       ]
     }]
   }
   ```

   Policy for `nix-cache-host`: same but without `s3:PutObject`.

7. **Paste `nix-cache-ci` credentials into GitHub Actions** as
   `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`.

8. **Encrypt the `nix-cache-host` credentials.** Write the file in
   `EnvironmentFile` format:
   ```bash
   cat > /tmp/creds <<EOF
   AWS_ACCESS_KEY_ID=AKIA...
   AWS_SECRET_ACCESS_KEY=...
   AWS_DEFAULT_REGION=us-east-1
   EOF
   nixfiles secret encrypt shared nix-cache-host-credentials < /tmp/creds
   shred -u /tmp/creds
   ```

9. **Point the modules at the encrypted file.** In each host config that
   should pull from the cache (typically all of them after provisioning),
   set:
   ```nix
   thoughtfull.binaryCache.awsCredentialsFile =
     ../nixosConfigurations/shared/secrets/nix-cache-host-credentials.age;
   ```
   Or, to flip it for all hosts at once, change the default in
   `nixosModules/binary-cache.nix`.

10. **Smoke-test the workflow.**
    ```bash
    gh workflow run build-and-push.yml
    gh run watch
    ```
    Both matrix jobs should land. Then:
    ```bash
    AWS_PROFILE=<host-profile> aws s3 cp \
      s3://thoughtfull-nix-cache/hosts/sedna/latest.json -
    ```
    Returns a `{storePath, gitRev, builtAt}` JSON object.

11. **Roll out the credentials option to hosts** by `nixos-rebuild
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
3. Bootstrap the host with `nixos-anywhere` or the installer image. During
   the first deploy, the operator's environment must have the GitHub PAT
   so the flake fetches private inputs.
4. After first boot, the host's daily `system-pull.timer` is the
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
4. Run `nixfiles` re-encrypt step if the host's SSH key was one of the
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
- **AWS credentials expired.** Rotate per section 7.
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

## 7. Rotating CI AWS credentials

1. In AWS IAM, generate a new access key for `nix-cache-ci`.
2. Update GitHub Actions secrets `AWS_ACCESS_KEY_ID` and
   `AWS_SECRET_ACCESS_KEY`.
3. Trigger the workflow to confirm:
   `gh workflow run build-and-push.yml`.
4. Delete the old access key in IAM.

---

## 8. Rotating host AWS credentials

1. In AWS IAM, generate a new access key for `nix-cache-host`.
2. Write the new credentials as `EnvironmentFile` format and re-encrypt:
   ```bash
   cat > /tmp/creds <<EOF
   AWS_ACCESS_KEY_ID=AKIA...
   AWS_SECRET_ACCESS_KEY=...
   AWS_DEFAULT_REGION=us-east-1
   EOF
   nixfiles secret encrypt shared nix-cache-host-credentials < /tmp/creds
   shred -u /tmp/creds
   git commit -am "Rotate cache host AWS credentials"
   git push
   ```
3. Trigger the workflow so the next pull-from-S3 source is the just-committed
   `main`.
4. On each host, run `systemctl start system-pull.service`. (Or wait one
   day for the timer.)
5. Once every host has switched generations, delete the old access key in
   IAM.

If a host can't pull (e.g., it was offline during rotation), keep the old
key alive temporarily and rotate that host out-of-band with
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
