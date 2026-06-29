// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {
    Deploy,
    DEPLOYMENT_SUITE_STOX_RECEIPT_V4,
    DEPLOYMENT_SUITE_STOX_RECEIPT_VAULT_V4,
    DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_V4,
    DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_BEACON_V4,
    DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_V4,
    DEPLOYMENT_SUITE_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_V4,
    DEPLOYMENT_SUITE_STOX_UNIFIED_DEPLOYER_V4,
    DEPLOYMENT_SUITE_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_V4,
    DEPLOYMENT_SUITE_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_V4,
    DEPLOYMENT_SUITE_STOX_CORPORATE_ACTIONS_FACET_V4,
    UnknownDeploymentSuite
} from "../../script/Deploy.sol";

contract DeployTest is Test {
    /// Deployment suite constants must match their keccak256 strings.
    function testDeploymentSuiteConstants() external pure {
        assertEq(DEPLOYMENT_SUITE_STOX_RECEIPT_V4, keccak256("stox-receipt-v4"));
        assertEq(DEPLOYMENT_SUITE_STOX_RECEIPT_VAULT_V4, keccak256("stox-receipt-vault-v4"));
        assertEq(DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_V4, keccak256("stox-wrapped-token-vault-v4"));
        assertEq(DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_BEACON_V4, keccak256("stox-wrapped-token-vault-beacon-v4"));
        assertEq(
            DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_V4,
            keccak256("stox-wrapped-token-vault-beacon-set-deployer-v4")
        );
        assertEq(
            DEPLOYMENT_SUITE_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_V4,
            keccak256("stox-offchain-asset-receipt-vault-beacon-set-deployer-v4")
        );
        assertEq(DEPLOYMENT_SUITE_STOX_UNIFIED_DEPLOYER_V4, keccak256("stox-unified-deployer-v4"));
        assertEq(
            DEPLOYMENT_SUITE_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_V4,
            keccak256("stox-offchain-asset-receipt-vault-authorizer-v1-v4")
        );
        assertEq(
            DEPLOYMENT_SUITE_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_V4,
            keccak256("stox-offchain-asset-receipt-vault-payment-mint-authorizer-v1-v4")
        );
        assertEq(DEPLOYMENT_SUITE_STOX_CORPORATE_ACTIONS_FACET_V4, keccak256("stox-corporate-actions-facet-v4"));
    }

    /// Unknown deployment suite must revert with UnknownDeploymentSuite.
    function testUnknownDeploymentSuiteReverts() external {
        Deploy deploy = new Deploy();
        vm.setEnv("DEPLOYMENT_KEY", vm.toString(uint256(1)));
        vm.setEnv("DEPLOYMENT_SUITE", "unknown-suite");
        vm.expectRevert(abi.encodeWithSelector(UnknownDeploymentSuite.selector, keccak256("unknown-suite")));
        deploy.run();
    }
}
