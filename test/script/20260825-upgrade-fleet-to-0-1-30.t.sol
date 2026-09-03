// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.6.1/token/ERC20/extensions/IERC20Metadata.sol";
import {IReceiptV3} from "rain-vats-0.1.6/src/interface/IReceiptV3.sol";

import {
    BeaconInUnknownState,
    FleetAlreadyUpgraded,
    UpgradeChangedTokenState
} from "../../script/20260825-upgrade-fleet-to-0-1-30.s.sol";
import {UpgradeFleetHarness} from "./UpgradeFleetHarness.sol";
import {LibBeaconInvariants} from "../../src/lib/LibBeaconInvariants.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {SafeTx, IUpgradeableBeacon} from "../../src/lib/LibSafeOps.sol";
import {TokenInstance} from "../../src/lib/LibTokenInvariants.sol";

/// @title UpgradeFleetTest
/// @notice Guard coverage for `20260825-upgrade-fleet-to-0-1-30` without a
/// fork: the unknown-drift refusal, the self-scoping, the already-upgraded
/// refusal, the exact bundle shape, and the token-state preservation check.
/// The live-fork walk is in `20260825-upgrade-fleet-to-0-1-30.prod.t.sol`.
contract UpgradeFleetTest is Test {
    UpgradeFleetHarness internal harness;
    address[3] internal beacons;

    function setUp() external {
        vm.chainId(LibSafeInvariants.BASE_CHAIN_ID);
        harness = new UpgradeFleetHarness();
        beacons = LibBeaconInvariants.prodBeaconsForChainId(LibSafeInvariants.BASE_CHAIN_ID);
    }

    /// @notice Mock both gated beacons in the pre-upgrade (0.1.1) state.
    function mockPreUpgradeBeacons() internal {
        vm.etch(beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX], hex"fe");
        vm.etch(beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX], hex"fe");
        vm.mockCall(
            beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX],
            abi.encodeCall(IBeacon.implementation, ()),
            abi.encode(LibProdDeployV4.STOX_RECEIPT_0_1_1)
        );
        vm.mockCall(
            beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX],
            abi.encodeCall(IBeacon.implementation, ()),
            abi.encode(LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_1)
        );
    }

    /// The pre-upgrade state authors both `upgradeTo` transactions.
    function testAuthoringProducesBothUpgrades() external {
        mockPreUpgradeBeacons();
        SafeTx[] memory txs = harness.callAuthorBundle(beacons);
        assertEq(txs.length, 2);
        assertEq(txs[0].to, beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX]);
        assertEq(txs[0].data, abi.encodeCall(IUpgradeableBeacon.upgradeTo, (LibProdDeployV4.STOX_RECEIPT_0_1_30)));
        assertEq(txs[1].to, beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX]);
        assertEq(txs[1].data, abi.encodeCall(IUpgradeableBeacon.upgradeTo, (LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30)));
    }

    /// A half-executed upgrade self-scopes to the remaining beacon.
    function testAuthoringSelfScopesAPartialUpgrade() external {
        mockPreUpgradeBeacons();
        vm.mockCall(
            beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX],
            abi.encodeCall(IBeacon.implementation, ()),
            abi.encode(LibProdDeployV4.STOX_RECEIPT_0_1_30)
        );
        SafeTx[] memory txs = harness.callAuthorBundle(beacons);
        assertEq(txs.length, 1);
        assertEq(txs[0].to, beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX]);
    }

    /// A beacon in neither the 0.1.1 nor 0.1.30 state is unknown drift.
    function testAuthoringRefusesUnknownDrift() external {
        mockPreUpgradeBeacons();
        vm.mockCall(
            beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX],
            abi.encodeCall(IBeacon.implementation, ()),
            abi.encode(address(0xBAD))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                BeaconInUnknownState.selector, beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX], address(0xBAD)
            )
        );
        harness.callAuthorBundle(beacons);
    }

    /// A fully-upgraded chain refuses to author anything.
    function testAuthoringRefusesWhenAlreadyUpgraded() external {
        mockPreUpgradeBeacons();
        vm.mockCall(
            beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX],
            abi.encodeCall(IBeacon.implementation, ()),
            abi.encode(LibProdDeployV4.STOX_RECEIPT_0_1_30)
        );
        vm.mockCall(
            beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX],
            abi.encodeCall(IBeacon.implementation, ()),
            abi.encode(LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30)
        );
        vm.expectRevert(FleetAlreadyUpgraded.selector);
        harness.callAuthorBundle(beacons);
    }

    address internal constant VAULT = address(0x1111);
    address internal constant RECEIPT = address(0x2222);
    address internal constant MANAGER = address(0x3333);

    /// @notice Mock one production token's reads.
    function mockToken(uint256 supply, address manager) internal returns (TokenInstance[] memory tokens) {
        vm.etch(VAULT, hex"fe");
        vm.etch(RECEIPT, hex"fe");
        vm.mockCall(VAULT, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(supply));
        vm.mockCall(VAULT, abi.encodeCall(IERC20Metadata.symbol, ()), abi.encode("stTEST"));
        vm.mockCall(VAULT, abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(uint8(18)));
        vm.mockCall(RECEIPT, abi.encodeCall(IReceiptV3.manager, ()), abi.encode(manager));
        tokens = new TokenInstance[](1);
        tokens[0] =
            TokenInstance({underlying: "TEST", receipt: RECEIPT, receiptVault: VAULT, wrappedTokenVault: address(0)});
    }

    /// Identical reads across the upgrade pass the preservation check.
    function testTokenStatePreservedAcceptsIdenticalReads() external {
        TokenInstance[] memory tokens = mockToken(1e18, MANAGER);
        (uint256[] memory supplies, bytes32[] memory metaHashes) = harness.callSnapshotTokenState(tokens);
        harness.callAssertTokenStatePreserved(tokens, supplies, metaHashes);
    }

    /// A vault whose `totalSupply` moved across the upgrade is refused.
    function testTokenStatePreservedRefusesASupplyChange() external {
        TokenInstance[] memory tokens = mockToken(1e18, MANAGER);
        (uint256[] memory supplies, bytes32[] memory metaHashes) = harness.callSnapshotTokenState(tokens);
        vm.mockCall(VAULT, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(1e18 + 1));
        vm.expectRevert(abi.encodeWithSelector(UpgradeChangedTokenState.selector, VAULT));
        harness.callAssertTokenStatePreserved(tokens, supplies, metaHashes);
    }

    /// A receipt whose `manager` moved across the upgrade is refused.
    function testTokenStatePreservedRefusesAManagerChange() external {
        TokenInstance[] memory tokens = mockToken(1e18, MANAGER);
        (uint256[] memory supplies, bytes32[] memory metaHashes) = harness.callSnapshotTokenState(tokens);
        vm.mockCall(RECEIPT, abi.encodeCall(IReceiptV3.manager, ()), abi.encode(address(0x4444)));
        vm.expectRevert(abi.encodeWithSelector(UpgradeChangedTokenState.selector, VAULT));
        harness.callAssertTokenStatePreserved(tokens, supplies, metaHashes);
    }
}
