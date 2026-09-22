// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Float} from "rain-math-float-0.1.1/src/lib/LibDecimalFloat.sol";
import {LibMintCapUnits} from "../../src/lib/LibMintCapUnits.sol";

/// @notice External surface over `LibMintCapUnits` so `vm.expectRevert` has a
/// call boundary to attach to. An `internal` revert raised in the test's own
/// frame cannot be caught, so the reverting cases would otherwise be
/// unassertable.
contract MintCapUnitsHarness {
    function toGenesis(uint256 currentAmount, Float multiplierSinceGenesis) external pure returns (uint256) {
        return LibMintCapUnits.toGenesis(currentAmount, multiplierSinceGenesis);
    }

    function toCurrent(uint256 genesisAmount, Float multiplierSinceGenesis) external pure returns (uint256) {
        return LibMintCapUnits.toCurrent(genesisAmount, multiplierSinceGenesis);
    }
}
