// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibProdBeaconsBase} from "../../../src/lib/LibProdBeaconsBase.sol";
import {LibTokenInvariants, TokenInstance} from "../../../src/lib/LibTokenInvariants.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {ERC1967_BEACON_SLOT} from "rain-extrospection-0.1.1/src/lib/LibExtrospectERC1967BeaconProxy.sol";

/// @title LibProdBeaconsBaseTest
/// @notice `LibProdBeaconsBase` claims to name the beacons Base's production
/// tokens RUN ON, and every ownership invariant built on it inherits that
/// claim: assert the wrong three addresses and the checks pass while the live
/// beacons go unpinned. Nothing enforced the claim — it held by author
/// discipline — so this reads the beacon out of each production proxy on a
/// live fork and pins the lib against what the chain actually says.
/// @dev Unpinned Base head. A pinned block would freeze the answer to whatever
/// was true at that block, which is the opposite of what a drift detector is
/// for.
contract LibProdBeaconsBaseTest is Test {
    /// @notice The beacon a `BeaconProxy` delegates to, read from its EIP-1967
    /// slot rather than a getter, so a proxy that does not expose one is still
    /// checkable.
    function beaconOf(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967_BEACON_SLOT))));
    }

    /// @notice Every production token's receipt, receipt vault and wrapped
    /// vault sits behind the beacon this lib names for that slot, in the lib's
    /// own index order. A token migrated onto a different beacon, or an index
    /// swap in the lib, fails here — the two cases the ownership asserts
    /// cannot distinguish on their own, because a wrong-but-Safe-owned beacon
    /// satisfies them just as well as the right one.
    function testProductionTokensRunOnTheseBeacons() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        address[3] memory beacons = LibProdBeaconsBase.beacons();
        TokenInstance[] memory tokens = LibTokenInvariants.productionTokensBase();
        assertTrue(tokens.length > 0, "no production tokens to check");
        for (uint256 i = 0; i < tokens.length; i++) {
            assertEq(beaconOf(tokens[i].receipt), beacons[0], string.concat(tokens[i].underlying, " receipt beacon"));
            assertEq(
                beaconOf(tokens[i].receiptVault),
                beacons[1],
                string.concat(tokens[i].underlying, " receipt vault beacon")
            );
            assertEq(
                beaconOf(tokens[i].wrappedTokenVault),
                beacons[2],
                string.concat(tokens[i].underlying, " wrapped vault beacon")
            );
        }
    }

    /// @notice The three beacons are distinct. Index-aligned lists invite a
    /// copy-paste that repeats one entry, and a repeated beacon would still
    /// pass every ownership check while quietly asserting nothing about the
    /// slot it displaced.
    function testTheThreeBeaconsAreDistinct() external pure {
        address[3] memory beacons = LibProdBeaconsBase.beacons();
        assertTrue(beacons[0] != beacons[1], "receipt == receipt vault");
        assertTrue(beacons[1] != beacons[2], "receipt vault == wrapped vault");
        assertTrue(beacons[0] != beacons[2], "receipt == wrapped vault");
    }
}
