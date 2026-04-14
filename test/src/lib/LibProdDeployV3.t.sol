// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {LibRainDeploy} from "rain.deploy/lib/LibRainDeploy.sol";
import {LibProdDeployV3} from "../../../src/lib/LibProdDeployV3.sol";
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
    IOffchainAssetReceiptVaultBeaconSetDeployerV2
} from "rain.vats/interface/IOffchainAssetReceiptVaultBeaconSetDeployerV2.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol";
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
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1.sol";
import {
    CREATION_CODE as STOX_AUTHORIZER_V1_CREATION_CODE,
    RUNTIME_CODE as STOX_AUTHORIZER_V1_RUNTIME_CODE,
    DEPLOYED_ADDRESS as STOX_AUTHORIZER_V1_GENERATED_ADDRESS
} from "../../../src/generated/StoxOffchainAssetReceiptVaultAuthorizerV1.pointers.sol";
import {
    CREATION_CODE as STOX_PAYMENT_MINT_AUTHORIZER_V1_CREATION_CODE,
    RUNTIME_CODE as STOX_PAYMENT_MINT_AUTHORIZER_V1_RUNTIME_CODE,
    DEPLOYED_ADDRESS as STOX_PAYMENT_MINT_AUTHORIZER_V1_GENERATED_ADDRESS
} from "../../../src/generated/StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1.pointers.sol";

contract LibProdDeployV3Test is Test {
    // --- Zoltu deploy address tests ---

    /// Deploying StoxReceipt via Zoltu MUST produce the expected address and
    /// codehash.
    function testDeployAddressStoxReceipt() external {
        LibRainDeploy.etchZoltuFactory(vm);
        address deployed = LibRainDeploy.deployZoltu(type(StoxReceipt).creationCode);
        assertEq(deployed, LibProdDeployV3.STOX_RECEIPT);
        assertTrue(deployed.code.length > 0);
        assertEq(deployed.codehash, LibProdDeployV3.STOX_RECEIPT_CODEHASH);
    }

    /// Deploying StoxReceiptVault via Zoltu MUST produce the expected address
    /// and codehash.
    function testDeployAddressStoxReceiptVault() external {
        LibRainDeploy.etchZoltuFactory(vm);
        address deployed = LibRainDeploy.deployZoltu(type(StoxReceiptVault).creationCode);
        assertEq(deployed, LibProdDeployV3.STOX_RECEIPT_VAULT);
        assertTrue(deployed.code.length > 0);
        assertEq(deployed.codehash, LibProdDeployV3.STOX_RECEIPT_VAULT_CODEHASH);
    }

    /// Deploying StoxWrappedTokenVault via Zoltu MUST produce the expected
    /// address and codehash.
    function testDeployAddressStoxWrappedTokenVault() external {
        LibRainDeploy.etchZoltuFactory(vm);
        address deployed = LibRainDeploy.deployZoltu(type(StoxWrappedTokenVault).creationCode);
        assertEq(deployed, LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT);
        assertTrue(deployed.code.length > 0);
        assertEq(deployed.codehash, LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_CODEHASH);
    }

    /// Deploying StoxUnifiedDeployer via Zoltu MUST produce the expected
    /// address and codehash.
    function testDeployAddressStoxUnifiedDeployer() external {
        LibRainDeploy.etchZoltuFactory(vm);
        address deployed = LibRainDeploy.deployZoltu(type(StoxUnifiedDeployer).creationCode);
        assertEq(deployed, LibProdDeployV3.STOX_UNIFIED_DEPLOYER);
        assertTrue(deployed.code.length > 0);
        assertEq(deployed.codehash, LibProdDeployV3.STOX_UNIFIED_DEPLOYER_CODEHASH);
    }

    // --- Fresh codehash tests ---

    /// Fresh-compiled StoxReceipt codehash MUST match the pointer constant.
    function testCodehashStoxReceipt() external {
        StoxReceipt c = new StoxReceipt();
        assertEq(address(c).codehash, LibProdDeployV3.STOX_RECEIPT_CODEHASH);
    }

    /// Fresh-compiled StoxReceiptVault codehash MUST match the pointer
    /// constant.
    function testCodehashStoxReceiptVault() external {
        StoxReceiptVault c = new StoxReceiptVault();
        assertEq(address(c).codehash, LibProdDeployV3.STOX_RECEIPT_VAULT_CODEHASH);
    }

    /// Fresh-compiled StoxWrappedTokenVault codehash MUST match the pointer
    /// constant.
    function testCodehashStoxWrappedTokenVault() external {
        StoxWrappedTokenVault c = new StoxWrappedTokenVault();
        assertEq(address(c).codehash, LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_CODEHASH);
    }

    /// Fresh-compiled StoxUnifiedDeployer codehash MUST match the pointer
    /// constant.
    function testCodehashStoxUnifiedDeployer() external {
        StoxUnifiedDeployer c = new StoxUnifiedDeployer();
        assertEq(address(c).codehash, LibProdDeployV3.STOX_UNIFIED_DEPLOYER_CODEHASH);
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
        assertEq(STOX_RECEIPT_GENERATED_ADDRESS, LibProdDeployV3.STOX_RECEIPT);
    }

    /// Generated pointer address for StoxReceiptVault MUST match library
    /// constant.
    function testGeneratedAddressStoxReceiptVault() external pure {
        assertEq(STOX_RECEIPT_VAULT_GENERATED_ADDRESS, LibProdDeployV3.STOX_RECEIPT_VAULT);
    }

    /// Generated pointer address for StoxWrappedTokenVault MUST match library
    /// constant.
    function testGeneratedAddressStoxWrappedTokenVault() external pure {
        assertEq(STOX_WRAPPED_TOKEN_VAULT_GENERATED_ADDRESS, LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT);
    }

    /// Generated pointer address for StoxUnifiedDeployer MUST match library
    /// constant.
    function testGeneratedAddressStoxUnifiedDeployer() external pure {
        assertEq(STOX_UNIFIED_DEPLOYER_GENERATED_ADDRESS, LibProdDeployV3.STOX_UNIFIED_DEPLOYER);
    }

    // --- StoxWrappedTokenVaultBeacon ---

    /// Deploying StoxWrappedTokenVaultBeacon via Zoltu MUST produce the
    /// expected address and codehash.
    function testDeployAddressStoxWrappedTokenVaultBeacon() external {
        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(type(StoxWrappedTokenVault).creationCode);
        address deployed = LibRainDeploy.deployZoltu(type(StoxWrappedTokenVaultBeacon).creationCode);
        assertEq(deployed, LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_BEACON);
        assertTrue(deployed.code.length > 0);
        assertEq(deployed.codehash, LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_BEACON_CODEHASH);
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
        assertEq(STOX_BEACON_GENERATED_ADDRESS, LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_BEACON);
    }

    // --- StoxWrappedTokenVaultBeaconSetDeployer ---

    /// Deploying StoxWrappedTokenVaultBeaconSetDeployer via Zoltu MUST produce
    /// the expected address and codehash.
    function testDeployAddressStoxWrappedTokenVaultBeaconSetDeployer() external {
        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(type(StoxWrappedTokenVault).creationCode);
        LibRainDeploy.deployZoltu(type(StoxWrappedTokenVaultBeacon).creationCode);
        address deployed = LibRainDeploy.deployZoltu(type(StoxWrappedTokenVaultBeaconSetDeployer).creationCode);
        assertEq(deployed, LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER);
        assertTrue(deployed.code.length > 0);
        assertEq(deployed.codehash, LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CODEHASH);
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
            STOX_BEACON_SET_DEPLOYER_GENERATED_ADDRESS, LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER
        );
    }

    // --- StoxOffchainAssetReceiptVaultBeaconSetDeployer ---

    /// Deploying StoxOffchainAssetReceiptVaultBeaconSetDeployer via Zoltu MUST
    /// produce the expected address and codehash.
    function testDeployAddressStoxOffchainAssetReceiptVaultBeaconSetDeployer() external {
        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(type(StoxReceipt).creationCode);
        LibRainDeploy.deployZoltu(type(StoxReceiptVault).creationCode);
        address deployed = LibRainDeploy.deployZoltu(type(StoxOffchainAssetReceiptVaultBeaconSetDeployer).creationCode);
        assertEq(deployed, LibProdDeployV3.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER);
        assertTrue(deployed.code.length > 0);
        assertEq(deployed.codehash, LibProdDeployV3.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CODEHASH);
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
        address deployed = LibRainDeploy.deployZoltu(type(StoxOffchainAssetReceiptVaultBeaconSetDeployer).creationCode);
        assertEq(keccak256(STOX_OARV_DEPLOYER_RUNTIME_CODE), keccak256(deployed.code));
    }

    function testGeneratedAddressStoxOffchainAssetReceiptVaultBeaconSetDeployer() external pure {
        assertEq(
            STOX_OARV_DEPLOYER_GENERATED_ADDRESS, LibProdDeployV3.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER
        );
    }

    // --- OARV deployer beacon configuration ---

    /// OARV deployer's receipt beacon has correct implementation and owner.
    function testOarvDeployerReceiptBeaconConfig() external {
        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(type(StoxReceipt).creationCode);
        LibRainDeploy.deployZoltu(type(StoxReceiptVault).creationCode);
        address deployed = LibRainDeploy.deployZoltu(type(StoxOffchainAssetReceiptVaultBeaconSetDeployer).creationCode);
        IOffchainAssetReceiptVaultBeaconSetDeployerV2 deployer = IOffchainAssetReceiptVaultBeaconSetDeployerV2(deployed);

        IBeacon receiptBeacon = deployer.iReceiptBeacon();
        assertEq(receiptBeacon.implementation(), LibProdDeployV3.STOX_RECEIPT, "receipt beacon implementation mismatch");
        assertEq(
            Ownable(address(receiptBeacon)).owner(),
            LibProdDeployV3.BEACON_INITIAL_OWNER,
            "receipt beacon owner mismatch"
        );
    }

    /// OARV deployer's vault beacon has correct implementation and owner.
    function testOarvDeployerVaultBeaconConfig() external {
        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(type(StoxReceipt).creationCode);
        LibRainDeploy.deployZoltu(type(StoxReceiptVault).creationCode);
        address deployed = LibRainDeploy.deployZoltu(type(StoxOffchainAssetReceiptVaultBeaconSetDeployer).creationCode);
        IOffchainAssetReceiptVaultBeaconSetDeployerV2 deployer = IOffchainAssetReceiptVaultBeaconSetDeployerV2(deployed);

        IBeacon vaultBeacon = deployer.iOffchainAssetReceiptVaultBeacon();
        assertEq(
            vaultBeacon.implementation(), LibProdDeployV3.STOX_RECEIPT_VAULT, "vault beacon implementation mismatch"
        );
        assertEq(
            Ownable(address(vaultBeacon)).owner(), LibProdDeployV3.BEACON_INITIAL_OWNER, "vault beacon owner mismatch"
        );
    }

    // --- StoxOffchainAssetReceiptVaultAuthorizerV1 ---

    /// Deploying StoxOffchainAssetReceiptVaultAuthorizerV1 via Zoltu MUST
    /// produce the expected address and codehash.
    function testDeployAddressStoxOffchainAssetReceiptVaultAuthorizerV1() external {
        LibRainDeploy.etchZoltuFactory(vm);
        address deployed = LibRainDeploy.deployZoltu(type(StoxOffchainAssetReceiptVaultAuthorizerV1).creationCode);
        assertEq(deployed, LibProdDeployV3.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1);
        assertTrue(deployed.code.length > 0);
        assertEq(deployed.codehash, LibProdDeployV3.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CODEHASH);
    }

    /// Fresh-compiled StoxOffchainAssetReceiptVaultAuthorizerV1 codehash MUST
    /// match the pointer constant.
    function testCodehashStoxOffchainAssetReceiptVaultAuthorizerV1() external {
        StoxOffchainAssetReceiptVaultAuthorizerV1 c = new StoxOffchainAssetReceiptVaultAuthorizerV1();
        assertEq(address(c).codehash, LibProdDeployV3.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CODEHASH);
    }

    /// Pointer creation code for StoxOffchainAssetReceiptVaultAuthorizerV1
    /// MUST match compiler output.
    function testCreationCodeStoxOffchainAssetReceiptVaultAuthorizerV1() external pure {
        assertEq(
            keccak256(STOX_AUTHORIZER_V1_CREATION_CODE),
            keccak256(type(StoxOffchainAssetReceiptVaultAuthorizerV1).creationCode)
        );
    }

    /// Pointer runtime code for StoxOffchainAssetReceiptVaultAuthorizerV1
    /// MUST match deployed bytecode.
    function testRuntimeCodeStoxOffchainAssetReceiptVaultAuthorizerV1() external {
        StoxOffchainAssetReceiptVaultAuthorizerV1 c = new StoxOffchainAssetReceiptVaultAuthorizerV1();
        assertEq(keccak256(STOX_AUTHORIZER_V1_RUNTIME_CODE), keccak256(address(c).code));
    }

    /// Generated pointer address for StoxOffchainAssetReceiptVaultAuthorizerV1
    /// MUST match library constant.
    function testGeneratedAddressStoxOffchainAssetReceiptVaultAuthorizerV1() external pure {
        assertEq(STOX_AUTHORIZER_V1_GENERATED_ADDRESS, LibProdDeployV3.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1);
    }

    // --- StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1 ---

    /// Deploying StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1 via
    /// Zoltu MUST produce the expected address and codehash.
    function testDeployAddressStoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1() external {
        LibRainDeploy.etchZoltuFactory(vm);
        address deployed =
            LibRainDeploy.deployZoltu(type(StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1).creationCode);
        assertEq(deployed, LibProdDeployV3.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1);
        assertTrue(deployed.code.length > 0);
        assertEq(
            deployed.codehash, LibProdDeployV3.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_CODEHASH
        );
    }

    /// Fresh-compiled StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1
    /// codehash MUST match the pointer constant.
    function testCodehashStoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1() external {
        StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1 c =
            new StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1();
        assertEq(
            address(c).codehash, LibProdDeployV3.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_CODEHASH
        );
    }

    /// Pointer creation code for
    /// StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1 MUST match
    /// compiler output.
    function testCreationCodeStoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1() external pure {
        assertEq(
            keccak256(STOX_PAYMENT_MINT_AUTHORIZER_V1_CREATION_CODE),
            keccak256(type(StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1).creationCode)
        );
    }

    /// Pointer runtime code for
    /// StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1 MUST match
    /// deployed bytecode.
    function testRuntimeCodeStoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1() external {
        StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1 c =
            new StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1();
        assertEq(keccak256(STOX_PAYMENT_MINT_AUTHORIZER_V1_RUNTIME_CODE), keccak256(address(c).code));
    }

    /// Generated pointer address for
    /// StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1 MUST match library
    /// constant.
    function testGeneratedAddressStoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1() external pure {
        assertEq(
            STOX_PAYMENT_MINT_AUTHORIZER_V1_GENERATED_ADDRESS,
            LibProdDeployV3.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1
        );
    }
}
