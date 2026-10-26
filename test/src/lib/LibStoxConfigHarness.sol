// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";

/// @notice External-call harness so `vm.expectRevert` sees `LibStoxConfig`'s
/// reverts.
contract LibStoxConfigHarness {
    function beaconOwner() external view returns (address) {
        return LibStoxConfig.beaconOwner();
    }
}
