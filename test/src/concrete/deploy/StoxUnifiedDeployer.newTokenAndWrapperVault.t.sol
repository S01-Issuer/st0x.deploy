// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std/Test.sol";
import {
    OffchainAssetReceiptVaultConfigV2
} from "rain.vats/concrete/deploy/OffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {ReceiptVaultConfigV2} from "rain.vats/abstract/ReceiptVault.sol";
import {StoxUnifiedDeployer} from "../../../../src/concrete/deploy/StoxUnifiedDeployer.sol";
import {StoxWrappedTokenVault} from "../../../../src/concrete/StoxWrappedTokenVault.sol";
import {LibProdDeployV2} from "../../../../src/lib/LibProdDeployV2.sol";
import {LibTestDeploy} from "../../../lib/LibTestDeploy.sol";

/// @title StoxUnifiedDeployerIntegrationTest
/// @notice End-to-end V2 integration test deploying the full Zoltu stack and
/// exercising newTokenAndWrapperVault with real deployers.
contract StoxUnifiedDeployerIntegrationTest is Test {
    /// Deploy full V2 stack via Zoltu and call newTokenAndWrapperVault.
    function testNewTokenAndWrapperVaultV2Integration() external {
        LibTestDeploy.deployAll(vm);
        StoxUnifiedDeployer unifiedDeployer = StoxUnifiedDeployer(LibProdDeployV2.STOX_UNIFIED_DEPLOYER);

        OffchainAssetReceiptVaultConfigV2 memory config = OffchainAssetReceiptVaultConfigV2({
            initialAdmin: address(this),
            receiptVaultConfig: ReceiptVaultConfigV2({
                asset: address(0), name: "Test Vault", symbol: "TV", receipt: address(0)
            })
        });

        vm.recordLogs();
        unifiedDeployer.newTokenAndWrapperVault(config);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundDeployment = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(unifiedDeployer)) {
                foundDeployment = true;
                (address sender, address receiptVault, address wrapper) =
                    abi.decode(logs[i].data, (address, address, address));
                assertEq(sender, address(this), "sender should be this contract");
                assertTrue(receiptVault != address(0), "receipt vault should be non-zero");
                assertTrue(wrapper != address(0), "wrapper vault should be non-zero");
                assertTrue(receiptVault.code.length > 0, "receipt vault should have code");
                assertTrue(wrapper.code.length > 0, "wrapper vault should have code");
                assertEq(
                    StoxWrappedTokenVault(wrapper).asset(), receiptVault, "wrapper asset should be the receipt vault"
                );
            }
        }
        assertTrue(foundDeployment, "Deployment event should have been emitted");
    }
}
