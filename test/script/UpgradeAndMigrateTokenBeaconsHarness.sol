// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {UpgradeAndMigrateTokenBeacons} from "../../script/20260909-upgrade-and-migrate-token-beacons.s.sol";

/// @title UpgradeAndMigrateTokenBeaconsHarness
/// @notice Exposes the script's internal pin map so a test can compare it
/// against a chain that reached the same end state by another route.
contract UpgradeAndMigrateTokenBeaconsHarness is UpgradeAndMigrateTokenBeacons {
    function callPostImplementations() external pure returns (address[3] memory) {
        return postImplementations();
    }
}
