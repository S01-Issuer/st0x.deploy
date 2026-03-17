// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {
    Deploy,
    DEPLOYMENT_SUITE_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET,
    DEPLOYMENT_SUITE_WRAPPED_TOKEN_VAULT_BEACON_SET,
    DEPLOYMENT_SUITE_UNIFIED_DEPLOYER,
    UnknownDeploymentSuite
} from "../../script/Deploy.sol";

contract DeployTest is Test {
    /// Deployment suite constants must match their keccak256 strings.
    function testDeploymentSuiteConstants() external pure {
        assertEq(
            DEPLOYMENT_SUITE_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET,
            keccak256("offchain-asset-receipt-vault-beacon-set")
        );
        assertEq(DEPLOYMENT_SUITE_WRAPPED_TOKEN_VAULT_BEACON_SET, keccak256("wrapped-token-vault-beacon-set"));
        assertEq(DEPLOYMENT_SUITE_UNIFIED_DEPLOYER, keccak256("unified-deployer"));
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
