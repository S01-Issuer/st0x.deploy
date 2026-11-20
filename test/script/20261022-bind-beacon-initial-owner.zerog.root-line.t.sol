// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {LibProdDeployCurrent} from "../../src/generated/LibProdDeployCurrent.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {LibStoxMigrations, ZerogCurrentSourceDeployed} from "../../src/lib/LibStoxMigrations.sol";
import {RootNameBound} from "../../src/lib/LibRootConfigBinding.sol";
import {IRecordScriptHooks} from "../lib/RootLineRecordScriptTest.sol";
import {BindBeaconInitialOwnerHarness} from "./BindBeaconInitialOwnerHarness.sol";
import {ZerogRootLineScriptTest} from "./ZerogRootLineScriptTest.sol";

/// @title BindBeaconInitialOwnerZerogRootLineTest
/// @notice The bind on 0G, onto the token creation's record: the record alone, since no current-source suite deploys
/// on 0G. The arm refuses once the name is bound or the suite timelock it names has code there.
contract BindBeaconInitialOwnerZerogRootLineTest is ZerogRootLineScriptTest {
    function newScript() internal override returns (IRecordScriptHooks) {
        return IRecordScriptHooks(address(new BindBeaconInitialOwnerHarness("zerog-root-line")));
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.BIND_BEACON_INITIAL_OWNER;
    }

    function declaredOnto() internal pure override returns (bytes32) {
        return LibStoxMigrations.CREATE_ZEROG_TOKENS;
    }

    function testZerogSuiteTimelockHasNoCode() external view {
        assertEq(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK.code.length, 0, "no suite timelock on 0G");
    }

    function testZerogBundleBindsNothing() external {
        executeBundle();
        assertFalse(rootBound(LibStoxConfig.BEACON_INITIAL_OWNER_NAME), "beacon initial owner unbound");
        sScript.callAssertPostState();
    }

    /// A bound name lets anyone deploy a current-source beacon on 0G, so the arm no longer holds.
    function testZerogPreflightRefusesTheNameBound() external {
        bindAsRoot(LibStoxConfig.BEACON_INITIAL_OWNER_NAME, zerogTimelock());
        vm.expectRevert(
            abi.encodeWithSelector(RootNameBound.selector, LibStoxConfig.BEACON_INITIAL_OWNER_NAME, block.timestamp)
        );
        sScript.callPreflight();
    }

    function testZerogPostStateRefusesTheNameBound() external {
        executeBundle();
        bindAsRoot(LibStoxConfig.BEACON_INITIAL_OWNER_NAME, zerogTimelock());
        vm.expectRevert(
            abi.encodeWithSelector(RootNameBound.selector, LibStoxConfig.BEACON_INITIAL_OWNER_NAME, block.timestamp)
        );
        sScript.callAssertPostState();
    }

    function testZerogPreflightRefusesTheSuiteTimelockDeployed() external {
        vm.etch(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK, hex"00");
        vm.expectRevert(
            abi.encodeWithSelector(ZerogCurrentSourceDeployed.selector, LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK)
        );
        sScript.callPreflight();
    }

    function testZerogPostStateRefusesTheSuiteTimelockDeployed() external {
        executeBundle();
        vm.etch(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK, hex"00");
        vm.expectRevert(
            abi.encodeWithSelector(ZerogCurrentSourceDeployed.selector, LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK)
        );
        sScript.callAssertPostState();
    }
}
