// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {ZerogRootLineFixture} from "./ZerogRootLineFixture.sol";

/// @title UnderlyingNamingRolloutZerogTest
/// @notice The underlying-naming rollout on live 0G, from the line walked to
/// the beacon onto past the token creation, over 0G's whole table.
contract UnderlyingNamingRolloutZerogTest is ZerogRootLineFixture {
    function setUp() public {
        forkZerogAtTheTokenRecord();
        landZerogLineThrough(LibStoxMigrations.HAND_SAFE_OWNED_BASE_VAULTS_TO_TIMELOCK);
    }

    function testRolloutOnZerog() external {
        assertRolloutFromTheBeaconOnto(LibStoxDeployNetworks.ZEROG);
    }
}
