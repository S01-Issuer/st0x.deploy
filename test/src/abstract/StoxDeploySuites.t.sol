// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeployDeclaration, DeploySuite} from "rain-deploy-0.1.29/src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.29/src/lib/LibRainDeploy.sol";
import {
    DEPLOYED_ADDRESS as TOFU_DECIMALS_ADDRESS,
    BYTECODE_HASH as TOFU_DECIMALS_CODEHASH
} from "rain-tofu-erc20-decimals-deploy-0.1.4/src/generated/0_1_0/TOFUTokenDecimals.sol";

import {LibTOFUTokenDecimals} from "rain-tofu-erc20-decimals-0.1.4/src/lib/LibTOFUTokenDecimals.sol";

import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";
import {LibAuthoriserInvariants} from "../../../src/lib/LibAuthoriserInvariants.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";

contract StoxDeploySuitesTest is Test, StoxDeploySuites {
    function testTofuPinIsTheDeploymentSourceReaches() external pure {
        assertEq(TOFU_DECIMALS_ADDRESS, address(LibTOFUTokenDecimals.TOFU_DECIMALS_DEPLOYMENT));
        assertEq(TOFU_DECIMALS_CODEHASH, LibTOFUTokenDecimals.TOFU_DECIMALS_EXPECTED_CODE_HASH);
    }

    function testDeclarationNetworksAreTheDeploymentNetworks() external view {
        DeployDeclaration memory declared = declaration();
        assertEq(declared.networks, LibStoxDeployNetworks.deploymentNetworks(), "networks");
        assertEq(declared.deployNetworks, LibStoxDeployNetworks.deploymentNetworks(), "deploy networks");
    }

    function testEveryCandidateNamesEveryDeploymentNetwork() external view {
        DeployDeclaration memory declared = declaration();
        for (uint256 i = 0; i < declared.candidates.length; i++) {
            assertEq(
                declared.candidates[i].snapshot.networks,
                LibStoxDeployNetworks.deploymentNetworks(),
                declared.candidates[i].snapshot.suite
            );
        }
    }

    function testEuAuthoriserCloneDeploysToThePinnedCloneOnEveryNetwork() external view {
        DeployDeclaration memory declared = declaration();
        (DeploySuite memory clone, bool found) = candidateOf(declared, EU_AUTHORISER);
        assertTrue(found, "EU authoriser candidate");
        SupportedNetwork[] memory networks =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        for (uint256 i = 0; i < networks.length; i++) {
            assertEq(
                deployedAddress(declared, clone, networks[i].chainId),
                LibAuthoriserInvariants.euAuthoriserForChainId(networks[i].chainId),
                networks[i].name
            );
        }
    }
}
