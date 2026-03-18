// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {
    Deploy,
    DEPLOYMENT_SUITE_STOX_RECEIPT,
    DEPLOYMENT_SUITE_STOX_RECEIPT_VAULT,
    DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT,
    DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_BEACON,
    DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER,
    DEPLOYMENT_SUITE_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER,
    DEPLOYMENT_SUITE_STOX_UNIFIED_DEPLOYER,
    UnknownDeploymentSuite
} from "../../script/Deploy.sol";

contract DeployTest is Test {
    /// Deployment suite constants must match their keccak256 strings.
    function testDeploymentSuiteConstants() external pure {
        assertEq(DEPLOYMENT_SUITE_STOX_RECEIPT, keccak256("stox-receipt"));
        assertEq(DEPLOYMENT_SUITE_STOX_RECEIPT_VAULT, keccak256("stox-receipt-vault"));
        assertEq(DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT, keccak256("stox-wrapped-token-vault"));
        assertEq(DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_BEACON, keccak256("stox-wrapped-token-vault-beacon"));
        assertEq(
            DEPLOYMENT_SUITE_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER,
            keccak256("stox-wrapped-token-vault-beacon-set-deployer")
        );
        assertEq(
            DEPLOYMENT_SUITE_STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER,
            keccak256("stox-offchain-asset-receipt-vault-beacon-set-deployer")
        );
        assertEq(DEPLOYMENT_SUITE_STOX_UNIFIED_DEPLOYER, keccak256("stox-unified-deployer"));
    }

    /// Unknown deployment suite must revert with UnknownDeploymentSuite.
    function testUnknownDeploymentSuiteReverts() external {
        Deploy deploy = new Deploy();
        vm.setEnv("DEPLOYMENT_KEY", vm.toString(uint256(1)));
        vm.setEnv("DEPLOYMENT_SUITE", "unknown-suite");
        vm.expectRevert(
            abi.encodeWithSelector(UnknownDeploymentSuite.selector, keccak256("unknown-suite"))
        );
        deploy.run();
    }
}
