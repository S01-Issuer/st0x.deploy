// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibProdBeacons0_1_1} from "../../../src/lib/LibProdBeacons0_1_1.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibLocalProdState} from "../../lib/LibLocalProdState.sol";

/// @title LibProdBeacons0_1_1Test
// The version-suffixed name mirrors the lib under test.
// slither-disable-next-line naming-convention
contract LibProdBeacons0_1_1Test is Test {
    /// @notice The four beacons are distinct. Index-aligned lists invite a
    /// copy-paste that repeats one entry, and a repeated beacon would still
    /// pass every ownership check while quietly asserting nothing about the
    /// slot it displaced.
    /// @dev Two of the four addresses are reads from the 0.1.1 beacon-set
    /// deployer, built locally. Ethereum is arbitrary: the set is
    /// deterministic and identical on every bootstrap chain.
    function testTheFourBeaconsAreDistinct() external {
        LibLocalProdState.beacons(vm, LibSafeInvariants.ETHEREUM_CHAIN_ID);
        address[4] memory beacons = LibProdBeacons0_1_1.beacons();
        for (uint256 i = 0; i < beacons.length; i++) {
            assertTrue(beacons[i] != address(0), "beacon entry is zero");
            for (uint256 j = i + 1; j < beacons.length; j++) {
                assertTrue(beacons[i] != beacons[j], "two beacon slots resolve to the same address");
            }
        }
    }
}
