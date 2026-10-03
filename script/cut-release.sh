#!/usr/bin/env bash
# SPDX-License-Identifier: LicenseRef-DCL-1.0
# SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
# Freeze the rolling `candidate` snapshot as a numbered release snapshot, then
# regenerate the deploy pointer libs.
#
# Invoked by rainix-tag-release as its `snapshot-generate-cmd`, AFTER the
# reusable has resolved the release version from the pushed `sol-vX.Y.Z` tag and
# written it to `foundry.toml` `[external.package].version`.
#
# Everything this used to do by hand is `LibRainDeploySnapshot.freeze`, reached
# through `BuildScript.cutRelease()`. It reads the version from
# `[external.package].version` itself, and it refuses a release the shell could
# not:
#
#   - a version that is not a strict `X.Y.Z` (`isStrictTriple`), which would
#     otherwise freeze a `0_1_30-rc1` directory the tag filter ignores forever
#   - a tag whose directory already exists (`SnapshotAlreadyFrozen`), so a
#     re-cut cannot clobber an audited snapshot
#   - a release with no contracts (`EmptyRelease`)
#   - a rolling snapshot that is missing for some contract (`NothingToFreeze`)
#   - a release that does not follow the record it is appended to
#     (`checkReleaseFollowsRecord`) — the monotonic-ordering guard this script
#     never had, so cutting 0.1.29 after 0.1.30 used to succeed
#
# It also reads every rolling snapshot before writing any of the frozen copy,
# so a failure part-way cannot leave a half-frozen release behind — which a
# `cp -r` can.
set -euo pipefail

forge script ./script/BuildPointers.sol --sig 'cutRelease()'
forge fmt
