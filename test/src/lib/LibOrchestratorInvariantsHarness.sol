// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {LibOrchestratorInvariants} from "../../../src/lib/LibOrchestratorInvariants.sol";

/// @notice External-call harness around `LibOrchestratorInvariants`'s
/// internal asserts so `vm.expectRevert` can catch their typed errors.
contract LibOrchestratorInvariantsHarness {
    function callAssertMintCapsBeaconSet() external view {
        LibOrchestratorInvariants.assertMintCapsBeaconSet();
    }

    function callAssertMintCapsInstance(address chainSafe) external view {
        LibOrchestratorInvariants.assertMintCapsInstance(chainSafe);
    }
}
