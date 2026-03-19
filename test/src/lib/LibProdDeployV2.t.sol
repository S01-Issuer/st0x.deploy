// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {LibRainDeploy} from "rain.deploy/lib/LibRainDeploy.sol";
import {LibProdDeployV2} from "../../../src/lib/LibProdDeployV2.sol";
import {StoxReceipt} from "../../../src/concrete/StoxReceipt.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {StoxWrappedTokenVault} from "../../../src/concrete/StoxWrappedTokenVault.sol";
import {StoxUnifiedDeployer} from "../../../src/concrete/deploy/StoxUnifiedDeployer.sol";
import {
    CREATION_CODE as STOX_RECEIPT_CREATION_CODE,
    RUNTIME_CODE as STOX_RECEIPT_RUNTIME_CODE,
    DEPLOYED_ADDRESS as STOX_RECEIPT_GENERATED_ADDRESS
} from "../../../src/generated/StoxReceipt.pointers.sol";
import {
    CREATION_CODE as STOX_RECEIPT_VAULT_CREATION_CODE,
    RUNTIME_CODE as STOX_RECEIPT_VAULT_RUNTIME_CODE,
    DEPLOYED_ADDRESS as STOX_RECEIPT_VAULT_GENERATED_ADDRESS
} from "../../../src/generated/StoxReceiptVault.pointers.sol";
import {
    CREATION_CODE as STOX_WRAPPED_TOKEN_VAULT_CREATION_CODE,
    RUNTIME_CODE as STOX_WRAPPED_TOKEN_VAULT_RUNTIME_CODE,
    DEPLOYED_ADDRESS as STOX_WRAPPED_TOKEN_VAULT_GENERATED_ADDRESS
} from "../../../src/generated/StoxWrappedTokenVault.pointers.sol";
import {
    CREATION_CODE as STOX_UNIFIED_DEPLOYER_CREATION_CODE,
    RUNTIME_CODE as STOX_UNIFIED_DEPLOYER_RUNTIME_CODE,
    DEPLOYED_ADDRESS as STOX_UNIFIED_DEPLOYER_GENERATED_ADDRESS
} from "../../../src/generated/StoxUnifiedDeployer.pointers.sol";
import {StoxWrappedTokenVaultBeacon} from "../../../src/concrete/StoxWrappedTokenVaultBeacon.sol";
import {
    StoxWrappedTokenVaultBeaconSetDeployer
} from "../../../src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol";
import {
    StoxOffchainAssetReceiptVaultBeaconSetDeployer
} from "../../../src/concrete/deploy/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {
    CREATION_CODE as STOX_BEACON_CREATION_CODE,
    RUNTIME_CODE as STOX_BEACON_RUNTIME_CODE,
    DEPLOYED_ADDRESS as STOX_BEACON_GENERATED_ADDRESS
} from "../../../src/generated/StoxWrappedTokenVaultBeacon.pointers.sol";
import {
    CREATION_CODE as STOX_BEACON_SET_DEPLOYER_CREATION_CODE,
    RUNTIME_CODE as STOX_BEACON_SET_DEPLOYER_RUNTIME_CODE,
    DEPLOYED_ADDRESS as STOX_BEACON_SET_DEPLOYER_GENERATED_ADDRESS
} from "../../../src/generated/StoxWrappedTokenVaultBeaconSetDeployer.pointers.sol";
import {
    CREATION_CODE as STOX_OARV_DEPLOYER_CREATION_CODE,
    RUNTIME_CODE as STOX_OARV_DEPLOYER_RUNTIME_CODE,
    DEPLOYED_ADDRESS as STOX_OARV_DEPLOYER_GENERATED_ADDRESS
} from "../../../src/generated/StoxOffchainAssetReceiptVaultBeaconSetDeployer.pointers.sol";

contract LibProdDeployV2Test is Test {
    // --- Zoltu deploy address tests ---

    /// Deploying StoxReceipt via Zoltu MUST produce the expected address and
    /// codehash.
    function testDeployAddressStoxReceipt() external {
        LibRainDeploy.etchZoltuFactory(vm);
        address deployed = LibRainDeploy.deployZoltu(type(StoxReceipt).creationCode);
        assertEq(deployed, LibProdDeployV2.STOX_RECEIPT);
        assertTrue(deployed.code.length > 0);
        assertEq(deployed.codehash, LibProdDeployV2.STOX_RECEIPT_CODEHASH);
    }

    /// Deploying StoxReceiptVault via Zoltu MUST produce the expected address
    /// and codehash.
    function testDeployAddressStoxReceiptVault() external {
        LibRainDeploy.etchZoltuFactory(vm);
        address deployed = LibRainDeploy.deployZoltu(type(StoxReceiptVault).creationCode);
        assertEq(deployed, LibProdDeployV2.STOX_RECEIPT_VAULT);
        assertTrue(deployed.code.length > 0);
        assertEq(deployed.codehash, LibProdDeployV2.STOX_RECEIPT_VAULT_CODEHASH);
    }

    /// Deploying StoxWrappedTokenVault via Zoltu MUST produce the expected
    /// address and codehash.
    function testDeployAddressStoxWrappedTokenVault() external {
        LibRainDeploy.etchZoltuFactory(vm);
        address deployed = LibRainDeploy.deployZoltu(type(StoxWrappedTokenVault).creationCode);
        assertEq(deployed, LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT);
        assertTrue(deployed.code.length > 0);
        assertEq(deployed.codehash, LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_CODEHASH);
    }

    /// Deploying StoxUnifiedDeployer via Zoltu MUST produce the expected
    /// address and codehash.
    function testDeployAddressStoxUnifiedDeployer() external {
        LibRainDeploy.etchZoltuFactory(vm);
        address deployed = LibRainDeploy.deployZoltu(type(StoxUnifiedDeployer).creationCode);
        assertEq(deployed, LibProdDeployV2.STOX_UNIFIED_DEPLOYER);
        assertTrue(deployed.code.length > 0);
        assertEq(deployed.codehash, LibProdDeployV2.STOX_UNIFIED_DEPLOYER_CODEHASH);
    }

    // --- Fresh codehash tests ---

    /// Fresh-compiled StoxReceipt codehash MUST match the pointer constant.
    function testCodehashStoxReceipt() external {
        StoxReceipt c = new StoxReceipt();
        assertEq(address(c).codehash, LibProdDeployV2.STOX_RECEIPT_CODEHASH);
    }

    /// Fresh-compiled StoxReceiptVault codehash MUST match the pointer
    /// constant.
    function testCodehashStoxReceiptVault() external {
        StoxReceiptVault c = new StoxReceiptVault();
        assertEq(address(c).codehash, LibProdDeployV2.STOX_RECEIPT_VAULT_CODEHASH);
    }

    /// Fresh-compiled StoxWrappedTokenVault codehash MUST match the pointer
    /// constant.
    function testCodehashStoxWrappedTokenVault() external {
        StoxWrappedTokenVault c = new StoxWrappedTokenVault();
        assertEq(address(c).codehash, LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_CODEHASH);
    }

    /// Fresh-compiled StoxUnifiedDeployer codehash MUST match the pointer
    /// constant.
    function testCodehashStoxUnifiedDeployer() external {
        StoxUnifiedDeployer c = new StoxUnifiedDeployer();
        assertEq(address(c).codehash, LibProdDeployV2.STOX_UNIFIED_DEPLOYER_CODEHASH);
    }

    // --- Creation code tests ---

    /// Pointer creation code for StoxReceipt MUST match compiler output.
    function testCreationCodeStoxReceipt() external pure {
        assertEq(keccak256(STOX_RECEIPT_CREATION_CODE), keccak256(type(StoxReceipt).creationCode));
    }

    /// Pointer creation code for StoxReceiptVault MUST match compiler output.
    function testCreationCodeStoxReceiptVault() external pure {
        assertEq(keccak256(STOX_RECEIPT_VAULT_CREATION_CODE), keccak256(type(StoxReceiptVault).creationCode));
    }

    /// Pointer creation code for StoxWrappedTokenVault MUST match compiler
    /// output.
    function testCreationCodeStoxWrappedTokenVault() external pure {
        assertEq(keccak256(STOX_WRAPPED_TOKEN_VAULT_CREATION_CODE), keccak256(type(StoxWrappedTokenVault).creationCode));
    }

    /// Pointer creation code for StoxUnifiedDeployer MUST match compiler
    /// output.
    function testCreationCodeStoxUnifiedDeployer() external pure {
        assertEq(keccak256(STOX_UNIFIED_DEPLOYER_CREATION_CODE), keccak256(type(StoxUnifiedDeployer).creationCode));
    }

    // --- Runtime code tests ---

    /// Pointer runtime code for StoxReceipt MUST match deployed bytecode.
    function testRuntimeCodeStoxReceipt() external {
        StoxReceipt c = new StoxReceipt();
        assertEq(keccak256(STOX_RECEIPT_RUNTIME_CODE), keccak256(address(c).code));
    }

    /// Pointer runtime code for StoxReceiptVault MUST match deployed bytecode.
    function testRuntimeCodeStoxReceiptVault() external {
        StoxReceiptVault c = new StoxReceiptVault();
        assertEq(keccak256(STOX_RECEIPT_VAULT_RUNTIME_CODE), keccak256(address(c).code));
    }

    /// Pointer runtime code for StoxWrappedTokenVault MUST match deployed
    /// bytecode.
    function testRuntimeCodeStoxWrappedTokenVault() external {
        StoxWrappedTokenVault c = new StoxWrappedTokenVault();
        assertEq(keccak256(STOX_WRAPPED_TOKEN_VAULT_RUNTIME_CODE), keccak256(address(c).code));
    }

    /// Pointer runtime code for StoxUnifiedDeployer MUST match deployed
    /// bytecode.
    function testRuntimeCodeStoxUnifiedDeployer() external {
        StoxUnifiedDeployer c = new StoxUnifiedDeployer();
        assertEq(keccak256(STOX_UNIFIED_DEPLOYER_RUNTIME_CODE), keccak256(address(c).code));
    }

    // --- Generated address consistency tests ---

    /// Generated pointer address for StoxReceipt MUST match library constant.
    function testGeneratedAddressStoxReceipt() external pure {
        assertEq(STOX_RECEIPT_GENERATED_ADDRESS, LibProdDeployV2.STOX_RECEIPT);
    }

    /// Generated pointer address for StoxReceiptVault MUST match library
    /// constant.
    function testGeneratedAddressStoxReceiptVault() external pure {
        assertEq(STOX_RECEIPT_VAULT_GENERATED_ADDRESS, LibProdDeployV2.STOX_RECEIPT_VAULT);
    }

    /// Generated pointer address for StoxWrappedTokenVault MUST match library
    /// constant.
    function testGeneratedAddressStoxWrappedTokenVault() external pure {
        assertEq(STOX_WRAPPED_TOKEN_VAULT_GENERATED_ADDRESS, LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT);
    }

    /// Generated pointer address for StoxUnifiedDeployer MUST match library
    /// constant.
    function testGeneratedAddressStoxUnifiedDeployer() external pure {
        assertEq(STOX_UNIFIED_DEPLOYER_GENERATED_ADDRESS, LibProdDeployV2.STOX_UNIFIED_DEPLOYER);
    }

    // --- StoxWrappedTokenVaultBeacon ---

    /// Deploying StoxWrappedTokenVaultBeacon via Zoltu MUST produce the
    /// expected address and codehash.
    function testDeployAddressStoxWrappedTokenVaultBeacon() external {
        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(type(StoxWrappedTokenVault).creationCode);
        address deployed = LibRainDeploy.deployZoltu(type(StoxWrappedTokenVaultBeacon).creationCode);
        assertEq(deployed, LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON);
        assertTrue(deployed.code.length > 0);
        assertEq(deployed.codehash, LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_CODEHASH);
    }

    function testCreationCodeStoxWrappedTokenVaultBeacon() external pure {
        assertEq(keccak256(STOX_BEACON_CREATION_CODE), keccak256(type(StoxWrappedTokenVaultBeacon).creationCode));
    }

    function testRuntimeCodeStoxWrappedTokenVaultBeacon() external {
        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(type(StoxWrappedTokenVault).creationCode);
        address deployed = LibRainDeploy.deployZoltu(type(StoxWrappedTokenVaultBeacon).creationCode);
        assertEq(keccak256(STOX_BEACON_RUNTIME_CODE), keccak256(deployed.code));
    }

    function testGeneratedAddressStoxWrappedTokenVaultBeacon() external pure {
        assertEq(STOX_BEACON_GENERATED_ADDRESS, LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON);
    }

    // --- StoxWrappedTokenVaultBeaconSetDeployer ---

    /// Deploying StoxWrappedTokenVaultBeaconSetDeployer via Zoltu MUST produce
    /// the expected address and codehash.
    function testDeployAddressStoxWrappedTokenVaultBeaconSetDeployer() external {
        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(type(StoxWrappedTokenVault).creationCode);
        LibRainDeploy.deployZoltu(type(StoxWrappedTokenVaultBeacon).creationCode);
        address deployed = LibRainDeploy.deployZoltu(type(StoxWrappedTokenVaultBeaconSetDeployer).creationCode);
        assertEq(deployed, LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER);
        assertTrue(deployed.code.length > 0);
        assertEq(deployed.codehash, LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CODEHASH);
    }

    function testCreationCodeStoxWrappedTokenVaultBeaconSetDeployer() external pure {
        assertEq(
            keccak256(STOX_BEACON_SET_DEPLOYER_CREATION_CODE),
            keccak256(type(StoxWrappedTokenVaultBeaconSetDeployer).creationCode)
        );
    }

    function testRuntimeCodeStoxWrappedTokenVaultBeaconSetDeployer() external {
        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(type(StoxWrappedTokenVault).creationCode);
        LibRainDeploy.deployZoltu(type(StoxWrappedTokenVaultBeacon).creationCode);
        address deployed = LibRainDeploy.deployZoltu(type(StoxWrappedTokenVaultBeaconSetDeployer).creationCode);
        assertEq(keccak256(STOX_BEACON_SET_DEPLOYER_RUNTIME_CODE), keccak256(deployed.code));
    }

    function testGeneratedAddressStoxWrappedTokenVaultBeaconSetDeployer() external pure {
        assertEq(
            STOX_BEACON_SET_DEPLOYER_GENERATED_ADDRESS, LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER
        );
    }

    // --- StoxOffchainAssetReceiptVaultBeaconSetDeployer ---

    /// Deploying StoxOffchainAssetReceiptVaultBeaconSetDeployer via Zoltu MUST
    /// produce the expected address and codehash.
    function testDeployAddressStoxOffchainAssetReceiptVaultBeaconSetDeployer() external {
        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(type(StoxReceipt).creationCode);
        LibRainDeploy.deployZoltu(type(StoxReceiptVault).creationCode);
        address deployed =
            LibRainDeploy.deployZoltu(type(StoxOffchainAssetReceiptVaultBeaconSetDeployer).creationCode);
        assertEq(deployed, LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER);
        assertTrue(deployed.code.length > 0);
        assertEq(
            deployed.codehash, LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CODEHASH
        );
    }

    function testCreationCodeStoxOffchainAssetReceiptVaultBeaconSetDeployer() external pure {
        assertEq(
            keccak256(STOX_OARV_DEPLOYER_CREATION_CODE),
            keccak256(type(StoxOffchainAssetReceiptVaultBeaconSetDeployer).creationCode)
        );
    }

    function testRuntimeCodeStoxOffchainAssetReceiptVaultBeaconSetDeployer() external {
        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(type(StoxReceipt).creationCode);
        LibRainDeploy.deployZoltu(type(StoxReceiptVault).creationCode);
        address deployed =
            LibRainDeploy.deployZoltu(type(StoxOffchainAssetReceiptVaultBeaconSetDeployer).creationCode);
        assertEq(keccak256(STOX_OARV_DEPLOYER_RUNTIME_CODE), keccak256(deployed.code));
    }

    function testGeneratedAddressStoxOffchainAssetReceiptVaultBeaconSetDeployer() external pure {
        assertEq(
            STOX_OARV_DEPLOYER_GENERATED_ADDRESS,
            LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER
        );
    }
}
