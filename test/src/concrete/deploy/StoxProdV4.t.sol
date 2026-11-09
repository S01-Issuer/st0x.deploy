// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibProdDeployV4} from "../../../../src/generated/LibProdDeployV4.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {LibStoxDeployNetworks} from "../../../../src/lib/LibStoxDeployNetworks.sol";
import {LibBeaconInvariants} from "../../../../src/lib/LibBeaconInvariants.sol";
import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {
    IOffchainAssetReceiptVaultBeaconSetDeployerV2
} from "rain-vats-0.2.20/src/interface/deprecated/IOffchainAssetReceiptVaultBeaconSetDeployerV2.sol";

/// @title StoxProdV4Test
/// @notice Fork test of the V4 beacons' wiring and ownership on every
/// deployment network. That the audited 0.1.1 set is live at its pinned
/// addresses with its pinned code is `StoxDeployChainTest`'s
/// `testSuitesLiveOnEverySupportedNetwork`, over every released suite.
///
/// `STOX_PROD_AUTHORISER_V4_CLONE` (hydrated from the 2026-07 broadcast) is
/// not checked here; `LibProdDeployV4Test.testAuthoriserV4ClonePin` asserts
/// the literal + codehash derivation, and `StoxProdV4PostSwap.t.sol` checks
/// the live on-chain clone.
contract StoxProdV4Test is Test {
    /// The wrapped-token-vault beacon points at the 0.1.1 vault
    /// implementation, and the offchain-asset-receipt-vault beacon-set
    /// deployer's two beacons point at the receipt and receipt vault
    /// implementations: on Base an unadopted deploy artifact frozen at the
    /// 0.1.1 impls its constructor baked (production runs on the V1-address
    /// beacons); everywhere else the in-use beacons, which the fleet upgrade
    /// (`20260825-upgrade-fleet-to-0-1-30`) moved onto the 0.1.30 impls.
    ///
    /// Beacon OWNERSHIP is asserted only for the beacons production tokens
    /// run on, via `LibBeaconInvariants.assertProdBeaconsOwnedByChainTimelock`.
    function checkProd_0_1_1OnChain(string memory network) internal {
        vm.createSelectFork(network);
        bool oarvBeaconsAreInUse = keccak256(bytes(network)) != keccak256(bytes(LibRainDeploy.BASE));
        assertEq(
            IBeacon(LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_0_1_1).implementation(),
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_0_1_1,
            string.concat(network, ": V4 beacon implementation mismatch")
        );

        IOffchainAssetReceiptVaultBeaconSetDeployerV2 oarvDeployer = IOffchainAssetReceiptVaultBeaconSetDeployerV2(
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1
        );
        assertEq(
            oarvDeployer.iReceiptBeacon().implementation(),
            oarvBeaconsAreInUse ? LibProdDeployV4.STOX_RECEIPT_0_1_30 : LibProdDeployV4.STOX_RECEIPT_0_1_1,
            string.concat(network, ": V4 OARV receipt beacon implementation mismatch")
        );
        assertEq(
            oarvDeployer.iOffchainAssetReceiptVaultBeacon().implementation(),
            oarvBeaconsAreInUse ? LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30 : LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_1,
            string.concat(network, ": V4 OARV vault beacon implementation mismatch")
        );

        LibBeaconInvariants.assertProdBeaconsOwnedByChainTimelock(block.chainid);
    }

    function testProdDeployV4OnEveryDeploymentNetwork() external {
        string[] memory networks = LibStoxDeployNetworks.deploymentNetworks();
        for (uint256 i = 0; i < networks.length; i++) {
            checkProd_0_1_1OnChain(networks[i]);
        }
    }
}
