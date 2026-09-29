// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.16.2/src/StdCheats.sol";
import {LibRainDeploy} from "rain-deploy-0.1.10/src/lib/LibRainDeploy.sol";

uint256 constant PROD_TEST_BLOCK_NUMBER_BASE = 47842154;

/// @dev Unix timestamp (2026-10-01T00:00:00Z) by which the fleet upgrade
/// must have executed on every chain. Shared by the migration-window
/// invariants that accept either the 0.1.1 or 0.1.30 implementation until
/// then; the orchestrator rollout shares the same date — this upgrade gates
/// its cutover.
uint256 constant FLEET_UPGRADE_DEADLINE = 1_790_812_800;

library LibTestProd {
    function createSelectForkBase(Vm vm) internal {
        vm.createSelectFork(LibRainDeploy.BASE, PROD_TEST_BLOCK_NUMBER_BASE);
    }
}
