// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {DeployDeclaration, DeploySuite} from "rain-deploy-0.1.30/src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";

import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {LibAuthoriserClone} from "../../../src/lib/LibAuthoriserClone.sol";
import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../../src/lib/LibTimelockInvariants.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";
import {StoxAuthorizerInitTest} from "../../lib/StoxAuthorizerInitTest.sol";

contract StoxDeploySuitesAuthoriserTest is StoxAuthorizerInitTest, StoxDeploySuites {
    function authoriserSuite() internal view returns (DeploySuite memory) {
        (DeploySuite memory suite, bool found) = candidateOf(declaration(), AUTHORISER);
        assertTrue(found, AUTHORISER);
        return suite;
    }

    function networks() internal view returns (SupportedNetwork[] memory) {
        SupportedNetwork[] memory nets =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        assertTrue(nets.length > 0, "networks");
        return nets;
    }

    function bindAuthoriserInitialAdmin(address admin) internal {
        LibTestDeploy.etchConfigRegistry(vm);
        LibTestDeploy.bind(
            vm,
            LibRegistryAuthority.ROOT_AUTHORITY,
            LibStoxConfig.AUTHORISER_INITIAL_ADMIN_NAME,
            "address",
            abi.encode(admin)
        );
    }

    function deployOnChain() external {
        deployLocallyOnChain(declaration(), vm, authoriserSuite());
    }

    function assertAdminSeated(address admin) internal view {
        StoxOffchainAssetReceiptVaultAuthorizerV1 authoriser =
            StoxOffchainAssetReceiptVaultAuthorizerV1(LibAuthoriserClone.cloneDeployedAddress());
        bytes32[7] memory admins = adminRoles();
        for (uint256 i = 0; i < admins.length; i++) {
            assertTrue(authoriser.hasRole(admins[i], admin), "admin role");
        }
    }

    function testAuthoriserSuiteDeclaresTheCloneOnEveryNetwork() external view {
        DeployDeclaration memory declared = declaration();
        DeploySuite memory suite = authoriserSuite();
        assertEq(suite.networks, LibStoxDeployNetworks.deploymentNetworks(), "networks");
        assertEq(suite.storedDeployedAddress, LibAuthoriserClone.cloneDeployedAddress(), "stored address");
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            assertEq(
                deployedAddress(declared, suite, nets[i].chainId),
                LibAuthoriserClone.cloneDeployedAddress(),
                nets[i].name
            );
        }
    }

    function testAuthoriserSuiteDeploysTheCloneOnEveryNetwork() external {
        DeploySuite memory suite = authoriserSuite();
        bindAuthoriserInitialAdmin(LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK);
        address[] memory deployed = deployLocally(declaration(), vm, suite);
        SupportedNetwork[] memory nets = networks();
        assertEq(deployed.length, nets.length, "deployed");
        for (uint256 i = 0; i < deployed.length; i++) {
            assertEq(deployed[i], LibAuthoriserClone.cloneDeployedAddress(), nets[i].name);
        }
        assertEq(LibAuthoriserClone.cloneDeployedAddress().code, suite.storedRuntimeCode, "runtime code");
        assertEq(LibAuthoriserClone.cloneDeployedAddress().codehash, suite.storedBytecodeHash, "code hash");
        assertAdminSeated(LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK);
    }

    /// Base's timelock differs from the other chains', and the clone still lands at one address.
    function testAuthoriserSuiteSeatsEachChainsTimelockAtOneAddress() external {
        SupportedNetwork[] memory nets = networks();
        for (uint256 i = 0; i < nets.length; i++) {
            uint256 preDeploy = vm.snapshotState();
            vm.chainId(nets[i].chainId);
            address timelock = LibTimelockInvariants.timelockForChainId(nets[i].chainId);
            bindAuthoriserInitialAdmin(timelock);
            this.deployOnChain();
            assertEq(LibAuthoriserClone.cloneDeployedAddress().code, authoriserSuite().storedRuntimeCode, nets[i].name);
            assertAdminSeated(timelock);
            vm.revertToState(preDeploy);
        }
    }

    function testFuzzAuthoriserSuiteAddressIsTheSameWhateverTheChainAndAdmin(uint64 chainId, address admin) external {
        vm.assume(admin != address(0));
        vm.chainId(chainId);
        bindAuthoriserInitialAdmin(admin);
        assertEq(
            deployedAddress(declaration(), authoriserSuite(), chainId),
            LibAuthoriserClone.cloneDeployedAddress(),
            "declared address"
        );
        this.deployOnChain();
        assertEq(LibAuthoriserClone.cloneDeployedAddress().code, authoriserSuite().storedRuntimeCode, "runtime code");
        assertAdminSeated(admin);
    }
}
