#!/usr/bin/env bash
set -euo pipefail

# Usage: push-to-cache.bash CACHE-URI SECRET-KEY-FILE STORE-PATH...
#
# Sign and upload the closures of STORE-PATHs to the S3 binary cache at
# CACHE-URI, skipping paths that cache.nixos.org or the cache already serve.
#
# A binary cache refuses a path whose references it doesn't hold, so `nix copy`
# can't upload a partial closure directly. Instead the missing paths are copied
# into a local staging cache seeded with stub narinfos for their references,
# and only the missing paths' own narinfos and NARs are uploaded.

cache=$1
secret_key=$2
shift 2
upstream=https://cache.nixos.org
bucket=${cache%%\?*}

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT

# Print the paths read from stdin that STORE lacks. Lookups are one request per
# path, so run them in parallel batches.
missing_from() {
  xargs -r -P 32 -n 50 nix-store --store "$1" --check-validity --print-invalid |
    sort -u
}

nix-store --query --requisites "$@" | sort -u >"$staging/closure"
missing_from "$upstream" <"$staging/closure" >"$staging/candidates"
missing_from "$cache" <"$staging/candidates" >"$staging/missing"

closure_count=$(wc -l <"$staging/closure")
missing_count=$(wc -l <"$staging/missing")
echo "push-to-cache: $missing_count of $closure_count closure paths to upload"
if [[ $missing_count -eq 0 ]]; then
  exit 0
fi

mkdir "$staging/cache"
xargs nix-store --query --references <"$staging/missing" | sort -u >"$staging/all-refs"
comm -23 "$staging/all-refs" "$staging/missing" >"$staging/refs"
if [[ -s "$staging/refs" ]]; then
  # The stubs only need to satisfy the staging cache's validity check; they are
  # deleted before upload.
  xargs nix-store --query --hash <"$staging/refs" >"$staging/hashes"
  xargs nix-store --query --size <"$staging/refs" >"$staging/sizes"
  paste "$staging/refs" "$staging/hashes" "$staging/sizes" |
    while read -r path hash size; do
      base=${path#/nix/store/}
      printf 'StorePath: %s\nURL: nar/stub\nNarHash: %s\nNarSize: %s\n' \
        "$path" "$hash" "$size" >"$staging/cache/${base%%-*}.narinfo"
      echo "$staging/cache/${base%%-*}.narinfo"
    done >"$staging/stubs"
fi

nix copy --no-recursive --stdin \
  --to "file://$staging/cache?compression=zstd&secret-key=$secret_key" \
  <"$staging/missing"

if [[ -s "$staging/stubs" ]]; then
  xargs rm -- <"$staging/stubs"
fi
rm -f "$staging/cache/nix-cache-info"

# NARs first, so no uploaded narinfo ever points at a missing NAR.
aws s3 cp --recursive --only-show-errors "$staging/cache/nar" "$bucket/nar"
aws s3 cp --recursive --only-show-errors "$staging/cache" "$bucket" --exclude 'nar/*'
