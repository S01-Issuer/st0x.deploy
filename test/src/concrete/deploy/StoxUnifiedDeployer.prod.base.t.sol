// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";

import {StoxUnifiedDeployer} from "../../../../src/concrete/deploy/StoxUnifiedDeployer.sol";
import {LibProdDeployV1} from "../../../../src/lib/LibProdDeployV1.sol";
import {LibTestProd} from "../../../lib/LibTestProd.sol";
import {
    OffchainAssetReceiptVaultBeaconSetDeployer
} from "ethgild/concrete/deploy/OffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {
    StoxWrappedTokenVaultBeaconSetDeployer
} from "../../../../src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol";
import {IBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol";

contract StoxProdBaseTest is Test {
    /// Verify all deployed contract addresses, codehashes on Base fork.
    function _checkAllOnChain() internal view {
        // OffchainAssetReceiptVaultBeaconSetDeployer
        assertTrue(
            LibProdDeployV1.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER.code.length > 0,
            "OffchainAssetReceiptVaultBeaconSetDeployer not deployed"
        );
        assertEq(
            LibProdDeployV1.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER.codehash,
            LibProdDeployV1.PROD_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_BASE_CODEHASH_V1
        );

        // StoxWrappedTokenVaultBeaconSetDeployer
        assertTrue(
            LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER.code.length > 0,
            "StoxWrappedTokenVaultBeaconSetDeployer not deployed"
        );
        assertEq(
            LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER.codehash,
            LibProdDeployV1.PROD_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_BASE_CODEHASH_V1
        );

        // StoxWrappedTokenVault implementation (via beacon)
        // The on-chain deployer uses the old I_STOX_WRAPPED_TOKEN_VAULT_BEACON
        // selector from before the rename to iStoxWrappedTokenVaultBeacon.
        (bool ok, bytes memory beaconData) = LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER.staticcall(
            abi.encodeWithSignature("I_STOX_WRAPPED_TOKEN_VAULT_BEACON()")
        );
        assertTrue(ok, "beacon call failed");
        address wrappedImpl = IBeacon(abi.decode(beaconData, (address))).implementation();
        assertEq(
            wrappedImpl,
            LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION,
            "StoxWrappedTokenVault implementation address mismatch"
        );
        assertTrue(wrappedImpl.code.length > 0, "StoxWrappedTokenVault implementation not deployed");
        assertEq(
            wrappedImpl.codehash, LibProdDeployV1.PROD_STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1
        );

        // StoxUnifiedDeployer
        assertTrue(LibProdDeployV1.STOX_UNIFIED_DEPLOYER.code.length > 0, "StoxUnifiedDeployer not deployed");
        assertEq(
            LibProdDeployV1.STOX_UNIFIED_DEPLOYER.codehash, LibProdDeployV1.PROD_STOX_UNIFIED_DEPLOYER_BASE_CODEHASH_V1
        );

        // StoxReceipt implementation (via beacon)
        OffchainAssetReceiptVaultBeaconSetDeployer oarvDeployer =
            OffchainAssetReceiptVaultBeaconSetDeployer(LibProdDeployV1.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER);
        address receiptImpl = oarvDeployer.I_RECEIPT_BEACON().implementation();
        assertEq(receiptImpl, LibProdDeployV1.STOX_RECEIPT_IMPLEMENTATION, "StoxReceipt implementation address mismatch");
        assertTrue(receiptImpl.code.length > 0, "StoxReceipt implementation not deployed");
        assertEq(receiptImpl.codehash, LibProdDeployV1.PROD_STOX_RECEIPT_IMPLEMENTATION_BASE_CODEHASH_V1);

        // StoxReceiptVault implementation (via beacon)
        address vaultImpl = oarvDeployer.I_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON().implementation();
        assertEq(
            vaultImpl,
            LibProdDeployV1.STOX_RECEIPT_VAULT_IMPLEMENTATION,
            "StoxReceiptVault implementation address mismatch"
        );
        assertTrue(vaultImpl.code.length > 0, "StoxReceiptVault implementation not deployed");
        assertEq(vaultImpl.codehash, LibProdDeployV1.PROD_STOX_RECEIPT_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1);
    }

    /// Verify V1 creation bytecodes match compiled artifacts for contracts
    /// that are unchanged between V1 and V2. Contracts that changed
    /// (StoxWrappedTokenVault, StoxWrappedTokenVaultBeaconSetDeployer) are
    /// verified in the V2 tests instead.
    function _checkUnchangedCreationBytecodes() internal view {
        assertEq(
            vm.getCode("StoxReceipt.sol:StoxReceipt"),
            LibProdDeployV1.PROD_STOX_RECEIPT_CREATION_BYTECODE_V1
        );
        assertEq(
            vm.getCode("StoxReceiptVault.sol:StoxReceiptVault"),
            LibProdDeployV1.PROD_STOX_RECEIPT_VAULT_CREATION_BYTECODE_V1
        );
        assertEq(
            vm.getCode("StoxUnifiedDeployer.sol:StoxUnifiedDeployer"),
            LibProdDeployV1.PROD_STOX_UNIFIED_DEPLOYER_CREATION_BYTECODE_V1
        );
    }

    /// Fresh-compiled StoxUnifiedDeployer must match the stored codehash.
    function testProdStoxUnifiedDeployerFreshCodehash() external {
        StoxUnifiedDeployer fresh = new StoxUnifiedDeployer();
        assertEq(address(fresh).codehash, LibProdDeployV1.PROD_STOX_UNIFIED_DEPLOYER_BASE_CODEHASH_V1);
    }

    /// Creation bytecodes must match stored constants.
    function testProdCreationBytecodes() external view {
        _checkUnchangedCreationBytecodes();
    }

    /// All contracts MUST be deployed on Base.
    function testProdDeployBase() external {
        LibTestProd.createSelectForkBase(vm);
        _checkAllOnChain();
    }
}
