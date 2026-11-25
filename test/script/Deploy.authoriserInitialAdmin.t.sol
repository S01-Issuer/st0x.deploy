// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeploySuite} from "rain-deploy-0.1.38/src/abstract/RainDeploySuitesBase.sol";
import {SupportedNetwork} from "rain-deploy-0.1.38/src/lib/LibRainDeploy.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.38/src/lib/LibRegistryAuthority.sol";
import {AuthoriserInitialAdminMismatch} from "../../script/Deploy.sol";
import {LibProdDeployCurrent} from "../../src/generated/LibProdDeployCurrent.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibTestDeploy} from "../lib/LibTestDeploy.sol";
import {DeployPreDeployCheckHarness} from "./DeployPreDeployCheckHarness.sol";

contract DeployAuthoriserInitialAdminTest is Test {
    DeployPreDeployCheckHarness internal harness;

    function setUp() external {
        harness = new DeployPreDeployCheckHarness();
        LibTestDeploy.etchConfigRegistry(vm);
    }

    function bindAuthoriserInitialAdmin(address admin) internal {
        LibTestDeploy.bind(
            vm,
            LibRegistryAuthority.ROOT_AUTHORITY,
            LibStoxConfig.AUTHORISER_INITIAL_ADMIN_NAME,
            "address",
            abi.encode(admin)
        );
    }

    function expectMismatch(address bound, uint256 chainId) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                AuthoriserInitialAdminMismatch.selector, bound, LibTimelockInvariants.timelockForChainId(chainId)
            )
        );
    }

    function testAuthoriserAcceptsEachChainsProdTimelock() external {
        DeploySuite memory suite = harness.authoriserSuite();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        assertTrue(networks.length > 0, "networks");
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            bindAuthoriserInitialAdmin(LibTimelockInvariants.timelockForChainId(networks[i].chainId));
            harness.exposedPreDeployCheck(suite, networks[i]);
        }
    }

    function testAuthoriserRefusesTheCandidateGovernanceTimelock() external {
        DeploySuite memory suite = harness.authoriserSuite();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        bindAuthoriserInitialAdmin(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK);
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            expectMismatch(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK, networks[i].chainId);
            harness.exposedPreDeployCheck(suite, networks[i]);
        }
    }

    /// Base's timelock differs from the other chains', so a constant expectation would pass one of them here.
    function testAuthoriserRefusesAnotherChainsProdTimelock() external {
        DeploySuite memory suite = harness.authoriserSuite();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        uint256 refused = 0;
        for (uint256 i = 0; i < networks.length; i++) {
            for (uint256 j = 0; j < networks.length; j++) {
                address other = LibTimelockInvariants.timelockForChainId(networks[j].chainId);
                if (other == LibTimelockInvariants.timelockForChainId(networks[i].chainId)) {
                    continue;
                }
                vm.chainId(networks[i].chainId);
                bindAuthoriserInitialAdmin(other);
                expectMismatch(other, networks[i].chainId);
                harness.exposedPreDeployCheck(suite, networks[i]);
                refused++;
            }
        }
        assertTrue(refused > 0, "some chain's timelock differs from another's");
    }

    function testFuzzAuthoriserRefusesAnyOtherBoundAdmin(address bound) external {
        DeploySuite memory suite = harness.authoriserSuite();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            vm.assume(bound != LibTimelockInvariants.timelockForChainId(networks[i].chainId));
        }
        bindAuthoriserInitialAdmin(bound);
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            expectMismatch(bound, networks[i].chainId);
            harness.exposedPreDeployCheck(suite, networks[i]);
        }
    }
}
