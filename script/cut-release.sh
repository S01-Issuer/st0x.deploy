#!/usr/bin/env bash
# SPDX-License-Identifier: LicenseRef-DCL-1.0
# SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
#
# Freeze `candidate` as this release's record, then regenerate the deploy libs.
# rainix-tag-release's `snapshot-generate-cmd`, run after the version is written
# to `[external.package].version`. `BuildScript.cutRelease()` does the work and
# makes every refusal; see `LibRainDeploySnapshot.freeze`.
set -euo pipefail

forge script ./script/Build.sol --sig 'cutRelease()'
forge fmt
