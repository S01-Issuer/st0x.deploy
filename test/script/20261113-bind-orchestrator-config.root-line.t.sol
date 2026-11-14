// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {OwnerManager} from "safe-global-safe-smart-account-1.4.1-3/contracts/base/OwnerManager.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {LibConfigRegistry} from "rain-deploy-0.1.30/src/lib/LibConfigRegistry.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.30/src/lib/LibConfigRegistryDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {LibSafe} from "rain-deploy-0.1.30/src/lib/LibSafe.sol";

import {OrchestratorConfigBindingMismatch} from "../../script/20261113-bind-orchestrator-config.s.sol";
import {
    scheduleRevokeServiceSignerDeclaration
} from "../../script/20261109-schedule-revoke-service-signer-deposit-withdraw.s.sol";
import {
    executeRevokeServiceSignerDeclaration
} from "../../script/20261109-execute-revoke-service-signer-deposit-withdraw.s.sol";
import {qsepSetFleetAuthoriserDeclaration} from "../../script/20261111-qsep-set-fleet-authoriser.s.sol";
import {BindOrchestratorConfigHarness} from "./BindOrchestratorConfigHarness.sol";
import {RevokeServiceSignerDepositWithdrawFixture} from "./RevokeServiceSignerDepositWithdrawFixture.sol";
import {LibProdDeployCurrent} from "../../src/generated/LibProdDeployCurrent.sol";
import {LibProdOrchestratorParams} from "../../src/lib/LibProdOrchestratorParams.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTestOrchestratorConfigBind} from "../lib/LibTestOrchestratorConfigBind.sol";
import {LibTestPreBackfillFork} from "../lib/LibTestPreBackfillFork.sol";
import {IRecordScriptHooks, RootLineRecordScriptTest} from "../lib/RootLineRecordScriptTest.sol";

/// @title BindOrchestratorConfigRootLineTest
/// @notice The bind on HyperEVM at its pinned pre-backfill block, with the
/// root line advanced through the service-signer revoke and the root's
/// unscoped approval of the Safe written on the fork, onto the tQSEP record.
contract BindOrchestratorConfigRootLineTest is RevokeServiceSignerDepositWithdrawFixture, RootLineRecordScriptTest {
    IConfigRegistryV5 internal constant CONFIG_REGISTRY =
        IConfigRegistryV5(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);

    function newScript() internal override returns (IRecordScriptHooks) {
        return IRecordScriptHooks(address(new BindOrchestratorConfigHarness("root-line")));
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.BIND_ORCHESTRATOR_CONFIG;
    }

    function declaredOnto() internal pure override returns (bytes32) {
        return LibStoxMigrations.QSEP_SET_FLEET_AUTHORISER;
    }

    function landBeforeOnto() internal override {
        LibTestPreBackfillFork.select(vm, LibStoxDeployNetworks.HYPEREVM);
        advanceRootLineToRevokeSchedule();
        writeRecord(scheduleRevokeServiceSignerDeclaration());
        writeRecord(executeRevokeServiceSignerDeclaration());
        LibTestOrchestratorConfigBind.approveSafe(vm, safeAddress());
    }

    function landOnto() internal override {
        writeRecord(qsepSetFleetAuthoriserDeclaration());
    }

    function restampAtThisMoment() internal override {
        bind(LibStoxConfig.ORCHESTRATOR_BEACON_NAME, beacon());
        bind(LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME, LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK);
    }

    function beacon() internal pure returns (address) {
        return LibProdOrchestratorParams.orchestratorParams().beacon;
    }

    function bind(bytes32 name, address value) internal {
        bindAs(name, "address", value);
    }

    function bindAs(bytes32 name, string memory valueType, address value) internal {
        vm.prank(LibRegistryAuthority.ROOT_AUTHORITY);
        CONFIG_REGISTRY.registerV5(LibRegistryAuthority.ROOT_AUTHORITY, name, valueType, abi.encode(value), "");
    }

    function executeProvenBundle() internal {
        executeBundle();
        sScript.callAssertPostState();
    }

    function testPostStateRefusesAnotherBeacon() external {
        address other = address(0xBEEF);
        executeProvenBundle();
        vm.warp(block.timestamp + 1);
        bind(LibStoxConfig.ORCHESTRATOR_BEACON_NAME, other);
        vm.expectRevert(
            abi.encodeWithSelector(
                OrchestratorConfigBindingMismatch.selector,
                LibStoxConfig.ORCHESTRATOR_BEACON_NAME,
                abi.encode(other),
                block.timestamp
            )
        );
        sScript.callAssertPostState();
    }

    function testPostStateRefusesAnotherInitialAdmin() external {
        address other = address(0xBEEF);
        executeProvenBundle();
        vm.warp(block.timestamp + 1);
        bind(LibStoxConfig.ORCHESTRATOR_BEACON_NAME, beacon());
        bind(LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME, other);
        vm.expectRevert(
            abi.encodeWithSelector(
                OrchestratorConfigBindingMismatch.selector,
                LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME,
                abi.encode(other),
                block.timestamp
            )
        );
        sScript.callAssertPostState();
    }

    function testPostStateRefusesTheBeaconBoundAsAnotherType() external {
        executeProvenBundle();
        vm.warp(block.timestamp + 1);
        bindAs(LibStoxConfig.ORCHESTRATOR_BEACON_NAME, "uint256", beacon());
        vm.expectRevert(
            abi.encodeWithSelector(
                OrchestratorConfigBindingMismatch.selector,
                LibStoxConfig.ORCHESTRATOR_BEACON_NAME,
                abi.encode(beacon()),
                block.timestamp
            )
        );
        sScript.callAssertPostState();
    }

    function testPostStateRefusesTheInitialAdminBoundAsAnotherType() external {
        executeProvenBundle();
        vm.warp(block.timestamp + 1);
        bind(LibStoxConfig.ORCHESTRATOR_BEACON_NAME, beacon());
        bindAs(LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME, "uint256", LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK);
        vm.expectRevert(
            abi.encodeWithSelector(
                OrchestratorConfigBindingMismatch.selector,
                LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME,
                abi.encode(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK),
                block.timestamp
            )
        );
        sScript.callAssertPostState();
    }

    function testPostStateRefusesABeaconBindingFromAnotherBlock() external {
        executeProvenBundle();
        uint256 boundAt = block.timestamp;
        vm.warp(boundAt + 1);
        bind(LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME, LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK);
        vm.expectRevert(
            abi.encodeWithSelector(
                OrchestratorConfigBindingMismatch.selector,
                LibStoxConfig.ORCHESTRATOR_BEACON_NAME,
                abi.encode(beacon()),
                boundAt
            )
        );
        sScript.callAssertPostState();
    }

    function testPostStateRefusesAnInitialAdminBindingFromAnotherBlock() external {
        executeProvenBundle();
        uint256 boundAt = block.timestamp;
        vm.warp(boundAt + 1);
        bind(LibStoxConfig.ORCHESTRATOR_BEACON_NAME, beacon());
        vm.expectRevert(
            abi.encodeWithSelector(
                OrchestratorConfigBindingMismatch.selector,
                LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME,
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

    function testArtifactNamesTheBundleForItsSigners() external {
        BindOrchestratorConfigHarness script = BindOrchestratorConfigHarness(address(sScript));
        script.run();
        assertEq(
            vm.parseJsonString(vm.readFile(script.callArtifactPath()), ".meta.name"),
            "ST0x: bind the orchestrator config"
        );
    }

    function testBundleIsTheBindsThenItsRootLineRecord() external view {
        SafeTx[] memory txs = sScript.callAuthorBundle();
        assertEq(txs.length, 3, "bundle length");
        assertEq(txs[0].to, address(CONFIG_REGISTRY), "beacon bind target");
        assertEq(
            txs[0].data,
            abi.encodeCall(
                IConfigRegistryV5.registerV5,
                (
                    LibRegistryAuthority.ROOT_AUTHORITY,
                    LibStoxConfig.ORCHESTRATOR_BEACON_NAME,
                    "address",
                    abi.encode(beacon()),
                    ""
                )
            ),
            "beacon bind calldata"
        );
        assertEq(txs[1].to, address(CONFIG_REGISTRY), "initial admin bind target");
        assertEq(
            txs[1].data,
            abi.encodeCall(
                IConfigRegistryV5.registerV5,
                (
                    LibRegistryAuthority.ROOT_AUTHORITY,
                    LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME,
                    "address",
                    abi.encode(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK),
                    ""
                )
            ),
            "initial admin bind calldata"
        );
    }
}
