// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {DeploySuite} from "rain-deploy-0.1.38/src/abstract/RainDeploySuitesBase.sol";
import {BYTECODE_HASH as TIMELOCK_BYTECODE_HASH} from "rain-deploy-0.1.38/src/generated/0_1_18/TimelockController.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.38/src/interface/IConfigRegistryV5.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.38/src/lib/LibRainDeploy.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.38/src/lib/LibRegistryAuthority.sol";
import {LibTimelockController} from "rain-deploy-0.1.38/src/lib/LibTimelockController.sol";
import {
    DEPOSIT_ADMIN,
    NonCanonicalInitialAdmin
} from "rain-vats-0.2.25/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {AuthoriserInitialAdminMismatch} from "../../script/Deploy.sol";
import {LibProdDeployCurrent} from "../../src/generated/LibProdDeployCurrent.sol";
import {LibAuthoriserClone} from "../../src/lib/LibAuthoriserClone.sol";
import {ExpectedGrantMissing} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibTestDeploy} from "../lib/LibTestDeploy.sol";
import {StoxAuthorizerInitTest} from "../lib/StoxAuthorizerInitTest.sol";
import {DeployPreDeployCheckHarness} from "./DeployPreDeployCheckHarness.sol";

contract DeployAuthoriserInitialAdminTest is StoxAuthorizerInitTest {
    DeployPreDeployCheckHarness internal harness;

    function setUp() external {
        harness = new DeployPreDeployCheckHarness();
        LibTestDeploy.etchConfigRegistry(vm);
    }

    function bindAuthoriserInitialAdminValue(bytes memory value) internal {
        LibTestDeploy.bind(
            vm, LibRegistryAuthority.ROOT_AUTHORITY, LibStoxConfig.AUTHORISER_INITIAL_ADMIN_NAME, "address", value
        );
    }

    function bindAuthoriserInitialAdmin(address admin) internal {
        bindAuthoriserInitialAdminValue(abi.encode(admin));
    }

    /// Deploys the chain's per-Safe governance timelock through the Zoltu factory, as its deploy does.
    function deployProdTimelock(uint256 chainId) internal returns (address) {
        LibRainDeploy.etchZoltuFactory(vm);
        address timelock =
            LibRainDeploy.deployZoltu(LibTimelockInvariants.timelockInitCode(LibSafeInvariants.safeForChainId(chainId)));
        assertEq(timelock, LibTimelockInvariants.timelockForChainId(chainId), "timelock pin");
        return timelock;
    }

    function expectMismatch(address bound, uint256 chainId) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                AuthoriserInitialAdminMismatch.selector, bound, LibTimelockInvariants.timelockForChainId(chainId)
            )
        );
    }

    function expectNonCanonical() internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                NonCanonicalInitialAdmin.selector,
                LibRegistryAuthority.ROOT_AUTHORITY,
                LibStoxConfig.AUTHORISER_INITIAL_ADMIN_NAME
            )
        );
    }

    function testAuthoriserAcceptsEachChainsProdTimelock() external {
        DeploySuite memory suite = harness.authoriserSuite();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        assertTrue(networks.length > 0, "networks");
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 snapshot = vm.snapshotState();
            vm.chainId(networks[i].chainId);
            bindAuthoriserInitialAdmin(deployProdTimelock(networks[i].chainId));
            harness.exposedPreDeployCheck(suite, networks[i]);
            vm.revertToState(snapshot);
        }
    }

    /// The binding check runs first: with the timelock missing too, an unbound admin is what the operator sees.
    function testAuthoriserRefusesUnboundInitialAdmin() external {
        DeploySuite memory suite = harness.authoriserSuite();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IConfigRegistryV5.NameNotRegistered.selector,
                    LibRegistryAuthority.ROOT_AUTHORITY,
                    LibStoxConfig.AUTHORISER_INITIAL_ADMIN_NAME
                )
            );
            harness.exposedPreDeployCheck(suite, networks[i]);
        }
    }

    /// The timelock is not deployed, so the binding refusal comes first.
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

    function testAuthoriserRefusesAnUndeployedTimelock() external {
        DeploySuite memory suite = harness.authoriserSuite();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            address timelock = LibTimelockInvariants.timelockForChainId(networks[i].chainId);
            bindAuthoriserInitialAdmin(timelock);
            vm.expectRevert(abi.encodeWithSelector(LibTimelockController.TimelockNotDeployed.selector, timelock));
            harness.exposedPreDeployCheck(suite, networks[i]);
        }
    }

    function testAuthoriserRefusesATimelockWithOtherCode(bytes memory code) external {
        vm.assume(code.length > 0 && code[0] != 0xef);
        vm.assume(keccak256(code) != TIMELOCK_BYTECODE_HASH);
        DeploySuite memory suite = harness.authoriserSuite();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            address timelock = LibTimelockInvariants.timelockForChainId(networks[i].chainId);
            bindAuthoriserInitialAdmin(timelock);
            vm.etch(timelock, code);
            vm.expectRevert(
                abi.encodeWithSelector(
                    LibTimelockController.TimelockCodehashMismatch.selector,
                    timelock,
                    TIMELOCK_BYTECODE_HASH,
                    keccak256(code)
                )
            );
            harness.exposedPreDeployCheck(suite, networks[i]);
        }
    }

    function testAuthoriserRefusesATimelockWithoutTheSafeAsProposer() external {
        DeploySuite memory suite = harness.authoriserSuite();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 snapshot = vm.snapshotState();
            vm.chainId(networks[i].chainId);
            address timelock = deployProdTimelock(networks[i].chainId);
            address safe = LibSafeInvariants.safeForChainId(networks[i].chainId);
            bindAuthoriserInitialAdmin(timelock);
            vm.prank(timelock);
            IAccessControl(timelock).revokeRole(LibTimelockInvariants.TIMELOCK_PROPOSER_ROLE, safe);
            vm.expectRevert(
                abi.encodeWithSelector(
                    LibTimelockController.TimelockMissingRole.selector,
                    timelock,
                    LibTimelockInvariants.TIMELOCK_PROPOSER_ROLE,
                    safe
                )
            );
            harness.exposedPreDeployCheck(suite, networks[i]);
            vm.revertToState(snapshot);
        }
    }

    /// The open-salt clone takes whatever admin is bound when anyone deploys it, and is then skipped.
    function testFuzzAuthoriserRefusesAnExistingCloneWithAnotherAdmin(address other) external {
        vm.assume(other != address(0));
        DeploySuite memory suite = harness.authoriserSuite();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            vm.assume(other != LibTimelockInvariants.timelockForChainId(networks[i].chainId));
        }
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 snapshot = vm.snapshotState();
            vm.chainId(networks[i].chainId);
            bindAuthoriserInitialAdmin(other);
            harness.deployAuthoriserCloneOnChain();
            address timelock = deployProdTimelock(networks[i].chainId);
            bindAuthoriserInitialAdmin(timelock);
            vm.expectRevert(
                abi.encodeWithSelector(
                    ExpectedGrantMissing.selector, LibAuthoriserClone.cloneDeployedAddress(), DEPOSIT_ADMIN, timelock
                )
            );
            harness.exposedPreDeployCheck(suite, networks[i]);
            vm.revertToState(snapshot);
        }
    }

    function testAuthoriserRefusesAnExistingCloneMissingAnyAdminRole() external {
        DeploySuite memory suite = harness.authoriserSuite();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        bytes32[7] memory admins = adminRoles();
        address clone = LibAuthoriserClone.cloneDeployedAddress();
        for (uint256 i = 0; i < networks.length; i++) {
            for (uint256 j = 0; j < admins.length; j++) {
                uint256 snapshot = vm.snapshotState();
                vm.chainId(networks[i].chainId);
                address timelock = deployProdTimelock(networks[i].chainId);
                bindAuthoriserInitialAdmin(timelock);
                harness.deployAuthoriserCloneOnChain();
                vm.prank(timelock);
                IAccessControl(clone).renounceRole(admins[j], timelock);
                vm.expectRevert(abi.encodeWithSelector(ExpectedGrantMissing.selector, clone, admins[j], timelock));
                harness.exposedPreDeployCheck(suite, networks[i]);
                vm.revertToState(snapshot);
            }
        }
    }

    /// A rerun after the clone's own deploy is not refused.
    function testAuthoriserAcceptsAnExistingCloneWithTheTimelockAdmin() external {
        DeploySuite memory suite = harness.authoriserSuite();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 snapshot = vm.snapshotState();
            vm.chainId(networks[i].chainId);
            bindAuthoriserInitialAdmin(deployProdTimelock(networks[i].chainId));
            harness.deployAuthoriserCloneOnChain();
            assertTrue(LibAuthoriserClone.cloneDeployedAddress().code.length > 0, "clone deployed");
            harness.exposedPreDeployCheck(suite, networks[i]);
            vm.revertToState(snapshot);
        }
    }

    function testFuzzAuthoriserRefusesTrailingBytesAfterTheTimelock(bytes memory extra) external {
        vm.assume(extra.length > 0);
        DeploySuite memory suite = harness.authoriserSuite();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            bindAuthoriserInitialAdminValue(
                abi.encodePacked(abi.encode(LibTimelockInvariants.timelockForChainId(networks[i].chainId)), extra)
            );
            expectNonCanonical();
            harness.exposedPreDeployCheck(suite, networks[i]);
        }
    }

    function testFuzzAuthoriserRefusesDirtyUpperBitsOverTheTimelock(uint96 dirty) external {
        vm.assume(dirty != 0);
        DeploySuite memory suite = harness.authoriserSuite();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            vm.chainId(networks[i].chainId);
            address timelock = LibTimelockInvariants.timelockForChainId(networks[i].chainId);
            bindAuthoriserInitialAdminValue(abi.encode(uint256(uint160(timelock)) | (uint256(dirty) << 160)));
            expectNonCanonical();
            harness.exposedPreDeployCheck(suite, networks[i]);
        }
    }
}
