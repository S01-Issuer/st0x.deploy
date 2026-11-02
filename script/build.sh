#!/bin/bash
# SPDX-License-Identifier: LicenseRef-DCL-1.0
# SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH

set -euxo pipefail

nix develop github:rainlanguage/rainix#sol-shell -c forge script ./script/BuildMigrations.sol
