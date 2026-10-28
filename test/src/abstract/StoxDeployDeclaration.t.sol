// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployVerifyDeclaration} from "rain-deploy-0.1.27/src/abstract/RainDeployVerifyDeclaration.sol";
import {ExternalDeployment} from "rain-deploy-0.1.27/src/abstract/RainDeployDeclarationChecks.sol";
import {RainDeploySuitesBase} from "rain-deploy-0.1.27/src/abstract/RainDeploySuitesBase.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY_ADDRESS,
    BYTECODE_HASH as CLONE_FACTORY_CODEHASH
} from "rain-factory-deploy-0.2.3/src/generated/0_1_15/CloneFactory.sol";
import {
    DEPLOYED_ADDRESS as TOFU_DECIMALS_ADDRESS,
    BYTECODE_HASH as TOFU_DECIMALS_CODEHASH
} from "rain-tofu-erc20-decimals-deploy-0.1.4/src/generated/0_1_0/TOFUTokenDecimals.sol";

import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";
import {StoxCorporateActionsFacet} from "../../../src/concrete/StoxCorporateActionsFacet.sol";
import {StoxReceipt} from "../../../src/concrete/StoxReceipt.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {StoxWrappedTokenVault} from "../../../src/concrete/StoxWrappedTokenVault.sol";
import {StoxWrappedTokenVaultBeacon} from "../../../src/concrete/StoxWrappedTokenVaultBeacon.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1.sol";
import {ST0xOrchestrator} from "../../../src/concrete/ST0xOrchestrator.sol";

/// @title StoxDeployDeclarationTest
/// @notice The suite fields only a dispatch, a verifier or a broadcast reads.
contract StoxDeployDeclarationTest is StoxDeploySuites, RainDeployVerifyDeclaration {
    function supportedNetworks()
        internal
        view
        override(StoxDeploySuites, RainDeploySuitesBase)
        returns (string[] memory)
    {
        return StoxDeploySuites.supportedNetworks();
    }

    function sourceCreationCode(string memory suite) internal pure override returns (bytes memory) {
        bytes32 key = keccak256(bytes(suite));
        if (key == keccak256(bytes(FACET))) return type(StoxCorporateActionsFacet).creationCode;
        if (key == keccak256(bytes(RECEIPT))) return type(StoxReceipt).creationCode;
        if (key == keccak256(bytes(RECEIPT_VAULT))) return type(StoxReceiptVault).creationCode;
        if (key == keccak256(bytes(WRAPPED_TOKEN_VAULT))) return type(StoxWrappedTokenVault).creationCode;
        if (key == keccak256(bytes(WRAPPED_TOKEN_VAULT_BEACON))) return type(StoxWrappedTokenVaultBeacon).creationCode;
        if (key == keccak256(bytes(AUTHORIZER))) return type(StoxOffchainAssetReceiptVaultAuthorizerV1).creationCode;
        if (key == keccak256(bytes(PAYMENT_MINT_AUTHORIZER))) {
            return type(StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1).creationCode;
        }
        if (key == keccak256(bytes(ORCHESTRATOR))) return type(ST0xOrchestrator).creationCode;
        revert(string.concat("no source for suite: ", suite));
    }

    function externalDeployments() internal pure override returns (ExternalDeployment[] memory) {
        ExternalDeployment[] memory externals = new ExternalDeployment[](2);
        externals[0] = ExternalDeployment({deployedAddress: CLONE_FACTORY_ADDRESS, codeHash: CLONE_FACTORY_CODEHASH});
        externals[1] = ExternalDeployment({deployedAddress: TOFU_DECIMALS_ADDRESS, codeHash: TOFU_DECIMALS_CODEHASH});
        return externals;
    }
}
