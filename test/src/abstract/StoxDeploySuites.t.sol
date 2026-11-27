// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeployDeclaration, DeploySuite} from "rain-deploy-0.1.43/src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.43/src/lib/LibRainDeploy.sol";
import {
    DEPLOYED_ADDRESS as TOFU_DECIMALS_ADDRESS,
    BYTECODE_HASH as TOFU_DECIMALS_CODEHASH
} from "rain-tofu-erc20-decimals-deploy-0.1.9/src/generated/0_1_0/TOFUTokenDecimals.sol";

import {LibTOFUTokenDecimals} from "rain-tofu-erc20-decimals-0.1.5/src/lib/LibTOFUTokenDecimals.sol";

import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";
import {LibAuthoriserInvariants} from "../../../src/lib/LibAuthoriserInvariants.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
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

    /// @notice The EU authoriser clone names every deployment network, 0G
    /// included, and the US authoriser clone names 0G alone. Every other
    /// candidate names every deployment network but 0G, a network added after
    /// 0G included: 0G runs only the audited releases and its authoriser clones.
    function testOnlyTheAuthoriserCandidatesNameZerog() external view {
        DeployDeclaration memory declared = declaration();
        string[] memory zerogOnly = new string[](1);
        zerogOnly[0] = LibStoxDeployNetworks.ZEROG;
        uint256 clones = 0;
        for (uint256 i = 0; i < declared.candidates.length; i++) {
            string memory suite = declared.candidates[i].snapshot.suite;
            string[] memory networks = declared.candidates[i].snapshot.networks;
            if (keccak256(bytes(suite)) == keccak256(bytes(EU_AUTHORISER))) {
                assertEq(networks, LibStoxDeployNetworks.deploymentNetworks(), suite);
                clones++;
            } else if (keccak256(bytes(suite)) == keccak256(bytes(US_AUTHORISER))) {
                assertEq(networks, zerogOnly, suite);
                clones++;
            } else {
                assertEveryNetworkButZerog(networks, suite);
            }
        }
        assertEq(clones, 2, "both authoriser candidates");
    }

    /// @dev `networks` names each deployment network other than 0G once, and not 0G.
    function assertEveryNetworkButZerog(string[] memory networks, string memory suite) internal pure {
        string[] memory deployment = LibStoxDeployNetworks.deploymentNetworks();
        assertEq(networks.length, deployment.length - 1, suite);
        for (uint256 i = 0; i < deployment.length; i++) {
            bool zerog = keccak256(bytes(deployment[i])) == keccak256(bytes(LibStoxDeployNetworks.ZEROG));
            assertEq(contains(networks, deployment[i]), !zerog, string.concat(suite, " ", deployment[i]));
        }
    }

    function contains(string[] memory networks, string memory network) internal pure returns (bool) {
        for (uint256 i = 0; i < networks.length; i++) {
            if (keccak256(bytes(networks[i])) == keccak256(bytes(network))) return true;
        }
        return false;
    }

    /// @notice The US authoriser clone deploys to 0G's pinned US authoriser:
    /// the open-salt clone `LibUsAuthoriserClone` derives over the 0G Safe.
    function testUsAuthoriserCloneDeploysToTheZerogPin() external view {
        DeployDeclaration memory declared = declaration();
        (DeploySuite memory clone, bool found) = candidateOf(declared, US_AUTHORISER);
        assertTrue(found, "US authoriser candidate");
        assertEq(
            deployedAddress(declared, clone, LibSafeInvariants.ZEROG_CHAIN_ID),
            LibAuthoriserInvariants.authoriserForChainId(LibSafeInvariants.ZEROG_CHAIN_ID)
        );
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
