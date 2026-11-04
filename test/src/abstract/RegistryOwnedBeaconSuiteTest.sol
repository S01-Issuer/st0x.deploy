// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {DeploySuite} from "rain-deploy-0.1.30/src/abstract/RainDeploySuitesBase.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";

import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";
import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";
import {LibTimelockInvariants} from "../../../src/lib/LibTimelockInvariants.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";

/// A registry-owned beacon suite lands at its pin, owned by the bound
/// governance timelock and serving the current implementation, and refuses
/// where the timelock is unbound.
abstract contract RegistryOwnedBeaconSuiteTest is Test, StoxDeploySuites {
    function suiteKey() internal pure virtual returns (string memory);

    function pin() internal pure virtual returns (address);

    function implementation() internal pure virtual returns (address);

    function construct() internal virtual;

    function beaconSuite() internal view returns (DeploySuite memory) {
        (DeploySuite memory suite, bool found) = candidateOf(declaration(), suiteKey());
        assertTrue(found, suiteKey());
        return suite;
    }

    function deploySuite() external returns (address[] memory) {
        return deployLocally(declaration(), vm, beaconSuite());
    }

    function bindTimelock(address timelock) internal {
        LibTestDeploy.etchConfigRegistry(vm);
        LibTestDeploy.bind(
            vm, LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.GOVERNANCE_TIMELOCK_NAME, "address", abi.encode(timelock)
        );
    }

    function assertDeployedAtThePin(address[] memory deployed, address owner) internal view {
        assertTrue(deployed.length > 0, "deployed");
        for (uint256 i = 0; i < deployed.length; i++) {
            assertEq(deployed[i], pin(), "deployed address");
        }
        assertEq(Ownable(pin()).owner(), owner, "owner");
        assertEq(IBeacon(pin()).implementation(), implementation(), "implementation");
    }

    function testBeaconSuiteDeploysOwnedByEachNetworksBoundTimelock() external {
        uint256[] memory chainIds = suiteChainIds(beaconSuite());
        assertTrue(chainIds.length > 0, "networks");
        for (uint256 i = 0; i < chainIds.length; i++) {
            uint256 preDeploy = vm.snapshotState();
            vm.chainId(chainIds[i]);
            address timelock = LibTimelockInvariants.timelockForChainId(chainIds[i]);
            bindTimelock(timelock);
            assertDeployedAtThePin(this.deploySuite(), timelock);
            vm.revertToState(preDeploy);
        }
    }

    function testFuzzBeaconSuiteAddressIsTheSameWhateverTheChainId(uint64 chainId, address owner) external {
        vm.assume(owner != address(0));
        vm.chainId(chainId);
        bindTimelock(owner);
        assertEq(deployedAddress(declaration(), beaconSuite(), chainId), pin(), "declared address");
        assertDeployedAtThePin(this.deploySuite(), owner);
    }

    function testBeaconSuiteRefusesWhereTheOwnerIsUnbound() external {
        LibRainDeploy.etchDependencies(vm, beaconSuite().dependencies);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV5.NameNotRegistered.selector,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.GOVERNANCE_TIMELOCK_NAME
            )
        );
        construct();

        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.DeployFailed.selector, false, address(0)));
        this.deploySuite();
    }
}
