// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeploySuite} from "rain-deploy-0.1.30/src/abstract/RainDeploySuitesBase.sol";
import {SupportedNetwork} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {DEPLOYED_ADDRESS as CONFIG_REGISTRY_ADDRESS} from "rain-deploy-0.1.30/src/generated/0_1_29/ConfigRegistry.sol";
import {TimelockInitialProposerMismatch} from "../../script/Deploy.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibTestDeploy} from "../lib/LibTestDeploy.sol";
import {DeployPreDeployCheckHarness} from "./DeployPreDeployCheckHarness.sol";

contract DeployGovernanceTimelockSafeTest is Test {
    DeployPreDeployCheckHarness internal harness;

    function setUp() external {
        harness = new DeployPreDeployCheckHarness();
        LibTestDeploy.etchConfigRegistry(vm);
    }

    function bindTimelockInitialProposer(address safe) internal {
        LibTestDeploy.bind(
            vm, LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.TIMELOCK_INITIAL_PROPOSER_NAME, "address", abi.encode(safe)
        );
    }

    function assumeNoChainSafe(address bound, SupportedNetwork[] memory networks) internal pure {
        for (uint256 i = 0; i < networks.length; i++) {
            vm.assume(bound != LibSafeInvariants.safeForChainId(networks[i].chainId));
        }
    }

    function otherSuite(string memory key) internal view returns (DeploySuite memory) {
        DeploySuite memory suite = harness.governanceTimelockSuite();
        vm.assume(keccak256(bytes(key)) != keccak256(bytes(suite.suite)));
        suite.suite = key;
        return suite;
    }

    function testGovernanceTimelockRefusesUnboundTimelockInitialProposer() external {
        DeploySuite memory suite = harness.governanceTimelockSuite();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IConfigRegistryV5.NameNotRegistered.selector,
                    LibStoxConfig.ROOT_AUTHORITY,
                    LibStoxConfig.TIMELOCK_INITIAL_PROPOSER_NAME
                )
            );
            harness.exposedPreDeployCheck(suite, networks[i]);
        }
    }

    function testGovernanceTimelockRefusesOtherBoundAddress(address bound) external {
        DeploySuite memory suite = harness.governanceTimelockSuite();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        assumeNoChainSafe(bound, networks);
        bindTimelockInitialProposer(bound);
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            vm.expectRevert(
                abi.encodeWithSelector(
                    TimelockInitialProposerMismatch.selector,
                    bound,
                    LibSafeInvariants.safeForChainId(networks[i].chainId)
                )
            );
            harness.exposedPreDeployCheck(suite, networks[i]);
        }
    }

    function testGovernanceTimelockAcceptsChainSafe() external {
        DeploySuite memory suite = harness.governanceTimelockSuite();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            bindTimelockInitialProposer(LibSafeInvariants.safeForChainId(networks[i].chainId));
            harness.exposedPreDeployCheck(suite, networks[i]);
        }
    }

    function testOtherSuitesIgnoreBoundAddressTheTimelockRefuses(string memory key, address bound) external {
        DeploySuite memory timelock = harness.governanceTimelockSuite();
        DeploySuite memory other = otherSuite(key);
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        assumeNoChainSafe(bound, networks);
        bindTimelockInitialProposer(bound);
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            vm.expectRevert(
                abi.encodeWithSelector(
                    TimelockInitialProposerMismatch.selector,
                    bound,
                    LibSafeInvariants.safeForChainId(networks[i].chainId)
                )
            );
            harness.exposedPreDeployCheck(timelock, networks[i]);
            harness.exposedPreDeployCheck(other, networks[i]);
        }
    }

    function testOtherSuitesNeverReadTheRegistry(string memory key) external {
        DeploySuite memory other = otherSuite(key);
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        vm.etch(CONFIG_REGISTRY_ADDRESS, hex"");
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            harness.exposedPreDeployCheck(other, networks[i]);
        }
    }
}
