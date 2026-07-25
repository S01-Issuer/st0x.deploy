#!/usr/bin/env bash
# Freeze the rolling `candidate` snapshot as a numbered release snapshot, then
# regenerate the deploy pointer libs.
#
# Invoked by rainix-tag-release as its `snapshot-generate-cmd`, AFTER the
# reusable has resolved the release version from the pushed `sol-vX.Y.Z` tag and
# written it to `foundry.toml` `[package].version`. So the version is read from
# `foundry.toml` here — the single source of truth at this point.
#
# Model: `src/generated/candidate/` is the rolling snapshot of what the current
# source compiles to (regenerated every BuildPointers run). A numbered snapshot
# (`0_1_4/`, …) is a FROZEN copy of `candidate` taken at the instant a tag
# releases it — it never changes again (the frozen-snapshots-append-only gate
# enforces this). This script performs that copy, then re-runs BuildPointers so
# the pointer libs pick up the new numbered alias set alongside `candidate`.
set -euo pipefail

VERSION="$(grep -m1 -E '^version = ' foundry.toml | sed -E 's/^version = "([^"]+)"/\1/')"
if [ -z "$VERSION" ]; then
  echo "cut-release: could not read [package].version from foundry.toml" >&2
  exit 1
fi
TAG="${VERSION//./_}"

if [ ! -d src/generated/candidate ]; then
  echo "cut-release: src/generated/candidate is missing — nothing to freeze" >&2
  exit 1
fi

echo "cut-release: freezing candidate -> src/generated/${TAG}"
rm -rf "src/generated/${TAG}"
cp -r src/generated/candidate "src/generated/${TAG}"

# Regenerate candidate (idempotent — source unchanged) and the pointer libs,
# which now emit the new numbered alias set in addition to `candidate`.
forge script ./script/BuildPointers.sol
forge fmt
