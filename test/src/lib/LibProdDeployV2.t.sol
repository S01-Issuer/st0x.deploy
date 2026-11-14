// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {LibProdDeployV2} from "../../../src/lib/LibProdDeployV2.sol";

/// @title LibProdDeployV2Test
/// @notice Validates that V2's frozen creation-bytecode constants are the
/// authentic historical code. Each frozen `hex` literal deploys through the
/// Zoltu factory to the deterministic address and runtime codehash of its V2
/// pins. Crucially these deploy the frozen constants, not
/// `type(X).creationCode`, so the assertions are independent of the current
/// compiler/optimizer settings: a legacy version is a historical audit trail,
/// never a recompile target (that role belongs to the latest version's test).
contract LibProdDeployV2Test is Test {
    /// A frozen V2 creation code and the pins it must deploy to.
    struct V2Contract {
        string name;
        bytes creationCode;
        address expectedAddress;
        bytes32 expectedCodehash;
    }

    /// Deployed in dependency order on one EVM, as the original Zoltu
    /// deployment required: the beacon constructor needs the wrapped token
    /// vault's code, the offchain set deployer the receipt and receipt vault,
    /// the wrapped token vault set deployer the beacon.
    function testV2CreationCodeDeploysToPins() external {
        V2Contract[] memory contracts = new V2Contract[](9);
        contracts[0] = V2Contract(
            "STOX_RECEIPT",
            LibProdDeployV2.PROD_STOX_RECEIPT_CREATION_BYTECODE_V2,
            LibProdDeployV2.STOX_RECEIPT,
            LibProdDeployV2.STOX_RECEIPT_CODEHASH
        );
        contracts[1] = V2Contract(
            "STOX_RECEIPT_VAULT",
            LibProdDeployV2.PROD_STOX_RECEIPT_VAULT_CREATION_BYTECODE_V2,
            LibProdDeployV2.STOX_RECEIPT_VAULT,
            LibProdDeployV2.STOX_RECEIPT_VAULT_CODEHASH
        );
        contracts[2] = V2Contract(
            "STOX_WRAPPED_TOKEN_VAULT",
            LibProdDeployV2.PROD_STOX_WRAPPED_TOKEN_VAULT_CREATION_BYTECODE_V2,
            LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT,
            LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_CODEHASH
        );
        contracts[3] = V2Contract(
            "STOX_UNIFIED_DEPLOYER",
            LibProdDeployV2.PROD_STOX_UNIFIED_DEPLOYER_CREATION_BYTECODE_V2,
            LibProdDeployV2.STOX_UNIFIED_DEPLOYER,
            LibProdDeployV2.STOX_UNIFIED_DEPLOYER_CODEHASH
        );
        contracts[4] = V2Contract(
            "STOX_WRAPPED_TOKEN_VAULT_BEACON",
            LibProdDeployV2.PROD_STOX_WRAPPED_TOKEN_VAULT_BEACON_CREATION_BYTECODE_V2,
            LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON,
            LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_CODEHASH
        );
        contracts[5] = V2Contract(
            "STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER",
            LibProdDeployV2.PROD_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CREATION_BYTECODE_V2,
            LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER,
            LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CODEHASH
        );
        contracts[6] = V2Contract(
            "STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER",
            LibProdDeployV2.PROD_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CREATION_BYTECODE_V2,
            LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER,
            LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CODEHASH
        );
        contracts[7] = V2Contract(
            "STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1",
            LibProdDeployV2.PROD_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CREATION_BYTECODE_V2,
            LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1,
            LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CODEHASH
        );
        contracts[8] = V2Contract(
            "STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1",
            LibProdDeployV2.PROD_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_CREATION_BYTECODE_V2,
            LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1,
            LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_CODEHASH
        );

        LibRainDeploy.etchZoltuFactory(vm);
        for (uint256 i = 0; i < contracts.length; i++) {
            address deployed = LibRainDeploy.deployZoltu(contracts[i].creationCode);
            assertEq(deployed, contracts[i].expectedAddress, string.concat(contracts[i].name, " address"));
            assertTrue(deployed.code.length > 0, string.concat(contracts[i].name, " has no code"));
            assertEq(deployed.codehash, contracts[i].expectedCodehash, string.concat(contracts[i].name, " codehash"));
        }
    }
}
