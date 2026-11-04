// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {DeploySuite} from "rain-deploy-0.1.29/src/abstract/RainDeploySuitesBase.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.29/src/interface/IConfigRegistryV5.sol";
import {LibRainDeploy} from "rain-deploy-0.1.29/src/lib/LibRainDeploy.sol";

import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";
import {StoxWrappedTokenVaultBeacon} from "../../../src/concrete/StoxWrappedTokenVaultBeacon.sol";
import {LibProdDeployV4 as V4} from "../../../src/generated/LibProdDeployV4.sol";
import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";
import {LibTimelockInvariants} from "../../../src/lib/LibTimelockInvariants.sol";

contract StoxDeploySuitesWrappedTokenVaultBeaconOwnerTest is Test, StoxDeploySuites {
    function beaconSuite() internal view returns (DeploySuite memory) {
        (DeploySuite memory suite, bool found) = candidateOf(declaration(), WRAPPED_TOKEN_VAULT_BEACON);
        assertTrue(found, WRAPPED_TOKEN_VAULT_BEACON);
        return suite;
    }

    function deploySuite() external returns (address[] memory) {
        return deployLocally(declaration(), vm, beaconSuite());
    }

    function assertDeployedAtThePin(address[] memory deployed) internal pure {
        assertTrue(deployed.length > 0, "deployed");
        for (uint256 i = 0; i < deployed.length; i++) {
            assertEq(deployed[i], V4.STOX_WRAPPED_TOKEN_VAULT_BEACON_CANDIDATE, "deployed address");
        }
    }

    function testBeaconSuiteDeploysOwnedByEachNetworksBoundTimelock() external {
        uint256[] memory chainIds = suiteChainIds(beaconSuite());
        assertTrue(chainIds.length > 0, "networks");
        for (uint256 i = 0; i < chainIds.length; i++) {
            uint256 preDeploy = vm.snapshotState();
            vm.chainId(chainIds[i]);
            address timelock = LibTimelockInvariants.timelockForChainId(chainIds[i]);
            LibTestDeploy.etchConfigRegistry(vm);
            LibTestDeploy.bind(
                vm,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.BEACON_INITIAL_OWNER_NAME,
                "address",
                abi.encode(timelock)
            );
            assertDeployedAtThePin(this.deploySuite());
            assertEq(Ownable(V4.STOX_WRAPPED_TOKEN_VAULT_BEACON_CANDIDATE).owner(), timelock, "owner");
            vm.revertToState(preDeploy);
        }
    }

    function testFuzzBeaconSuiteAddressIsTheSameWhateverTheChainId(uint64 chainId, address owner) external {
        vm.assume(owner != address(0));
        vm.chainId(chainId);
        LibTestDeploy.etchConfigRegistry(vm);
        LibTestDeploy.bind(
            vm, LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.BEACON_INITIAL_OWNER_NAME, "address", abi.encode(owner)
        );
        assertEq(
            deployedAddress(declaration(), beaconSuite(), chainId),
            V4.STOX_WRAPPED_TOKEN_VAULT_BEACON_CANDIDATE,
            "declared address"
        );
        assertDeployedAtThePin(this.deploySuite());
        assertEq(Ownable(V4.STOX_WRAPPED_TOKEN_VAULT_BEACON_CANDIDATE).owner(), owner, "owner");
    }

    function testBeaconSuiteRefusesWhereTheOwnerIsUnbound() external {
        LibRainDeploy.etchDependencies(vm, beaconSuite().dependencies);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV5.NameNotRegistered.selector,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.BEACON_INITIAL_OWNER_NAME
            )
        );
        new StoxWrappedTokenVaultBeacon();

        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.DeployFailed.selector, false, address(0)));
        this.deploySuite();
    }
}
