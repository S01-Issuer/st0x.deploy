// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {LibProdDeployCurrent} from "../../src/generated/LibProdDeployCurrent.sol";
import {LibProdOrchestratorParams} from "../../src/lib/LibProdOrchestratorParams.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {LibStoxMigrations, ZerogCurrentSourceDeployed} from "../../src/lib/LibStoxMigrations.sol";
import {RootNameBound} from "../../src/lib/LibRootConfigBinding.sol";
import {IRecordScriptHooks} from "../lib/RootLineRecordScriptTest.sol";
import {BindOrchestratorConfigHarness} from "./BindOrchestratorConfigHarness.sol";
import {ZerogRootLineScriptTest} from "./ZerogRootLineScriptTest.sol";

/// @title BindOrchestratorConfigZerogRootLineTest
/// @notice The orchestrator config bind on 0G, onto the tQSEP record at the end of the walked line: the record alone,
/// since no current-source suite deploys on 0G. The arm refuses once either name is bound, or the current-source
/// orchestrator beacon or the suite timelock has code there.
contract BindOrchestratorConfigZerogRootLineTest is ZerogRootLineScriptTest {
    function newScript() internal override returns (IRecordScriptHooks) {
        return IRecordScriptHooks(address(new BindOrchestratorConfigHarness("zerog-root-line")));
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.BIND_ORCHESTRATOR_CONFIG;
    }

    function declaredOnto() internal pure override returns (bytes32) {
        return LibStoxMigrations.QSEP_SET_FLEET_AUTHORISER;
    }

    function beacon() internal pure returns (address) {
        return LibProdOrchestratorParams.orchestratorParams().beacon;
    }

    function testZerogCurrentSourceOrchestratorHasNoCode() external view {
        assertEq(beacon().code.length, 0, "no current-source orchestrator beacon on 0G");
        assertEq(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK.code.length, 0, "no suite timelock on 0G");
    }

    function testZerogBundleBindsNothing() external {
        executeBundle();
        assertFalse(rootBound(LibStoxConfig.ORCHESTRATOR_BEACON_NAME), "orchestrator beacon unbound");
        assertFalse(rootBound(LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME), "orchestrator initial admin unbound");
        sScript.callAssertPostState();
    }

    function boundName(bool beaconName) internal returns (bytes32 name) {
        name = beaconName ? LibStoxConfig.ORCHESTRATOR_BEACON_NAME : LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME;
        bindAsRoot(name, zerogTimelock());
    }

    function testZerogPreflightRefusesEitherNameBound(bool beaconName) external {
        bytes32 name = boundName(beaconName);
        vm.expectRevert(abi.encodeWithSelector(RootNameBound.selector, name, block.timestamp));
        sScript.callPreflight();
    }

    function testZerogPostStateRefusesEitherNameBound(bool beaconName) external {
        executeBundle();
        bytes32 name = boundName(beaconName);
        vm.expectRevert(abi.encodeWithSelector(RootNameBound.selector, name, block.timestamp));
        sScript.callAssertPostState();
    }

    function testZerogPostStateRefusesTheSuiteTimelockDeployed() external {
        executeBundle();
        vm.etch(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK, hex"00");
        vm.expectRevert(
            abi.encodeWithSelector(ZerogCurrentSourceDeployed.selector, LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK)
        );
        sScript.callAssertPostState();
    }

    function testZerogPreflightRefusesTheOrchestratorBeaconDeployed() external {
        vm.etch(beacon(), hex"00");
        vm.expectRevert(abi.encodeWithSelector(ZerogCurrentSourceDeployed.selector, beacon()));
        sScript.callPreflight();
    }

    function testZerogPreflightRefusesTheSuiteTimelockDeployed() external {
        vm.etch(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK, hex"00");
        vm.expectRevert(
            abi.encodeWithSelector(ZerogCurrentSourceDeployed.selector, LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK)
        );
        sScript.callPreflight();
    }

    function testZerogPostStateRefusesTheOrchestratorBeaconDeployed() external {
        executeBundle();
        vm.etch(beacon(), hex"00");
        vm.expectRevert(abi.encodeWithSelector(ZerogCurrentSourceDeployed.selector, beacon()));
        sScript.callAssertPostState();
    }
}
