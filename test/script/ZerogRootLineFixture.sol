// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.38/src/interface/IConfigRegistryV5.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.38/src/lib/LibConfigRegistryDeploy.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.38/src/lib/LibRegistryAuthority.sol";
import {SafeTx} from "rain-deploy-0.1.38/src/lib/LibSafeTx.sol";
import {LibRainDeploy} from "rain-deploy-0.1.38/src/lib/LibRainDeploy.sol";
import {LibSafeFork} from "rain-deploy-0.1.38/src/lib/LibSafeFork.sol";
import {
    BYTECODE_HASH as CONFIG_REGISTRY_CODEHASH,
    RUNTIME_CODE as CONFIG_REGISTRY_RUNTIME_CODE
} from "rain-deploy-0.1.38/src/generated/candidate/ConfigRegistry.sol";

import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {
    IST0xOrchestratorBeaconSetDeployerV1
} from "../../src/interface/deprecated/IST0xOrchestratorBeaconSetDeployerV1.sol";
import {LibOrchestratorInvariants} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibProdTokenConfig} from "../../src/lib/LibProdTokenConfig.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {TokenInstance} from "../../src/lib/LibTokenInvariants.sol";
import {LibTestConfigRegistryDelegates} from "../lib/LibTestConfigRegistryDelegates.sol";
import {LibTestRootLine} from "../lib/LibTestRootLine.sol";
import {IRecordScriptHooks} from "../lib/RootLineRecordScriptTest.sol";
import {BindBeaconInitialOwnerHarness} from "./BindBeaconInitialOwnerHarness.sol";
import {BindOrchestratorConfigHarness} from "./BindOrchestratorConfigHarness.sol";
import {CreateZerogTokensHarness} from "./CreateZerogTokensHarness.sol";
import {ExecuteRevokeServiceSignerDepositWithdrawHarness} from "./ExecuteRevokeServiceSignerDepositWithdrawHarness.sol";
import {HandSafeOwnedBaseVaultsToTimelockHarness} from "./HandSafeOwnedBaseVaultsToTimelockHarness.sol";
import {QsepSetFleetAuthoriserHarness} from "./QsepSetFleetAuthoriserHarness.sol";
import {
    ScheduleRevokeServiceSignerDepositWithdrawHarness
} from "./ScheduleRevokeServiceSignerDepositWithdrawHarness.sol";
import {ZerogTokenCreationFixture} from "./ZerogTokenCreationFixture.sol";

/// @title ZerogRootLineFixture
/// @notice 0G as #620 leaves it (`ZerogTokenCreationFixture`'s state, the backfill, every token created and the
/// creation's record), then the root line walked past the token creation. The ConfigRegistry, which landed on 0G after
/// the fixture's block, is etched at its pin with the root's unscoped approval of the Safe, as live 0G has it, and
/// with no name bound. So is the 0.1.30 orchestrator live 0G runs, outside any migration: its beacon-set deployer and
/// the instance claimed for the timelock in one transaction (0G block 50776661), and its beacon handed to the timelock
/// with the other three. A migration with a 0G arm lands through its
/// own 0G bundle, which must be the record alone. A migration whose 0G arm waits on a decision
/// (`ZerogArmPendingDecision`) lands as its record alone, written by the Safe, standing in for that arm.
abstract contract ZerogRootLineFixture is ZerogTokenCreationFixture {
    IConfigRegistryV5 internal constant CONFIG_REGISTRY =
        IConfigRegistryV5(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);

    function zerogSafe() internal pure returns (address) {
        return LibSafeInvariants.safeForChainId(LibSafeInvariants.ZEROG_CHAIN_ID);
    }

    function zerogTimelock() internal pure returns (address) {
        return LibTimelockInvariants.timelockForChainId(LibSafeInvariants.ZEROG_CHAIN_ID);
    }

    /// @notice The migrations after the 0G token creation, in line order.
    function zerogLine() internal pure returns (bytes32[10] memory) {
        return [
            LibStoxMigrations.BIND_BEACON_INITIAL_OWNER,
            LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK,
            LibStoxMigrations.HAND_SAFE_OWNED_BASE_VAULTS_TO_TIMELOCK,
            LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_BEACONS,
            LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_RENAME,
            LibStoxMigrations.EXECUTE_UNDERLYING_NAMING,
            LibStoxMigrations.SCHEDULE_REVOKE_SERVICE_SIGNER,
            LibStoxMigrations.EXECUTE_REVOKE_SERVICE_SIGNER,
            LibStoxMigrations.QSEP_SET_FLEET_AUTHORISER,
            LibStoxMigrations.BIND_ORCHESTRATOR_CONFIG
        ];
    }

    /// @notice Whether `migration`'s 0G arm waits on a decision, so the fixture writes its record as a stand-in.
    function zerogPendingDecision(bytes32 migration) internal pure returns (bool) {
        return migration == LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK
            || migration == LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_BEACONS
            || migration == LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_RENAME
            || migration == LibStoxMigrations.EXECUTE_UNDERLYING_NAMING;
    }

    /// @notice 0G built and backfilled, with every token created except the last batch: the line at the backfill.
    function landZerogTokensBeforeRecord() internal {
        buildZerog();
        vm.etch(address(CONFIG_REGISTRY), CONFIG_REGISTRY_RUNTIME_CODE);
        assertEq(address(CONFIG_REGISTRY).codehash, CONFIG_REGISTRY_CODEHASH, "ConfigRegistry pin");
        LibTestConfigRegistryDelegates.approveUnscoped(vm, zerogSafe());
        buildZerogOrchestrator();
        landZerogBackfill();
        CreateZerogTokensHarness creation = new CreateZerogTokensHarness("zerog-line-batches");
        uint256 rows = LibProdTokenConfig.productionTokenConfigs().length;
        // Each bundle but the last creates 20 rows and leaves the line at the backfill.
        while (creation.callCreatedCount() + 20 < rows) {
            runBundle(IRecordScriptHooks(address(creation)));
        }
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5, "line at the backfill");
    }

    /// @notice The 0.1.30 orchestrator as live 0G has it: over the receipt-vault beacon set its vault-logic lock reads,
    /// its own beacon-set deployer and first `deploy`, administered by the timelock, and its beacon on the timelock.
    function buildZerogOrchestrator() internal {
        // `buildZerog` etches this beacon set as a declared dependency of the 0.1.30 orchestrator, without the two
        // beacons its constructor creates. Live 0G deployed it, beacons included, so deploy it.
        address receiptVaultSet = LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_30;
        vm.etch(receiptVaultSet, "");
        assertEq(
            LibRainDeploy.deployZoltu(
                LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CREATION_CODE_0_1_30
            ),
            receiptVaultSet,
            "0.1.30 receipt-vault beacon set"
        );
        address setDeployer =
            LibRainDeploy.deployZoltu(LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_CREATION_CODE_0_1_30);
        assertEq(setDeployer, LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_30, "orchestrator set deployer");
        assertEq(
            IST0xOrchestratorBeaconSetDeployerV1(setDeployer).deploy(zerogTimelock()),
            LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE,
            "orchestrator instance"
        );
        vm.prank(LibProdDeployV4.BEACON_INITIAL_OWNER);
        Ownable(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_BEACON).transferOwnership(zerogTimelock());
        assertZerogOrchestratorAsLive();
    }

    /// @notice The 0.1.30 orchestrator's state on live 0G: its beacon set, the instance and its role admins as on
    /// every chain, the timelock its `DEFAULT_ADMIN_ROLE`, and the Safe holding neither that nor `EMERGENCY_ROLE`.
    function assertZerogOrchestratorAsLive() internal view {
        LibOrchestratorInvariants.assertBeaconSet();
        LibOrchestratorInvariants.assertInstance();
        IAccessControl orchestrator = IAccessControl(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE);
        assertTrue(orchestrator.hasRole(bytes32(0), zerogTimelock()), "timelock is the orchestrator's admin");
        assertFalse(orchestrator.hasRole(bytes32(0), zerogSafe()), "the Safe is not the orchestrator's admin");
        assertFalse(orchestrator.hasRole(keccak256("EMERGENCY"), zerogSafe()), "the Safe holds no EMERGENCY_ROLE");
    }

    /// @notice The token creation's last bundle: the last rows, then its record.
    function landZerogTokenRecord() internal {
        runBundle(IRecordScriptHooks(address(new CreateZerogTokensHarness("zerog-line-record"))));
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.CREATE_ZEROG_TOKENS, "line at the token creation");
    }

    /// @notice 0G as #620 leaves it: the line at the token creation.
    function landZerogTokens() internal {
        landZerogTokensBeforeRecord();
        landZerogTokenRecord();
    }

    /// @notice The tokens the 0G creation made, in row order: what 0G's token table holds once hydrated.
    function zerogTokens() internal returns (TokenInstance[] memory tokens) {
        CreateZerogTokensHarness creation = new CreateZerogTokensHarness("zerog-line-tokens");
        tokens = new TokenInstance[](LibProdTokenConfig.productionTokenConfigs().length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokens[i] = creation.callToken(i);
        }
    }

    /// @notice The hand-over script on 0G, with the created tokens standing in for 0G's table.
    function zerogHandOver(string memory tag) internal returns (HandSafeOwnedBaseVaultsToTimelockHarness) {
        HandSafeOwnedBaseVaultsToTimelockHarness handOver = new HandSafeOwnedBaseVaultsToTimelockHarness(tag);
        handOver.setOwnershipRows(zerogTokens());
        return handOver;
    }

    /// @notice From a line past the token creation, lands each migration after its head through `target`.
    function landZerogLineThrough(bytes32 target) internal {
        bytes32[10] memory line = zerogLine();
        bytes32 onto = LibStoxMigrations.CREATE_ZEROG_TOKENS;
        for (uint256 i = 0; i < line.length; i++) {
            if (LibStoxMigrations.applied(line[i]) == 0) landZerogMigration(line[i], onto);
            if (line[i] == target) {
                assertEq(LibStoxMigrations.head(), target, "line at the target");
                return;
            }
            onto = line[i];
        }
        revert("target is not on 0G's line after the token creation");
    }

    /// @notice From a line past the token creation, lands each migration after its head up to the one before `next`.
    function landZerogLineBefore(bytes32 next) internal {
        bytes32[10] memory line = zerogLine();
        if (line[0] == next) return;
        for (uint256 i = 1; i < line.length; i++) {
            if (line[i] == next) {
                landZerogLineThrough(line[i - 1]);
                return;
            }
        }
        revert("next is not on 0G's line after the token creation");
    }

    /// @notice Lands `migration` onto `onto` on 0G: its 0G bundle, or its record alone where its arm is pending.
    function landZerogMigration(bytes32 migration, bytes32 onto) internal {
        assertEq(LibStoxMigrations.head(), onto, "line at the onto");
        if (zerogPendingDecision(migration)) {
            LibTestRootLine.write(vm, zerogSafe(), migration, onto);
        } else if (migration == LibStoxMigrations.BIND_BEACON_INITIAL_OWNER) {
            runRecordOnly(IRecordScriptHooks(address(new BindBeaconInitialOwnerHarness("zerog-line"))));
        } else if (migration == LibStoxMigrations.HAND_SAFE_OWNED_BASE_VAULTS_TO_TIMELOCK) {
            runRecordOnly(IRecordScriptHooks(address(zerogHandOver("zerog-line"))));
        } else if (migration == LibStoxMigrations.SCHEDULE_REVOKE_SERVICE_SIGNER) {
            runRecordOnly(
                IRecordScriptHooks(address(new ScheduleRevokeServiceSignerDepositWithdrawHarness("zerog-line")))
            );
        } else if (migration == LibStoxMigrations.EXECUTE_REVOKE_SERVICE_SIGNER) {
            runRecordOnly(
                IRecordScriptHooks(address(new ExecuteRevokeServiceSignerDepositWithdrawHarness("zerog-line")))
            );
        } else if (migration == LibStoxMigrations.QSEP_SET_FLEET_AUTHORISER) {
            runRecordOnly(IRecordScriptHooks(address(new QsepSetFleetAuthoriserHarness("zerog-line"))));
        } else if (migration == LibStoxMigrations.BIND_ORCHESTRATOR_CONFIG) {
            runRecordOnly(IRecordScriptHooks(address(new BindOrchestratorConfigHarness("zerog-line"))));
        } else {
            revert("no 0G landing for the migration");
        }
        assertEq(LibStoxMigrations.head(), migration, "migration heads the line");
    }

    /// @notice Pre-flight, the bundle through the 0G Safe, then the post-state.
    function runBundle(IRecordScriptHooks script) internal {
        script.callPreflight();
        LibSafeFork.executeBundle(vm, Safe(payable(zerogSafe())), script.callAuthorBundle());
        script.callAssertPostState();
    }

    /// @notice `runBundle`, after checking the 0G bundle is the record alone.
    function runRecordOnly(IRecordScriptHooks script) internal {
        assertEq(script.callAuthorBundle().length, 1, "0G bundle is the record alone");
        runBundle(script);
    }

    /// @notice The root binds `name` to `value` on 0G, as it could at any moment.
    function bindAsRoot(bytes32 name, address value) internal {
        vm.prank(LibRegistryAuthority.ROOT_AUTHORITY);
        CONFIG_REGISTRY.registerV5(LibRegistryAuthority.ROOT_AUTHORITY, name, "address", abi.encode(value), "");
    }

    /// @notice Whether `name` is bound under the root authority in the ConfigRegistry.
    function rootBound(bytes32 name) internal view returns (bool) {
        assertEq(address(CONFIG_REGISTRY).codehash, CONFIG_REGISTRY_CODEHASH, "ConfigRegistry present");
        // slither-disable-next-line low-level-calls
        (bool ok,) = address(CONFIG_REGISTRY)
            .staticcall(abi.encodeCall(IConfigRegistryV5.getV5, (LibRegistryAuthority.ROOT_AUTHORITY, name)));
        return ok;
    }
}
