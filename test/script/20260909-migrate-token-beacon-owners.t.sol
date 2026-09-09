// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {
    MigrateTokenBeaconOwners,
    NotA0_1_1BootstrapChain
} from "../../script/20260909-migrate-token-beacon-owners.s.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibProdBeacons0_1_1} from "../../src/lib/LibProdBeacons0_1_1.sol";
import {BeaconOwnerMismatch} from "../../src/lib/LibBeaconInvariants.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {IOwnable} from "../../src/interface/IOwnable.sol";

/// @title MigrateTokenBeaconOwnersTest
/// @notice The chain-generic 0.1.1 token-beacon migration refuses every
/// chain it must not touch: Base (in-use beacons are the V1 set) and any
/// chain whose beacons have already left the deploy EOA. The positive path
/// is the live broadcast on a freshly bootstrapped chain, whose forcing
/// function is that chain's `*BeaconOwnershipTest`.
contract MigrateTokenBeaconOwnersTest is Test {
    /// @notice Base's in-use production beacons are its V1-generation set,
    /// so the 0.1.1 migration does not apply and is refused before any
    /// owner read.
    function testRefusesBase() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        MigrateTokenBeaconOwners script = new MigrateTokenBeaconOwners();
        vm.expectRevert(abi.encodeWithSelector(NotA0_1_1BootstrapChain.selector, LibSafeInvariants.BASE_CHAIN_ID));
        script.run();
    }

    /// @notice A chain whose beacons already migrated is refused on the
    /// EOA-owner pre-flight rather than re-run — Ethereum's beacons left the
    /// deploy EOA on 2026-07-16.
    function testRefusesAnAlreadyMigratedChain() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        address receiptBeacon = LibProdBeacons0_1_1.beacons()[0];
        address currentOwner = IOwnable(receiptBeacon).owner();
        assertNotEq(currentOwner, LibProdDeployV4.BEACON_INITIAL_OWNER, "Ethereum receipt beacon still EOA-owned");

        MigrateTokenBeaconOwners script = new MigrateTokenBeaconOwners();
        vm.expectRevert(
            abi.encodeWithSelector(
                BeaconOwnerMismatch.selector, receiptBeacon, LibProdDeployV4.BEACON_INITIAL_OWNER, currentOwner
            )
        );
        script.run();
    }
}
