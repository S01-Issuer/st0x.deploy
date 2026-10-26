#!/usr/bin/env bash
# SPDX-License-Identifier: LicenseRef-DCL-1.0
# SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
#
# rainix-copy-artifacts' post-forge-build hook: regenerates the committed JSON
# artifacts that script/Build.sol does not.
set -euo pipefail

cd "$(dirname "$0")/.."

sol() { nix develop github:rainlanguage/rainix#sol-shell -c "$@"; }

sol forge script ./script/BuildPrivilegedAddresses.sol
sol forge script ./script/BuildSubgraphNetworks.sol
sol forge script ./script/BuildIdealRoles.sol
sol forge script ./script/BuildMigrations.sol

# The reusable's stale check is blind to untracked files (rainlanguage/rainix#357).
git add --intent-to-add --all
