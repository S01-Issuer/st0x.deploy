// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {OwnerManager} from "safe-global-safe-smart-account-1.4.1-3/contracts/base/OwnerManager.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {LibConfigRegistry} from "rain-deploy-0.1.30/src/lib/LibConfigRegistry.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.30/src/lib/LibConfigRegistryDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {LibSafe} from "rain-deploy-0.1.30/src/lib/LibSafe.sol";
import {LibSafeFork} from "rain-deploy-0.1.30/src/lib/LibSafeFork.sol";
import {ITimelockControllerState, LibTimelockController} from "rain-deploy-0.1.30/src/lib/LibTimelockController.sol";

import {BeaconInitialOwnerBindingMismatch} from "../../script/20261022-bind-beacon-initial-owner.s.sol";
import {BindBeaconInitialOwnerHarness} from "./BindBeaconInitialOwnerHarness.sol";
import {BackfillMigrationRegistryV5Harness} from "./BackfillMigrationRegistryV5Harness.sol";
import {LibProdDeployCurrent} from "../../src/generated/LibProdDeployCurrent.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibTestBeaconInitialOwnerBind} from "../lib/LibTestBeaconInitialOwnerBind.sol";
import {LibTestPreBackfillFork} from "../lib/LibTestPreBackfillFork.sol";
import {IRecordScriptHooks, RootLineRecordScriptTest} from "../lib/RootLineRecordScriptTest.sol";

/// @title BindBeaconInitialOwnerRootLineTest
/// @notice The bind on HyperEVM at its pinned pre-backfill block, with the
/// governance timelock deployed and the root's unscoped approval of the Safe
/// written on the fork, onto the executed V5 backfill bundle.
contract BindBeaconInitialOwnerRootLineTest is RootLineRecordScriptTest {
    IConfigRegistryV5 internal constant CONFIG_REGISTRY =
        IConfigRegistryV5(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);

    function newScript() internal override returns (IRecordScriptHooks) {
        return IRecordScriptHooks(address(new BindBeaconInitialOwnerHarness("root-line")));
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.BIND_BEACON_INITIAL_OWNER;
    }

    function declaredOnto() internal pure override returns (bytes32) {
        return LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5;
    }

    function landBeforeOnto() internal override {
        LibTestPreBackfillFork.select(vm, LibStoxDeployNetworks.HYPEREVM);
        assertEq(
            LibTestBeaconInitialOwnerBind.deployTimelock(vm, safeAddress()),
            LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK,
            "timelock address"
        );
        LibTestBeaconInitialOwnerBind.approveSafe(vm, safeAddress());
    }

    function landOnto() internal override {
        LibSafeFork.executeBundle(
            vm, Safe(payable(safeAddress())), new BackfillMigrationRegistryV5Harness("root-line").callAuthorBundle()
        );
    }

    function restampAtThisMoment() internal override {
        bindBeaconInitialOwner(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK);
    }

    function bindBeaconInitialOwner(address owner) internal {
        vm.prank(LibRegistryAuthority.ROOT_AUTHORITY);
        CONFIG_REGISTRY.registerV5(
            LibRegistryAuthority.ROOT_AUTHORITY,
            LibStoxConfig.BEACON_INITIAL_OWNER_NAME,
            "address",
            abi.encode(owner),
            ""
        );
    }

    function executeProvenBundle() internal {
        executeBundle();
        sScript.callAssertPostState();
    }

    function testPostStateRefusesAnotherTimelock() external {
        address other = address(0xBEEF);
        executeProvenBundle();
        vm.warp(block.timestamp + 1);
        bindBeaconInitialOwner(other);
        vm.expectRevert(
            abi.encodeWithSelector(BeaconInitialOwnerBindingMismatch.selector, abi.encode(other), block.timestamp)
        );
        sScript.callAssertPostState();
    }

    function testPostStateRefusesABindingFromAnotherBlock() external {
        executeProvenBundle();
        uint256 boundAt = block.timestamp;
        vm.warp(boundAt + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                BeaconInitialOwnerBindingMismatch.selector,
                abi.encode(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK),
                boundAt
            )
        );
        sScript.callAssertPostState();
    }

    function testPreflightRefusesAnUnpinnedRegistry() external {
        vm.etch(address(CONFIG_REGISTRY), hex"00");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.UnexpectedConfigRegistryCodeHash.selector,
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH,
                keccak256(hex"00")
            )
        );
        sScript.callPreflight();
    }

    function testPostStateRefusesADriftedSafe() external {
        executeProvenBundle();
        vm.mockCall(safeAddress(), abi.encodeCall(OwnerManager.getThreshold, ()), abi.encode(uint256(4)));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibSafe.SafeThresholdMismatch.selector,
                safeAddress(),
                LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD,
                4
            )
        );
        sScript.callAssertPostState();
    }

    function testPreflightRefusesASafeOffPolicy() external {
        vm.mockCall(safeAddress(), abi.encodeCall(OwnerManager.getThreshold, ()), abi.encode(uint256(1)));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibSafe.SafeThresholdMismatch.selector,
                safeAddress(),
                LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD,
                1
            )
        );
        sScript.callPreflight();
    }

    function testPreflightRefusesATimelockOffState() external {
        address timelock = LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK;
        vm.mockCall(timelock, abi.encodeCall(ITimelockControllerState.getMinDelay, ()), abi.encode(uint256(1)));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibTimelockController.TimelockMinDelayMismatch.selector,
                timelock,
                LibTimelockInvariants.TIMELOCK_MIN_DELAY,
                1
            )
        );
        sScript.callPreflight();
    }

    function testArtifactNamesTheBundleForItsSigners() external {
        BindBeaconInitialOwnerHarness script = BindBeaconInitialOwnerHarness(address(sScript));
        script.run();
        assertEq(
            vm.parseJsonString(vm.readFile(script.callArtifactPath()), ".meta.name"),
            "ST0x: bind the beacon initial owner"
        );
    }

    function testBundleIsTheBindThenItsRootLineRecord() external view {
        SafeTx[] memory txs = sScript.callAuthorBundle();
        assertEq(txs.length, 2, "bundle length");
        assertEq(txs[0].to, address(CONFIG_REGISTRY), "bind target");
    }
}
