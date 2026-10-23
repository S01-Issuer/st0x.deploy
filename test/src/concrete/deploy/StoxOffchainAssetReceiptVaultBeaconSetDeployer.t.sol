// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {LibRainDeploy} from "rain-deploy-0.1.22/src/lib/LibRainDeploy.sol";
import {IConfigRegistryV3} from "rain-deploy-0.1.22/src/interface/IConfigRegistryV3.sol";

import {StoxReceipt} from "../../../../src/concrete/StoxReceipt.sol";
import {StoxReceiptVault} from "../../../../src/concrete/StoxReceiptVault.sol";
import {
    StoxOffchainAssetReceiptVaultBeaconSetDeployer
} from "../../../../src/concrete/deploy/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {LibProdDeployV4} from "../../../../src/generated/LibProdDeployV4.sol";
import {LibStoxConfig} from "../../../../src/lib/LibStoxConfig.sol";
import {LibStoxConfigFork} from "../../../../src/lib/LibStoxConfigFork.sol";

contract StoxOffchainAssetReceiptVaultBeaconSetDeployerTest is Test {
    function deployImplementations() internal {
        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(type(StoxReceipt).creationCode);
        LibRainDeploy.deployZoltu(type(StoxReceiptVault).creationCode);
    }

    /// Both beacons are owned by the bound beacon owner, and the Zoltu address
    /// does not depend on it.
    function testFuzzBeaconOwnerFollowsBinding(address owner) external {
        vm.assume(owner != address(0));
        deployImplementations();
        LibStoxConfigFork.bindBeaconOwner(vm, owner);
        StoxOffchainAssetReceiptVaultBeaconSetDeployer deployer = StoxOffchainAssetReceiptVaultBeaconSetDeployer(
            LibRainDeploy.deployZoltu(type(StoxOffchainAssetReceiptVaultBeaconSetDeployer).creationCode)
        );
        assertEq(address(deployer), LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CANDIDATE);
        assertEq(Ownable(address(deployer.iReceiptBeacon())).owner(), owner, "receipt beacon owner");
        assertEq(Ownable(address(deployer.iOffchainAssetReceiptVaultBeacon())).owner(), owner, "vault beacon owner");
        assertEq(deployer.iReceiptBeacon().implementation(), LibProdDeployV4.STOX_RECEIPT_CANDIDATE);
        assertEq(
            deployer.iOffchainAssetReceiptVaultBeacon().implementation(), LibProdDeployV4.STOX_RECEIPT_VAULT_CANDIDATE
        );
    }

    /// An unbound owner refuses construction.
    function testBeaconOwnerUnboundReverts() external {
        deployImplementations();
        LibStoxConfigFork.etchConfigRegistry(vm);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV3.NameNotRegistered.selector, LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.BEACON_OWNER
            )
        );
        new StoxOffchainAssetReceiptVaultBeaconSetDeployer();
    }
}
