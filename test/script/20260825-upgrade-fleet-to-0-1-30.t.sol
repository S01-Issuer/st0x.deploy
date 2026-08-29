// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";

import {
    UpgradeTargetNotDeployed,
    BeaconInUnknownState,
    FleetAlreadyUpgraded,
    IUpgradeableBeaconLike
} from "../../script/20260825-upgrade-fleet-to-0-1-30.s.sol";
import {UpgradeFleetHarness} from "./UpgradeFleetHarness.sol";
import {LibBeaconInvariants} from "../../src/lib/LibBeaconInvariants.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {SafeTx} from "../../src/lib/LibSafeOps.sol";

/// @title UpgradeFleetTest
/// @notice Guard coverage for `20260825-upgrade-fleet-to-0-1-30` without a
/// fork: the target-deployed gate, the unknown-drift refusal, the
/// self-scoping, the already-upgraded refusal, and the exact bundle shape.
/// The live-fork walk is in `20260825-upgrade-fleet-to-0-1-30.prod.t.sol`.
contract UpgradeFleetTest is Test {
    UpgradeFleetHarness internal harness;
    address[2] internal beacons;

    function setUp() external {
        vm.chainId(LibSafeInvariants.BASE_CHAIN_ID);
        harness = new UpgradeFleetHarness();
        beacons = [
            LibBeaconInvariants.receiptBeaconForChainId(LibSafeInvariants.BASE_CHAIN_ID),
            LibBeaconInvariants.receiptVaultBeaconForChainId(LibSafeInvariants.BASE_CHAIN_ID)
        ];
    }

    /// @notice Mock both gated beacons in the pre-upgrade (0.1.1) state.
    function mockPreUpgradeBeacons() internal {
        vm.etch(beacons[0], hex"fe");
        vm.etch(beacons[1], hex"fe");
        vm.mockCall(
            beacons[0], abi.encodeCall(IBeacon.implementation, ()), abi.encode(LibProdDeployV4.STOX_RECEIPT_0_1_1)
        );
        vm.mockCall(
            beacons[1], abi.encodeCall(IBeacon.implementation, ()), abi.encode(LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_1)
        );
    }

    /// The target gate refuses a codeless (or wrong-codehash) 0.1.30 impl.
    function testTargetGateRefusesUndeployedImpl() external {
        vm.expectRevert(abi.encodeWithSelector(UpgradeTargetNotDeployed.selector, LibProdDeployV4.STOX_RECEIPT_0_1_30));
        harness.callAssertTargetDeployed(
            LibProdDeployV4.STOX_RECEIPT_0_1_30, LibProdDeployV4.STOX_RECEIPT_CODEHASH_0_1_30
        );
    }

    /// The target gate accepts the frozen 0.1.30 runtime at the pin.
    function testTargetGateAcceptsTheFrozenRuntime() external {
        vm.etch(LibProdDeployV4.STOX_RECEIPT_0_1_30, LibProdDeployV4.STOX_RECEIPT_RUNTIME_CODE_0_1_30);
        harness.callAssertTargetDeployed(
            LibProdDeployV4.STOX_RECEIPT_0_1_30, LibProdDeployV4.STOX_RECEIPT_CODEHASH_0_1_30
        );
    }

    /// The pre-upgrade state authors both `upgradeTo` transactions.
    function testAuthoringProducesBothUpgrades() external {
        mockPreUpgradeBeacons();
        SafeTx[] memory txs = harness.callAuthorBundle();
        assertEq(txs.length, 2);
        assertEq(txs[0].to, beacons[0]);
        assertEq(txs[0].data, abi.encodeCall(IUpgradeableBeaconLike.upgradeTo, (LibProdDeployV4.STOX_RECEIPT_0_1_30)));
        assertEq(txs[1].to, beacons[1]);
        assertEq(
            txs[1].data, abi.encodeCall(IUpgradeableBeaconLike.upgradeTo, (LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30))
        );
    }

    /// A half-executed upgrade self-scopes to the remaining beacon.
    function testAuthoringSelfScopesAPartialUpgrade() external {
        mockPreUpgradeBeacons();
        vm.mockCall(
            beacons[0], abi.encodeCall(IBeacon.implementation, ()), abi.encode(LibProdDeployV4.STOX_RECEIPT_0_1_30)
        );
        SafeTx[] memory txs = harness.callAuthorBundle();
        assertEq(txs.length, 1);
        assertEq(txs[0].to, beacons[1]);
    }

    /// A beacon in neither the 0.1.1 nor 0.1.30 state is unknown drift.
    function testAuthoringRefusesUnknownDrift() external {
        mockPreUpgradeBeacons();
        vm.mockCall(beacons[0], abi.encodeCall(IBeacon.implementation, ()), abi.encode(address(0xBAD)));
        vm.expectRevert(abi.encodeWithSelector(BeaconInUnknownState.selector, beacons[0], address(0xBAD)));
        harness.callAuthorBundle();
    }

    /// A fully-upgraded chain refuses to author anything.
    function testAuthoringRefusesWhenAlreadyUpgraded() external {
        mockPreUpgradeBeacons();
        vm.mockCall(
            beacons[0], abi.encodeCall(IBeacon.implementation, ()), abi.encode(LibProdDeployV4.STOX_RECEIPT_0_1_30)
        );
        vm.mockCall(
            beacons[1],
            abi.encodeCall(IBeacon.implementation, ()),
            abi.encode(LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30)
        );
        vm.expectRevert(FleetAlreadyUpgraded.selector);
        harness.callAuthorBundle();
    }
}
