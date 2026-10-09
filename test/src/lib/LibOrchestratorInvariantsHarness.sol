// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {LibOrchestratorInvariants} from "../../../src/lib/LibOrchestratorInvariants.sol";

/// @title LibOrchestratorInvariantsHarness
/// @notice External-call shim around the internal library so
/// `vm.expectRevert` can intercept the typed errors.
contract LibOrchestratorInvariantsHarness {
    function callAssertBeaconSet() external view {
        LibOrchestratorInvariants.assertBeaconSet();
    }

    function callAssertInstance(address chainSafe) external view {
        LibOrchestratorInvariants.assertInstance(chainSafe);
    }
}
