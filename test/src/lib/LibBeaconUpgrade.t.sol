// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.38/src/lib/LibMigrationRegistryDeploy.sol";
import {LibBeaconUpgrade} from "../../../src/lib/LibBeaconUpgrade.sol";
import {ICorporateActionsV1} from "../../../src/interface/ICorporateActionsV1.sol";
import {LibBeaconInvariants} from "../../../src/lib/LibBeaconInvariants.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../../../src/lib/LibStoxMigrations.sol";
import {LibLocalProdState} from "../../lib/LibLocalProdState.sol";
import {LibTestRootLine} from "../../lib/LibTestRootLine.sol";
import {LibTokenInvariants, NoTokenTableForChain, TokenInstance} from "../../../src/lib/LibTokenInvariants.sol";
import {RUNTIME_CODE as RECEIPT_VAULT_RUNTIME_CODE} from "../../../src/generated/candidate/StoxReceiptVault.sol";

contract LibBeaconUpgradeTest is Test {
    /// The receipt-vault implementation the rollout upgrades to delegatecalls
    /// the facet the beacon pre-flight checks: its pinned runtime code has the
    /// rollout's facet address compiled in. Re-pointing one constant without
    /// the other fails here, not after signing and the delay.
    function testReceiptVaultCallsTheRolloutFacet() external pure {
        assertEq(keccak256(RECEIPT_VAULT_RUNTIME_CODE), LibBeaconUpgrade.RECEIPT_VAULT_CODEHASH, "codehash");
        bytes memory code = RECEIPT_VAULT_RUNTIME_CODE;
        bytes20 facet = bytes20(LibBeaconUpgrade.FACET);
        bool found = false;
        for (uint256 byteIndex = 0; byteIndex + 20 <= code.length && !found; byteIndex++) {
            bytes20 window;
            assembly ("memory-safe") {
                window := mload(add(add(code, 0x20), byteIndex))
            }
            found = window == facet;
        }
        assertTrue(found, "facet address in vault code");
    }

    /// On every deployment network, 0G included, the beacon batch is exactly:
    /// the wrapper beacon onto the new wrapper, the vault beacon onto the new
    /// vault, the facet probe on the chain's first production vault, then the
    /// batch's root-line record onto the Safe-owned Base vault handover; no
    /// call carries value.
    function testBeaconBatchIsExactOnEveryDeploymentNetwork() external {
        LibTestRootLine.etchRegistry(vm);
        uint256[] memory chainIds = LibLocalProdState.chainIds();
        assertEq(chainIds[chainIds.length - 1], LibSafeInvariants.ZEROG_CHAIN_ID, "0G is a deployment network");
        for (uint256 chainIndex = 0; chainIndex < chainIds.length; chainIndex++) {
            uint256 chainId = chainIds[chainIndex];
            string memory label = vm.toString(chainId);
            uint256 snapshot = vm.snapshotState();
            LibLocalProdState.beacons(vm, chainId);
            address[4] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(chainId);
            (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
                LibBeaconUpgrade.beaconBatch(chainId);
            vm.revertToState(snapshot);

            assertEq(targets.length, 4, label);
            assertEq(values.length, 4, label);
            assertEq(payloads.length, 4, label);
            for (uint256 callIndex = 0; callIndex < 4; callIndex++) {
                assertEq(values[callIndex], 0, label);
            }

            assertEq(targets[0], beacons[LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX], label);
            assertEq(
                payloads[0],
                abi.encodeCall(UpgradeableBeacon.upgradeTo, (LibBeaconUpgrade.WRAPPED_TOKEN_VAULT_IMPLEMENTATION)),
                label
            );
            assertEq(targets[1], beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX], label);
            assertEq(
                payloads[1],
                abi.encodeCall(UpgradeableBeacon.upgradeTo, (LibBeaconUpgrade.RECEIPT_VAULT_IMPLEMENTATION)),
                label
            );
            assertTrue(targets[0] != targets[1], label);
            assertEq(targets[2], LibTokenInvariants.productionTokensForChainId(chainId)[0].receiptVault, label);
            assertEq(payloads[2], abi.encodeCall(ICorporateActionsV1.completedActionCount, ()), label);
            assertEq(targets[3], LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, label);
            assertEq(
                payloads[3],
                LibTestRootLine.recordCalldata(
                    LibStoxMigrations.SCHEDULE_BEACON_UPGRADE, LibStoxMigrations.HAND_SAFE_OWNED_BASE_VAULTS_TO_TIMELOCK
                ),
                label
            );
        }
    }

    function externalBeaconTokens(uint256 chainId) external pure returns (TokenInstance[] memory) {
        return LibBeaconUpgrade.beaconTokens(chainId);
    }

    function assertSameToken(TokenInstance memory actual, TokenInstance memory expected) internal pure {
        assertEq(actual.underlying, expected.underlying, "underlying");
        assertEq(actual.receipt, expected.receipt, string.concat(expected.underlying, " receipt"));
        assertEq(actual.receiptVault, expected.receiptVault, string.concat(expected.underlying, " receipt vault"));
        assertEq(actual.wrappedTokenVault, expected.wrappedTokenVault, string.concat(expected.underlying, " wrapper"));
    }

    /// On every deployment network, 0G included, `beaconTokens` is the
    /// chain's whole table, then tQSEP on Base and nothing more elsewhere.
    function testBeaconTokensAreTheTableThenTqsepOnBase() external pure {
        uint256[] memory chainIds = LibLocalProdState.chainIds();
        assertEq(chainIds[chainIds.length - 1], LibSafeInvariants.ZEROG_CHAIN_ID, "0G is a deployment network");
        for (uint256 chainIndex = 0; chainIndex < chainIds.length; chainIndex++) {
            uint256 chainId = chainIds[chainIndex];
            TokenInstance[] memory table = LibTokenInvariants.productionTokensForChainId(chainId);
            TokenInstance[] memory beaconTokens = LibBeaconUpgrade.beaconTokens(chainId);
            assertGt(table.length, 0, "table");
            bool onBase = chainId == LibSafeInvariants.BASE_CHAIN_ID;
            assertEq(beaconTokens.length, table.length + (onBase ? 1 : 0), "length");
            for (uint256 rowIndex = 0; rowIndex < table.length; rowIndex++) {
                assertSameToken(beaconTokens[rowIndex], table[rowIndex]);
            }
            if (onBase) assertSameToken(beaconTokens[table.length], LibTokenInvariants.qsepToken());
        }
    }

    /// `beaconTokens` refuses a chain with no table rather than returning
    /// nothing.
    function testBeaconTokensRefuseAChainWithNoTable() external {
        vm.expectRevert(abi.encodeWithSelector(NoTokenTableForChain.selector, uint256(137)));
        this.externalBeaconTokens(137);
    }
}
