// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {VmSafe} from "forge-std-1.17.0/src/Vm.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.7.0/token/ERC20/extensions/IERC20Metadata.sol";
import {OwnerManager} from "safe-global-safe-smart-account-1.4.1-3/contracts/base/OwnerManager.sol";
import {LibRainDeploy} from "rain-deploy-0.1.38/src/lib/LibRainDeploy.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.38/src/lib/LibMigrationRegistryDeploy.sol";
import {LibSafe} from "rain-deploy-0.1.38/src/lib/LibSafe.sol";
import {LibTimelockController} from "rain-deploy-0.1.38/src/lib/LibTimelockController.sol";

import {
    ExecuteBeaconUpgrade,
    BeaconUpgradeExecutorHoldsRole,
    BeaconUpgradeNotDone,
    BeaconUpgradeNotExecuted,
    BeaconUpgradeNotReady
} from "../../script/20261021-execute-beacon-upgrade.s.sol";
import {
    ScheduleBeaconUpgrade,
    ImplementationNotDeployed,
    BeaconAlreadyUpgraded,
    OperationAlreadyScheduled,
    BeaconUpgradeMovedMetadata,
    scheduleBeaconUpgradeDeclaration
} from "../../script/20261021-schedule-beacon-upgrade.s.sol";
import {ScheduleBeaconUpgradeHarness} from "./ScheduleBeaconUpgradeHarness.sol";
import {ExecuteBeaconUpgradeHarness} from "./ExecuteBeaconUpgradeHarness.sol";
import {BeaconUpgradeFixture} from "./BeaconUpgradeFixture.sol";
import {LibTestPreBackfillFork} from "../lib/LibTestPreBackfillFork.sol";
import {LibTestRootLine} from "../lib/LibTestRootLine.sol";
import {LibTestZerogTokenCreation} from "../lib/LibTestZerogTokenCreation.sol";

import {ICorporateActionsV1} from "../../src/interface/ICorporateActionsV1.sol";
import {ST0xOrchestrator} from "../../src/concrete/ST0xOrchestrator.sol";
import {MintAuthV1, Digest} from "../../src/interface/IST0xOrchestratorV2.sol";
import {IST0xOrchestratorV1} from "../../src/interface/deprecated/IST0xOrchestratorV1.sol";
import {BeaconImplementationMismatch, BeaconOwnerMismatch} from "../../src/lib/LibBeaconInvariants.sol";
import {LibBeaconUpgrade, BeaconUpgradeReleaseNotFrozen} from "../../src/lib/LibBeaconUpgrade.sol";
import {LibOrchestratorInvariants} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibProdTokenConfig, TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "../../src/lib/LibTokenInvariants.sol";

/// @title BeaconUpgradeRolloutTest
/// @notice The beacon upgrade on every deployment network, 0G included. Per
/// network, with the root line at the schedule's onto and the candidate
/// implementations planted, the schedule is authored, verified and executed,
/// the batch is executed from a roleless key after its delay, and the
/// execution record lands. The refusal tests cover each pre-flight check and
/// each executor refusal.
contract BeaconUpgradeRolloutTest is BeaconUpgradeFixture {
    /// @notice Distinguishes each mint-and-burn round's operator and nonce.
    uint256 internal sMintRound;

    /// @notice The beacon batch is exactly: the wrapper beacon upgrade, the
    /// vault beacon upgrade, the facet probe on the chain's first production
    /// vault, then the batch's record.
    function assertBeaconBatchExact(uint256 chainId, string memory network) internal view {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            LibBeaconUpgrade.beaconBatch(chainId);
        assertEq(targets.length, 4, string.concat(network, ": beacon batch length"));
        assertEq(values.length, 4, string.concat(network, ": values length"));
        assertEq(payloads.length, 4, string.concat(network, ": payloads length"));
        assertEq(
            targets[0], LibBeaconUpgrade.wrappedTokenVaultBeacon(chainId), string.concat(network, ": wrapper beacon")
        );
        assertEq(
            payloads[0],
            abi.encodeCall(UpgradeableBeacon.upgradeTo, (LibBeaconUpgrade.WRAPPED_TOKEN_VAULT_IMPLEMENTATION)),
            string.concat(network, ": wrapper upgrade")
        );
        assertEq(targets[1], LibBeaconUpgrade.receiptVaultBeacon(chainId), string.concat(network, ": vault beacon"));
        assertEq(
            payloads[1],
            abi.encodeCall(UpgradeableBeacon.upgradeTo, (LibBeaconUpgrade.RECEIPT_VAULT_IMPLEMENTATION)),
            string.concat(network, ": vault upgrade")
        );
        assertEq(
            targets[2],
            LibTokenInvariants.productionTokensForChainId(chainId)[0].receiptVault,
            string.concat(network, ": probe vault")
        );
        assertEq(
            payloads[2],
            abi.encodeCall(ICorporateActionsV1.completedActionCount, ()),
            string.concat(network, ": probe call")
        );
        assertEq(
            targets[3],
            LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS,
            string.concat(network, ": record target")
        );
        assertEq(
            payloads[3],
            LibTestRootLine.recordCalldata(
                LibStoxMigrations.SCHEDULE_BEACON_UPGRADE, LibStoxMigrations.HAND_SAFE_OWNED_BASE_VAULTS_TO_TIMELOCK
            ),
            string.concat(network, ": record call")
        );
        for (uint256 callIndex = 0; callIndex < values.length; callIndex++) {
            assertEq(values[callIndex], 0, string.concat(network, ": value"));
        }
    }

    /// @dev For the issuers renamed since launch, the name the live `name`
    /// carries and the issuer's current legal name: MicroStrategy Incorporated
    /// became Strategy Inc (August 2025), and Rocket Lab USA, Inc. was replaced
    /// as the listed company by Rocket Lab Corporation (May 2025). Both empty
    /// for every other ticker.
    function renamedIssuer(string memory underlying)
        internal
        pure
        returns (string memory launchName, string memory currentName)
    {
        if (keccak256(bytes(underlying)) == keccak256("MSTR")) {
            return ("MicroStrategy Incorporated", "Strategy Inc");
        }
        if (keccak256(bytes(underlying)) == keccak256("RKLB")) return ("Rocket Lab USA Inc", "Rocket Lab Corporation");
        return ("", "");
    }

    /// @notice Every underlying name is the live name without its " ST0x"
    /// suffix and without surrounding whitespace, except for renamed
    /// issuers, whose live name carries the launch name and whose underlying
    /// name is pinned to the current legal name.
    function testUnderlyingNamesAreTheTrimmedLiveNames() external pure {
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        uint256 renamedSeen = 0;
        for (uint256 rowIndex = 0; rowIndex < configs.length; rowIndex++) {
            TokenConfig memory config = configs[rowIndex];
            bytes memory plain = bytes(config.underlyingName);
            assertGt(plain.length, 0, config.underlying);
            assertTrue(plain[0] != " " && plain[plain.length - 1] != " ", config.underlying);
            (string memory launchName, string memory currentName) = renamedIssuer(config.underlying);
            if (bytes(launchName).length > 0) {
                renamedSeen++;
                assertEq(config.underlyingName, currentName, config.underlying);
            } else {
                launchName = config.underlyingName;
            }
            assertEq(string.concat(launchName, " ST0x"), vm.trim(config.name), config.underlying);
            assertFalse(vm.contains(config.underlyingName, "ST0x"), config.underlying);
        }
        assertEq(renamedSeen, 2, "both renamed issuers are listed");
    }

    /// @notice From the line at the schedule's onto: schedules, executes and
    /// records the beacon upgrade on `network` and checks each step.
    function assertRollout(string memory network) internal {
        uint256 chainId = block.chainid;
        address timelock = LibTimelockInvariants.timelockForChainId(chainId);
        TimelockController controller = TimelockController(payable(timelock));
        bytes32 id = LibBeaconUpgrade.beaconOperationId(timelock, chainId);
        ScheduleBeaconUpgradeHarness schedule = new ScheduleBeaconUpgradeHarness(network);
        ExecuteBeaconUpgradeHarness execution = new ExecuteBeaconUpgradeHarness(network);

        assertBeaconBatchExact(chainId, network);
        assertEq(
            LibStoxMigrations.head(), scheduleBeaconUpgradeDeclaration().onto, string.concat(network, ": line at onto")
        );
        vm.expectPartialRevert(ImplementationNotDeployed.selector);
        schedule.callPreflight();
        vm.expectRevert(abi.encodeWithSelector(BeaconUpgradeNotReady.selector, id, false, false));
        execution.execute();
        vm.expectRevert(abi.encodeWithSelector(BeaconUpgradeNotExecuted.selector, id));
        execution.callPreflight();

        plantImplementations();
        authorVerifyExecute(address(schedule), schedule.callArtifactPath());
        assertEq(
            LibStoxMigrations.head(),
            LibStoxMigrations.HAND_SAFE_OWNED_BASE_VAULTS_TO_TIMELOCK,
            string.concat(network, ": schedule writes no record")
        );
        assertTrue(controller.isOperationPending(id), string.concat(network, ": pending"));
        assertFalse(controller.isOperationReady(id), string.concat(network, ": not ready inside the delay"));
        assertEq(
            controller.getTimestamp(id),
            block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY,
            string.concat(network, ": ready after the delay")
        );
        assertEq(
            IBeacon(LibBeaconUpgrade.receiptVaultBeacon(chainId)).implementation(),
            LibBeaconUpgrade.RECEIPT_VAULT_FROM_IMPLEMENTATION,
            string.concat(network, ": vault beacon unmoved while pending")
        );
        assertEq(
            IBeacon(LibBeaconUpgrade.wrappedTokenVaultBeacon(chainId)).implementation(),
            LibBeaconUpgrade.WRAPPED_TOKEN_VAULT_FROM_IMPLEMENTATION,
            string.concat(network, ": wrapper beacon unmoved while pending")
        );
        vm.expectRevert(abi.encodeWithSelector(BeaconUpgradeNotExecuted.selector, id));
        execution.callPreflight();

        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY - 1);
        vm.expectRevert(abi.encodeWithSelector(BeaconUpgradeNotReady.selector, id, true, false));
        execution.execute();
        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + 1);
        assertFalse(
            IAccessControl(timelock).hasRole(LibTimelockInvariants.TIMELOCK_EXECUTOR_ROLE, address(this)),
            string.concat(network, ": roleless executor")
        );
        execution.execute();

        assertTrue(controller.isOperationDone(id), string.concat(network, ": done"));
        assertEq(
            IBeacon(LibBeaconUpgrade.receiptVaultBeacon(chainId)).implementation(),
            LibBeaconUpgrade.RECEIPT_VAULT_IMPLEMENTATION,
            string.concat(network, ": vault beacon upgraded")
        );
        assertEq(
            IBeacon(LibBeaconUpgrade.wrappedTokenVaultBeacon(chainId)).implementation(),
            LibBeaconUpgrade.WRAPPED_TOKEN_VAULT_IMPLEMENTATION,
            string.concat(network, ": wrapper beacon upgraded")
        );
        assertEq(
            LibStoxMigrations.head(),
            LibStoxMigrations.SCHEDULE_BEACON_UPGRADE,
            string.concat(network, ": batch record")
        );
        assertEq(
            LibStoxMigrations.applied(LibStoxMigrations.SCHEDULE_BEACON_UPGRADE),
            block.timestamp,
            string.concat(network, ": batch record stamped at execution")
        );
        vm.expectRevert(abi.encodeWithSelector(BeaconUpgradeNotReady.selector, id, false, true));
        execution.execute();

        authorVerifyExecute(address(execution), execution.callArtifactPath());
        assertEq(
            LibStoxMigrations.head(),
            LibStoxMigrations.EXECUTE_BEACON_UPGRADE,
            string.concat(network, ": line at the execution")
        );
    }

    function testRolloutOnEveryDeploymentNetwork() external {
        string[] memory networks = LibStoxDeployNetworks.networksBeforeZerog();
        for (uint256 i = 0; i < networks.length; i++) {
            LibTestPreBackfillFork.select(vm, networks[i]);
            advanceRootLineToBeaconSchedule();
            assertRollout(networks[i]);
        }
    }

    /// @notice Live 0G at the token creation's last bundle, with the root
    /// line written up to the schedule's onto as the 0G Safe and the timelock
    /// approved as a root delegate. The orchestrator admin move has no 0G arm,
    /// so no script reaches that onto on 0G.
    function forkZerogAtTheBeaconOnto() internal {
        vm.createSelectFork(LibStoxDeployNetworks.ZEROG, LibTestZerogTokenCreation.LAST_BUNDLE_BLOCK);
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.CREATE_ZEROG_TOKENS, "0G line at the token creation");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        bytes32[5] memory line = [
            LibStoxMigrations.SCHEDULE_ZEROG_ORCHESTRATOR_ROLES,
            LibStoxMigrations.EXECUTE_ZEROG_ORCHESTRATOR_ROLES,
            LibStoxMigrations.BIND_BEACON_INITIAL_OWNER,
            LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK,
            LibStoxMigrations.HAND_SAFE_OWNED_BASE_VAULTS_TO_TIMELOCK
        ];
        bytes32 lineHead = LibStoxMigrations.CREATE_ZEROG_TOKENS;
        for (uint256 i = 0; i < line.length; i++) {
            LibTestRootLine.write(vm, safe, line[i], lineHead);
            lineHead = line[i];
        }
        LibTestRootLine.approve(vm, LibTimelockInvariants.timelockForChainId(block.chainid));
    }

    /// @notice 0G's beacons serve the same from-implementations as every other
    /// chain's, so the same batch schedules, executes and records there.
    function testRolloutOnZerog() external {
        forkZerogAtTheBeaconOnto();
        assertEq(block.chainid, LibSafeInvariants.ZEROG_CHAIN_ID, "0G");
        assertRollout(LibStoxDeployNetworks.ZEROG);
    }

    /// @notice Base with the beacon batch registered and past its delay.
    function batchReadyOnBase() internal {
        LibTestPreBackfillFork.select(vm, LibRainDeploy.BASE);
        advanceRootLineToBeaconSchedule();
        landBeaconSchedule();
        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
    }

    /// @notice On Base, `execute()` calls the registry exactly once, as the
    /// timelock, with the batch's record.
    function testExecuteWritesOnlyTheBatchRecord() external {
        batchReadyOnBase();
        ExecuteBeaconUpgrade executor = new ExecuteBeaconUpgrade();
        bytes memory record = LibTestRootLine.recordCalldata(
            LibStoxMigrations.SCHEDULE_BEACON_UPGRADE, LibStoxMigrations.HAND_SAFE_OWNED_BASE_VAULTS_TO_TIMELOCK
        );
        vm.startStateDiffRecording();
        executor.execute();
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        uint256 registryCalls = 0;
        for (uint256 accessIndex = 0; accessIndex < accesses.length; accessIndex++) {
            VmSafe.AccountAccess memory access = accesses[accessIndex];
            if (access.account != LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS) continue;
            if (
                access.kind != VmSafe.AccountAccessKind.Call && access.kind != VmSafe.AccountAccessKind.DelegateCall
                    && access.kind != VmSafe.AccountAccessKind.CallCode
            ) continue;
            registryCalls++;
            assertTrue(access.kind == VmSafe.AccountAccessKind.Call, "plain call");
            assertEq(access.accessor, LibTimelockInvariants.timelockForChainId(block.chainid), "by the timelock");
            assertEq(access.data, record, "record calldata");
            assertFalse(access.reverted, "landed");
        }
        assertEq(registryCalls, 1, "one registry call");
    }

    /// @notice On Base, the orchestrator mints and burns NVDA before and after
    /// the beacon upgrade, its lock accepts the beacon set on both sides, and
    /// the upgrade moves neither NVDA name nor symbol.
    function testBaseNvdaAndOrchestratorAcrossTheUpgrade() external {
        LibTestPreBackfillFork.select(vm, LibRainDeploy.BASE);
        ST0xOrchestrator orchestrator = ST0xOrchestrator(payable(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE));
        assertTrue(
            IST0xOrchestratorV1(address(orchestrator)).vaultLogicIsExpected(), "lock accepts the beacon set before"
        );
        advanceRootLineToBeaconSchedule();
        landBeaconSchedule();
        mintAndBurn(orchestrator, LibTokenInvariants.NVDA_RECEIPT_VAULT);
        string memory vaultName = IERC20Metadata(LibTokenInvariants.NVDA_RECEIPT_VAULT).name();
        string memory wrapperName = IERC20Metadata(LibTokenInvariants.NVDA_WRAPPED_TOKEN_VAULT).name();

        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        new ExecuteBeaconUpgrade().execute();
        assertEq(
            IBeacon(LibBeaconUpgrade.receiptVaultBeacon(block.chainid)).implementation(),
            LibBeaconUpgrade.RECEIPT_VAULT_IMPLEMENTATION,
            "vault beacon upgraded"
        );

        assertTrue(
            IST0xOrchestratorV1(address(orchestrator)).vaultLogicIsExpected(), "lock accepts the beacon set after"
        );
        assertEq(IERC20Metadata(LibTokenInvariants.NVDA_RECEIPT_VAULT).symbol(), "tNVDA", "vault symbol");
        assertEq(IERC20Metadata(LibTokenInvariants.NVDA_WRAPPED_TOKEN_VAULT).symbol(), "wtNVDA", "wrapper symbol");
        assertEq(IERC20Metadata(LibTokenInvariants.NVDA_RECEIPT_VAULT).name(), vaultName, "vault name");
        assertEq(IERC20Metadata(LibTokenInvariants.NVDA_WRAPPED_TOKEN_VAULT).name(), wrapperName, "wrapper name");
        mintAndBurn(orchestrator, LibTokenInvariants.NVDA_RECEIPT_VAULT);
    }

    /// @notice Mints `token` through the live orchestrator to a fresh EOA that
    /// signs its own authorisation, then burns it back, with roles granted by
    /// the orchestrator's admin, the timelock.
    function mintAndBurn(ST0xOrchestrator orchestrator, address token) internal {
        sMintRound++;
        (address operator, uint256 key) = makeAddrAndKey(string.concat("operator-", vm.toString(sMintRound)));
        address admin = LibTimelockInvariants.timelockForChainId(block.chainid);
        bytes32 mintRole = orchestrator.MINT_ROLE();
        bytes32 burnRole = orchestrator.BURN_ROLE();
        vm.startPrank(admin);
        orchestrator.grantRole(mintRole, operator);
        orchestrator.grantRole(burnRole, operator);
        vm.stopPrank();

        uint256 amount = 1e18;
        uint256 supplyBefore = IERC20(token).totalSupply();
        bytes32 nonce = keccak256(abi.encode(token, sMintRound));
        bytes32 digest = Digest.unwrap(orchestrator.mintAuthDigest(token, operator, amount, nonce));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        vm.prank(operator);
        IST0xOrchestratorV1(address(orchestrator))
            .mint(token, operator, amount, MintAuthV1({nonce: nonce, signature: abi.encodePacked(r, s, v)}), "");
        assertEq(IERC20(token).balanceOf(operator), amount, "minted");

        vm.startPrank(operator);
        IERC20(token).approve(address(orchestrator), amount);
        orchestrator.burn(token, amount, "");
        vm.stopPrank();
        assertEq(IERC20(token).balanceOf(operator), 0, "burned");
        assertEq(IERC20(token).totalSupply(), supplyBefore, "supply restored");
    }

    /// @notice Until the release is frozen, the schedule script refuses in
    /// `run()` and `verify()`, even with the implementations deployed.
    function testSchedulingRefusesUntilTheReleaseIsFrozen() external {
        LibTestPreBackfillFork.select(vm, LibRainDeploy.BASE);
        plantImplementations();
        ScheduleBeaconUpgrade schedule = new ScheduleBeaconUpgrade();
        vm.expectRevert(BeaconUpgradeReleaseNotFrozen.selector);
        schedule.run();
        vm.expectRevert(BeaconUpgradeReleaseNotFrozen.selector);
        schedule.verify("out/never-written.json");
    }

    /// @notice The beacon pre-flight refuses each missing implementation by
    /// name, with the others present.
    function testBeaconPreflightRefusesEachMissingImplementation() external {
        LibTestPreBackfillFork.select(vm, LibRainDeploy.BASE);
        advanceRootLineToBeaconSchedule();
        ScheduleBeaconUpgradeHarness schedule = new ScheduleBeaconUpgradeHarness("refusals");
        address[3] memory implementations = [
            LibBeaconUpgrade.FACET,
            LibBeaconUpgrade.RECEIPT_VAULT_IMPLEMENTATION,
            LibBeaconUpgrade.WRAPPED_TOKEN_VAULT_IMPLEMENTATION
        ];
        bytes32[3] memory codehashes = [
            LibBeaconUpgrade.FACET_CODEHASH,
            LibBeaconUpgrade.RECEIPT_VAULT_CODEHASH,
            LibBeaconUpgrade.WRAPPED_TOKEN_VAULT_CODEHASH
        ];
        plantImplementations();
        schedule.callPreflight();
        for (uint256 missing = 0; missing < implementations.length; missing++) {
            uint256 snapshot = vm.snapshotState();
            vm.etch(implementations[missing], hex"00");
            vm.expectRevert(
                abi.encodeWithSelector(
                    ImplementationNotDeployed.selector,
                    implementations[missing],
                    codehashes[missing],
                    keccak256(hex"00")
                )
            );
            schedule.callPreflight();
            vm.revertToState(snapshot);
        }
    }

    /// @notice The beacon pre-flight refuses once either beacon has moved, and
    /// once the operation is registered.
    function testBeaconPreflightRefusesAnUpgradedBeaconAndARegisteredOperation() external {
        LibTestPreBackfillFork.select(vm, LibRainDeploy.BASE);
        advanceRootLineToBeaconSchedule();
        plantImplementations();
        ScheduleBeaconUpgradeHarness schedule = new ScheduleBeaconUpgradeHarness("refusals");
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        address[2] memory beaconAddresses = [
            LibBeaconUpgrade.receiptVaultBeacon(block.chainid), LibBeaconUpgrade.wrappedTokenVaultBeacon(block.chainid)
        ];
        address[2] memory targets =
            [LibBeaconUpgrade.RECEIPT_VAULT_IMPLEMENTATION, LibBeaconUpgrade.WRAPPED_TOKEN_VAULT_IMPLEMENTATION];
        for (uint256 beaconIndex = 0; beaconIndex < beaconAddresses.length; beaconIndex++) {
            uint256 snapshot = vm.snapshotState();
            vm.prank(timelock);
            UpgradeableBeacon(beaconAddresses[beaconIndex]).upgradeTo(targets[beaconIndex]);
            vm.expectRevert(abi.encodeWithSelector(BeaconAlreadyUpgraded.selector, beaconAddresses[beaconIndex]));
            schedule.callPreflight();
            vm.revertToState(snapshot);
        }

        executePrefix(schedule.callAuthorBundle(), 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                OperationAlreadyScheduled.selector, LibBeaconUpgrade.beaconOperationId(timelock, block.chainid)
            )
        );
        schedule.callPreflight();
    }

    /// @notice The beacon pre-flight refuses a beacon that serves anything but
    /// its pinned from-implementation, so a batch is never scheduled over an
    /// upgrade it does not know about.
    function testBeaconPreflightRefusesAnUnknownFromImplementation() external {
        LibTestPreBackfillFork.select(vm, LibRainDeploy.BASE);
        advanceRootLineToBeaconSchedule();
        plantImplementations();
        ScheduleBeaconUpgradeHarness schedule = new ScheduleBeaconUpgradeHarness("from-impl");
        schedule.callPreflight();
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        address[2] memory beaconAddresses = [
            LibBeaconUpgrade.receiptVaultBeacon(block.chainid), LibBeaconUpgrade.wrappedTokenVaultBeacon(block.chainid)
        ];
        address[2] memory froms = [
            LibBeaconUpgrade.RECEIPT_VAULT_FROM_IMPLEMENTATION, LibBeaconUpgrade.WRAPPED_TOKEN_VAULT_FROM_IMPLEMENTATION
        ];
        // Any deployed implementation that is neither side of the batch.
        address other = LibBeaconUpgrade.FACET;
        for (uint256 beaconIndex = 0; beaconIndex < beaconAddresses.length; beaconIndex++) {
            uint256 snapshot = vm.snapshotState();
            vm.prank(timelock);
            UpgradeableBeacon(beaconAddresses[beaconIndex]).upgradeTo(other);
            vm.expectRevert(
                abi.encodeWithSelector(
                    BeaconImplementationMismatch.selector, beaconAddresses[beaconIndex], froms[beaconIndex], other
                )
            );
            schedule.callPreflight();
            vm.revertToState(snapshot);
        }
    }

    /// @notice The execution proof refuses any of the four metadata values
    /// that moved across the upgrade, on the first and last rows of the token
    /// table and on tQSEP.
    function testBeaconProofRefusesEachBrokenUpgrade() external {
        LibTestPreBackfillFork.select(vm, LibRainDeploy.BASE);
        advanceRootLineToBeaconSchedule();
        landBeaconSchedule();
        ScheduleBeaconUpgradeHarness schedule = new ScheduleBeaconUpgradeHarness("proof-refusals");
        TokenInstance[] memory table = LibTokenInvariants.productionTokensForChainId(block.chainid);
        TokenInstance memory first = table[0];
        TokenInstance memory last = table[table.length - 1];

        uint256 snapshot = vm.snapshotState();
        // A value read before the batch and another after it, for each of the four getters.
        bytes[] memory moved = new bytes[](2);
        moved[0] = abi.encode("Before");
        moved[1] = abi.encode("After");
        address[6] memory targets = [
            first.receiptVault,
            first.wrappedTokenVault,
            last.receiptVault,
            last.wrappedTokenVault,
            LibTokenInvariants.QSEP_RECEIPT_VAULT,
            LibTokenInvariants.QSEP_WRAPPED_TOKEN_VAULT
        ];
        string[6] memory getters = ["name()", "symbol()", "symbol()", "name()", "name()", "symbol()"];
        for (uint256 getterIndex = 0; getterIndex < targets.length; getterIndex++) {
            vm.mockCalls(targets[getterIndex], abi.encodeWithSignature(getters[getterIndex]), moved);
            vm.expectRevert(
                abi.encodeWithSelector(BeaconUpgradeMovedMetadata.selector, targets[getterIndex], "Before", "After")
            );
            schedule.callProveExecution();
            vm.revertToState(snapshot);
            vm.clearMockedCalls();
        }
    }

    /// @notice The beacon pre-flight refuses when the timelock does not own an
    /// in-use beacon, and when the timelock is not in its pinned state.
    function testBeaconPreflightRefusesBeaconOwnerAndTimelockState() external {
        LibTestPreBackfillFork.select(vm, LibRainDeploy.BASE);
        advanceRootLineToBeaconSchedule();
        plantImplementations();
        ScheduleBeaconUpgradeHarness schedule = new ScheduleBeaconUpgradeHarness("owners");
        schedule.callPreflight();
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);

        uint256 snapshot = vm.snapshotState();
        address vaultBeacon = LibBeaconUpgrade.receiptVaultBeacon(block.chainid);
        vm.prank(timelock);
        UpgradeableBeacon(vaultBeacon).transferOwnership(address(0xbeef));
        vm.expectRevert(abi.encodeWithSelector(BeaconOwnerMismatch.selector, vaultBeacon, timelock, address(0xbeef)));
        schedule.callPreflight();
        vm.revertToState(snapshot);

        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        vm.prank(timelock);
        TimelockController(payable(timelock)).revokeRole(LibTimelockInvariants.TIMELOCK_PROPOSER_ROLE, safe);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibTimelockController.TimelockMissingRole.selector,
                timelock,
                LibTimelockInvariants.TIMELOCK_PROPOSER_ROLE,
                safe
            )
        );
        schedule.callPreflight();
    }

    /// @notice The executor refuses a Safe off its pinned policy, with the
    /// batch ready.
    function testExecuteRefusesASafeOffPolicy() external {
        batchReadyOnBase();
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        ExecuteBeaconUpgrade executor = new ExecuteBeaconUpgrade();
        vm.mockCall(safe, abi.encodeCall(OwnerManager.getThreshold, ()), abi.encode(uint256(1)));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibSafe.SafeThresholdMismatch.selector, safe, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD, 1
            )
        );
        executor.execute();
    }

    /// @notice The executor refuses a timelock not in its pinned state, with
    /// the batch ready.
    function testExecuteRefusesATimelockNotInItsPinnedState() external {
        batchReadyOnBase();
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        ExecuteBeaconUpgrade executor = new ExecuteBeaconUpgrade();
        vm.prank(timelock);
        TimelockController(payable(timelock)).revokeRole(LibTimelockInvariants.TIMELOCK_PROPOSER_ROLE, safe);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibTimelockController.TimelockMissingRole.selector,
                timelock,
                LibTimelockInvariants.TIMELOCK_PROPOSER_ROLE,
                safe
            )
        );
        executor.execute();
    }

    /// @notice The executor refuses an execution the timelock does not report
    /// done.
    function testExecuteRefusesAnOperationNotDoneAfterExecution() external {
        batchReadyOnBase();
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        bytes32 id = LibBeaconUpgrade.beaconOperationId(timelock, block.chainid);
        ExecuteBeaconUpgrade executor = new ExecuteBeaconUpgrade();
        vm.mockCall(timelock, abi.encodeCall(TimelockController.isOperationDone, (id)), abi.encode(false));
        vm.expectRevert(abi.encodeWithSelector(BeaconUpgradeNotDone.selector, id));
        executor.execute();
    }

    /// @notice The executor refuses a key that holds the timelock's executor
    /// role, with the batch ready.
    function testExecuteRefusesAKeyHoldingTheExecutorRole() external {
        batchReadyOnBase();
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        ExecuteBeaconUpgrade executor = new ExecuteBeaconUpgrade();
        bytes32 executorRole = LibTimelockInvariants.TIMELOCK_EXECUTOR_ROLE;
        vm.prank(timelock);
        TimelockController(payable(timelock)).grantRole(executorRole, address(this));
        vm.expectRevert(abi.encodeWithSelector(BeaconUpgradeExecutorHoldsRole.selector, timelock, address(this)));
        executor.execute();
    }
}
