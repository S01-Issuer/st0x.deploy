// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {LibSafe} from "rain-deploy-0.1.30/src/lib/LibSafe.sol";
import {LibTimelockController} from "rain-deploy-0.1.30/src/lib/LibTimelockController.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.30/src/lib/LibSafeFork.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.30/src/lib/LibSafeTxBuilderJson.sol";

import {
    DirectTransferNotRefused,
    ProofNotExecuted,
    ProofReadyInsideDelay,
    HandoverReceiptBeaconMismatch,
    HandoverVaultBeaconMismatch,
    HandoverVaultNotOnSafe,
    HandoverVaultOwnerFrozen,
    HandoverVaultReceiptMismatch,
    SafeHoldsAdminRole,
    VaultNotOnTimelock
} from "../../script/20261103-hand-safe-owned-base-vaults-to-timelock.s.sol";
import {BackfillMigrationRegistryV5Harness} from "./BackfillMigrationRegistryV5Harness.sol";
import {HandSafeOwnedBaseVaultsToTimelockHarness} from "./HandSafeOwnedBaseVaultsToTimelockHarness.sol";
import {OrchestratorAdminToTimelockHarness} from "./OrchestratorAdminToTimelockHarness.sol";
import {LibTestPreBackfillFork} from "../lib/LibTestPreBackfillFork.sol";
import {LibTestRegistryBeaconProxy} from "../lib/LibTestRegistryBeaconProxy.sol";
import {LibTestBeaconInitialOwnerBind} from "../lib/LibTestBeaconInitialOwnerBind.sol";
import {ScriptDeclaration} from "../../src/interface/IStoxScript.sol";
import {IOwnerFreezableV1} from "rain-vats-0.2.20/src/interface/IOwnerFreezableV1.sol";
import {IReceiptV3} from "rain-vats-0.2.20/src/interface/IReceiptV3.sol";
import {IReceiptVaultV3} from "rain-vats-0.2.20/src/interface/IReceiptVaultV3.sol";
import {ExpectedGrantMissing, LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {BeaconOwnerMismatch, LibBeaconInvariants} from "../../src/lib/LibBeaconInvariants.sol";
import {RoleGrant} from "../../src/lib/RoleGrant.sol";
import {LibInvariants} from "../../src/lib/LibInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations, UnexpectedMigrationLine} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {
    LibTokenInvariants,
    ReceiptVaultAuthoriserMismatch,
    ReceiptVaultOwnerMismatch,
    TokenInstance
} from "../../src/lib/LibTokenInvariants.sol";
import {LibUnderlyingNamingRollout} from "../../src/lib/LibUnderlyingNamingRollout.sol";

contract HandSafeOwnedBaseVaultsToTimelockTest is Test {
    function forkAtBackfill(string memory network, string memory tag)
        internal
        returns (HandSafeOwnedBaseVaultsToTimelockHarness)
    {
        LibTestPreBackfillFork.select(vm, network);
        BackfillMigrationRegistryV5Harness backfill = new BackfillMigrationRegistryV5Harness(tag);
        Safe safe = Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
        LibSafeFork.executeBundle(vm, safe, backfill.callAuthorBundle());
        LibTestBeaconInitialOwnerBind.execute(vm, address(safe), tag);
        OrchestratorAdminToTimelockHarness adminMove = new OrchestratorAdminToTimelockHarness(tag);
        LibSafeFork.executeBundle(vm, safe, adminMove.callAuthorBundle());
        return new HandSafeOwnedBaseVaultsToTimelockHarness(tag);
    }

    function forkBaseAtBackfill(string memory tag) internal returns (HandSafeOwnedBaseVaultsToTimelockHarness) {
        return forkAtBackfill(LibRainDeploy.BASE, tag);
    }

    function expectedDeclaration() internal pure returns (ScriptDeclaration memory) {
        return ScriptDeclaration({
            id: LibStoxMigrations.HAND_SAFE_OWNED_BASE_VAULTS_TO_TIMELOCK,
            onto: LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK,
            history: false
        });
    }

    function assertRecordTx(SafeTx memory recordTx) internal view {
        (address recordTo, bytes memory recordData) = LibStoxMigrations.recordCall(expectedDeclaration());
        assertEq(recordTx.to, recordTo, "record target");
        assertEq(recordTx.value, 0, "record value");
        assertEq(recordTx.data, recordData, "record calldata");
        assertEq(uint8(recordTx.operation), uint8(Enum.Operation.Call), "record operation");
    }

    function testHandoverBase() external {
        HandSafeOwnedBaseVaultsToTimelockHarness script = forkBaseAtBackfill("bundle");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);

        vm.expectPartialRevert(ReceiptVaultOwnerMismatch.selector);
        this.externalAssertRolloutOwnership(timelock);

        uint256 preRun = vm.snapshotState();
        uint256 runAt = block.timestamp;
        script.run();
        assertEq(block.timestamp, runAt, "the governance proof's warp leaked");
        assertGovernedLikeTheRest();
        vm.revertToState(preRun);

        string memory artifactPath = script.callArtifactPath();
        script.verify(artifactPath);
        (, address artifactSafe, SafeTx[] memory txs) = LibSafeTxBuilderJson.fromJson(vm, vm.readFile(artifactPath));
        assertEq(artifactSafe, safe, "artifact Safe");
        assertEq(txs.length, 7, "six transfers and the record");
        assertEq(vm.parseJsonString(vm.readFile(artifactPath), ".meta.name"), script.callBundleName(), "meta.name");
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), txs);

        assertGovernedLikeTheRest();
        assertEq(LibStoxMigrations.applied(LibStoxMigrations.HAND_SAFE_OWNED_BASE_VAULTS_TO_TIMELOCK), block.timestamp);
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.HAND_SAFE_OWNED_BASE_VAULTS_TO_TIMELOCK);

        vm.prank(safe);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, safe));
        Ownable(LibTokenInvariants.MC_RECEIPT_VAULT).transferOwnership(safe);

        vm.expectRevert(
            abi.encodeWithSelector(
                UnexpectedMigrationLine.selector, LibStoxMigrations.HAND_SAFE_OWNED_BASE_VAULTS_TO_TIMELOCK
            )
        );
        script.callPreflight();
    }

    function externalAssertRolloutOwnership(address timelock) external view {
        LibTokenInvariants.assertUniformOwnership(LibUnderlyingNamingRollout.tokens(block.chainid), timelock);
    }

    function assertGovernedLikeTheRest() internal {
        HandSafeOwnedBaseVaultsToTimelockHarness probe = new HandSafeOwnedBaseVaultsToTimelockHarness("probe");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        address authoriser = LibAuthoriserInvariants.authoriserForChainId(block.chainid);
        TokenInstance[] memory tokens = LibTokenInvariants.productionTokensForChainId(block.chainid);

        LibInvariants.assertProductionState(tokens, authoriser);
        LibAuthoriserInvariants.assertExpectedEuGrants(
            LibAuthoriserInvariants.euAuthoriserForChainId(block.chainid),
            timelock,
            LibAuthoriserInvariants.GRANTEE_EU_MINTER
        );
        LibTokenInvariants.assertUniformOwnership(tokens, timelock);
        LibUnderlyingNamingRollout.assertTickersBound(block.chainid);

        // tMSTR, moved to the timelock by the 2026-07-29 migration.
        TokenInstance memory migrated = tokens[0];
        address referenceBeacon = probe.callBeaconOf(migrated.receiptVault);
        for (uint256 i = 0; i < tokens.length; i++) {
            TokenInstance memory token = tokens[i];
            if (!isHandoverVault(token.receiptVault)) continue;
            assertEq(Ownable(token.receiptVault).owner(), Ownable(migrated.receiptVault).owner(), token.underlying);
            assertEq(probe.callBeaconOf(token.receiptVault), referenceBeacon, token.underlying);
            assertEq(probe.callBeaconOf(token.receipt), probe.callBeaconOf(migrated.receipt), token.underlying);
            assertEq(address(IReceiptVaultV3(payable(token.receiptVault)).receipt()), token.receipt, token.underlying);
            assertEq(IReceiptV3(token.receipt).manager(), token.receiptVault, token.underlying);
            assertEq(
                IOwnerFreezableV1(token.receiptVault).ownerFrozenUntil(),
                IOwnerFreezableV1(migrated.receiptVault).ownerFrozenUntil(),
                token.underlying
            );
            assertEq(IOwnerFreezableV1(token.receiptVault).ownerFreezeAlwaysAllowedFrom(safe), 0, token.underlying);
            assertEq(IOwnerFreezableV1(token.receiptVault).ownerFreezeAlwaysAllowedTo(safe), 0, token.underlying);
        }
    }

    function handoverVaults() internal pure returns (address[6] memory) {
        return [
            LibTokenInvariants.WMT_RECEIPT_VAULT,
            LibTokenInvariants.MC_RECEIPT_VAULT,
            LibTokenInvariants.DIS_RECEIPT_VAULT,
            LibTokenInvariants.IFX_RECEIPT_VAULT,
            LibTokenInvariants.SOI_RECEIPT_VAULT,
            LibTokenInvariants.TPRO_RECEIPT_VAULT
        ];
    }

    function isHandoverVault(address vault) internal pure returns (bool) {
        address[6] memory vaults = handoverVaults();
        for (uint256 i = 0; i < vaults.length; i++) {
            if (vaults[i] == vault) return true;
        }
        return false;
    }

    /// The production artifact path is the one `run-script` uploads (`out/*.json`) and the runbook's `verify` reads.
    function testProductionArtifactPathIsTheUploadedJson() external {
        HandSafeOwnedBaseVaultsToTimelockHarness script = new HandSafeOwnedBaseVaultsToTimelockHarness("path");
        vm.chainId(LibSafeInvariants.BASE_CHAIN_ID);
        assertEq(script.callProductionArtifactPath(), "out/20261103-hand-safe-owned-base-vaults-to-timelock-8453.json");
    }

    function assertRecordAloneOffBase(string memory network) internal {
        HandSafeOwnedBaseVaultsToTimelockHarness script = forkAtBackfill(network, network);
        SafeTx[] memory txs = script.callAuthorBundle();
        assertEq(txs.length, 1, "the record alone");
        assertRecordTx(txs[0]);

        script.callPreflight();
        uint256 snapshot = vm.snapshotState();
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address vault = LibUnderlyingNamingRollout.tokens(block.chainid)[0].receiptVault;
        vm.prank(LibTimelockInvariants.timelockForChainId(block.chainid));
        Ownable(vault).transferOwnership(safe);
        vm.expectRevert(abi.encodeWithSelector(VaultNotOnTimelock.selector, vault, safe));
        script.callPreflight();
        vm.revertToState(snapshot);

        // `run()` authors the artifact; from the pre-run state `verify` holds it, the Safe signs it and the post-state holds.
        uint256 preRun = vm.snapshotState();
        script.run();
        vm.revertToState(preRun);
        string memory artifactPath = script.callArtifactPath();
        script.verify(artifactPath);
        (,, SafeTx[] memory artifactTxs) = LibSafeTxBuilderJson.fromJson(vm, vm.readFile(artifactPath));
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), artifactTxs);
        script.callAssertPostState();
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.HAND_SAFE_OWNED_BASE_VAULTS_TO_TIMELOCK, "record heads");
    }

    function testRecordAloneOffBaseEthereum() external {
        assertRecordAloneOffBase(LibStoxDeployNetworks.ETHEREUM);
    }

    function testRecordAloneOffBaseHyperEvm() external {
        assertRecordAloneOffBase(LibStoxDeployNetworks.HYPEREVM);
    }

    function testRecordAloneOffBaseRobinhood() external {
        assertRecordAloneOffBase(LibStoxDeployNetworks.ROBINHOOD);
    }

    function testRecordAloneOffBaseBsc() external {
        assertRecordAloneOffBase(LibStoxDeployNetworks.BSC);
    }

    /// A vault the timelock already owns is skipped: the bundle moves only the rest, and the record still lands.
    function testPartialHandoverMovesOnlyTheRest() external {
        HandSafeOwnedBaseVaultsToTimelockHarness script = forkBaseAtBackfill("partial");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        vm.prank(safe);
        Ownable(LibTokenInvariants.MC_RECEIPT_VAULT).transferOwnership(timelock);
        script.callPreflight();
        SafeTx[] memory txs = script.callAuthorBundle();
        assertEq(txs.length, 6, "five transfers and the record");
        for (uint256 i = 0; i < txs.length - 1; i++) {
            assertTrue(txs[i].to != LibTokenInvariants.MC_RECEIPT_VAULT, "skips the moved vault");
        }
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), txs);
        script.callAssertPostState();
        assertGovernedLikeTheRest();
    }

    /// After Base Safe nonce 706 moves the six vaults, the bundle is the record alone and the line still advances.
    function testHandoverAfterTheQueuedTransferIsTheRecordAlone() external {
        HandSafeOwnedBaseVaultsToTimelockHarness script = forkBaseAtBackfill("queued");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        address[6] memory vaults = handoverVaults();
        for (uint256 i = 0; i < vaults.length; i++) {
            vm.prank(safe);
            Ownable(vaults[i]).transferOwnership(timelock);
        }
        script.callPreflight();
        SafeTx[] memory txs = script.callAuthorBundle();
        assertEq(txs.length, 1, "the record alone");
        assertRecordTx(txs[0]);
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), txs);
        script.callAssertPostState();
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.HAND_SAFE_OWNED_BASE_VAULTS_TO_TIMELOCK);
    }

    function testRefusesStrangerOwner() external {
        HandSafeOwnedBaseVaultsToTimelockHarness script = forkBaseAtBackfill("stranger");
        address stranger = makeAddr("stranger");
        vm.mockCall(LibTokenInvariants.DIS_RECEIPT_VAULT, abi.encodeWithSignature("owner()"), abi.encode(stranger));
        vm.expectRevert(
            abi.encodeWithSelector(HandoverVaultNotOnSafe.selector, LibTokenInvariants.DIS_RECEIPT_VAULT, stranger)
        );
        script.callPreflight();
    }

    function testRefusesOtherVaultOffTimelock() external {
        HandSafeOwnedBaseVaultsToTimelockHarness script = forkBaseAtBackfill("other-vault");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        address vault = LibTokenInvariants.MSTR_RECEIPT_VAULT;
        vm.prank(timelock);
        Ownable(vault).transferOwnership(safe);
        vm.expectRevert(abi.encodeWithSelector(VaultNotOnTimelock.selector, vault, safe));
        script.callPreflight();
    }

    function testRefusesForeignBeacon() external {
        HandSafeOwnedBaseVaultsToTimelockHarness script = forkBaseAtBackfill("beacon");
        address vaultBeacon =
            LibBeaconInvariants.prodBeaconsForChainId(block.chainid)[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX];
        UpgradeableBeacon foreign = new UpgradeableBeacon(IBeacon(vaultBeacon).implementation(), address(this));
        LibTestRegistryBeaconProxy.etch(vm, LibTokenInvariants.WMT_RECEIPT_VAULT, address(foreign));
        vm.expectRevert(
            abi.encodeWithSelector(
                HandoverVaultBeaconMismatch.selector, LibTokenInvariants.WMT_RECEIPT_VAULT, vaultBeacon, foreign
            )
        );
        script.callPreflight();
    }

    function testRefusesEverySafeAdminRoleOnBothAuthorisers() external {
        HandSafeOwnedBaseVaultsToTimelockHarness script = forkBaseAtBackfill("admin");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        address[2] memory authorisers = [
            LibAuthoriserInvariants.authoriserForChainId(block.chainid),
            LibAuthoriserInvariants.euAuthoriserForChainId(block.chainid)
        ];
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants(safe, timelock);
        for (uint256 authoriserIndex = 0; authoriserIndex < authorisers.length; authoriserIndex++) {
            for (uint256 i = 0; i < LibAuthoriserInvariants.ADMIN_ROLE_COUNT; i++) {
                uint256 clean = vm.snapshotState();
                vm.prank(timelock);
                IAccessControl(authorisers[authoriserIndex]).grantRole(grants[i].role, safe);
                vm.expectRevert(
                    abi.encodeWithSelector(SafeHoldsAdminRole.selector, authorisers[authoriserIndex], grants[i].role)
                );
                script.callPreflight();
                vm.revertToState(clean);
            }
        }
    }

    function testRefusesTimelockDrift() external {
        assertRefusesTimelockDrift(forkBaseAtBackfill("timelock-drift"));
    }

    function testRefusesTimelockDriftOffBase() external {
        assertRefusesTimelockDrift(forkAtBackfill(LibStoxDeployNetworks.ETHEREUM, "off-base-timelock-drift"));
    }

    function assertRefusesTimelockDrift(HandSafeOwnedBaseVaultsToTimelockHarness script) internal {
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        vm.prank(timelock);
        TimelockController(payable(timelock)).updateDelay(1 hours);
        vm.expectRevert(timelockDrift(timelock));
        script.callPreflight();
    }

    function timelockDrift(address timelock) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(
            LibTimelockController.TimelockMinDelayMismatch.selector,
            timelock,
            LibTimelockInvariants.TIMELOCK_MIN_DELAY,
            uint256(1 hours)
        );
    }

    function testRefusesBeaconOffTimelock() external {
        assertRefusesBeaconOffTimelock(forkBaseAtBackfill("beacon-owner"));
    }

    function testRefusesBeaconOffTimelockOffBase() external {
        assertRefusesBeaconOffTimelock(forkAtBackfill(LibStoxDeployNetworks.ETHEREUM, "off-base-beacon-owner"));
    }

    function assertRefusesBeaconOffTimelock(HandSafeOwnedBaseVaultsToTimelockHarness script) internal {
        address beacon = moveOrchestratorBeaconToSafe();
        vm.expectRevert(
            abi.encodeWithSelector(
                BeaconOwnerMismatch.selector,
                beacon,
                LibTimelockInvariants.timelockForChainId(block.chainid),
                LibSafeInvariants.safeForChainId(block.chainid)
            )
        );
        script.callPreflight();
    }

    function moveOrchestratorBeaconToSafe() internal returns (address) {
        address beacon =
            LibBeaconInvariants.prodBeaconsForChainId(block.chainid)[LibBeaconInvariants.ORCHESTRATOR_BEACON_INDEX];
        vm.prank(LibTimelockInvariants.timelockForChainId(block.chainid));
        Ownable(beacon).transferOwnership(LibSafeInvariants.safeForChainId(block.chainid));
        return beacon;
    }

    function testRefusesMissingGrants() external {
        HandSafeOwnedBaseVaultsToTimelockHarness script = forkBaseAtBackfill("grants");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        address authoriser = LibAuthoriserInvariants.authoriserForChainId(block.chainid);
        address euAuthoriser = LibAuthoriserInvariants.euAuthoriserForChainId(block.chainid);
        RoleGrant memory usGrant =
            LibAuthoriserInvariants.expectedGrants(safe, timelock)[LibAuthoriserInvariants.ADMIN_ROLE_COUNT];
        RoleGrant memory euGrant = LibAuthoriserInvariants.expectedEuGrants(
            timelock, LibAuthoriserInvariants.GRANTEE_EU_MINTER, LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C
        )[LibAuthoriserInvariants.ADMIN_ROLE_COUNT];

        uint256 clean = vm.snapshotState();
        vm.prank(timelock);
        IAccessControl(authoriser).revokeRole(usGrant.role, usGrant.grantee);
        vm.expectRevert(
            abi.encodeWithSelector(ExpectedGrantMissing.selector, authoriser, usGrant.role, usGrant.grantee)
        );
        script.callPreflight();
        vm.revertToState(clean);

        vm.prank(timelock);
        IAccessControl(euAuthoriser).revokeRole(euGrant.role, euGrant.grantee);
        vm.expectRevert(
            abi.encodeWithSelector(ExpectedGrantMissing.selector, euAuthoriser, euGrant.role, euGrant.grantee)
        );
        script.callPreflight();
    }

    function testRefusesVaultOnWrongAuthoriser() external {
        HandSafeOwnedBaseVaultsToTimelockHarness script = forkBaseAtBackfill("authoriser");
        address stranger = mockWmtAuthoriser();
        vm.expectRevert(
            abi.encodeWithSelector(
                ReceiptVaultAuthoriserMismatch.selector,
                LibTokenInvariants.WMT_RECEIPT_VAULT,
                LibAuthoriserInvariants.authoriserForChainId(block.chainid),
                stranger
            )
        );
        script.callPreflight();
    }

    function mockWmtAuthoriser() internal returns (address) {
        address stranger = makeAddr("stranger");
        vm.mockCall(LibTokenInvariants.WMT_RECEIPT_VAULT, abi.encodeWithSignature("authorizer()"), abi.encode(stranger));
        return stranger;
    }

    function handedOverFork(string memory tag) internal returns (HandSafeOwnedBaseVaultsToTimelockHarness) {
        HandSafeOwnedBaseVaultsToTimelockHarness script = forkBaseAtBackfill(tag);
        LibSafeFork.executeBundle(
            vm, Safe(payable(LibSafeInvariants.safeForChainId(block.chainid))), script.callAuthorBundle()
        );
        script.callAssertPostState();
        return script;
    }

    function testPostStateRefusesAVaultBackOnTheSafe() external {
        HandSafeOwnedBaseVaultsToTimelockHarness script = handedOverFork("post-owner");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        address[6] memory vaults = handoverVaults();
        for (uint256 i = 0; i < vaults.length; i++) {
            uint256 clean = vm.snapshotState();
            vm.prank(timelock);
            Ownable(vaults[i]).transferOwnership(safe);
            vm.expectRevert(abi.encodeWithSelector(ReceiptVaultOwnerMismatch.selector, vaults[i], timelock, safe));
            script.callAssertPostState();
            vm.revertToState(clean);
        }
    }

    function testPostStateRefusesWrongAuthoriser() external {
        HandSafeOwnedBaseVaultsToTimelockHarness script = handedOverFork("post-authoriser");
        address stranger = mockWmtAuthoriser();
        vm.expectRevert(
            abi.encodeWithSelector(
                ReceiptVaultAuthoriserMismatch.selector,
                LibTokenInvariants.WMT_RECEIPT_VAULT,
                LibAuthoriserInvariants.authoriserForChainId(block.chainid),
                stranger
            )
        );
        script.callAssertPostState();
    }

    function testPostStateRefusesBeaconOffTimelock() external {
        HandSafeOwnedBaseVaultsToTimelockHarness script = handedOverFork("post-beacon");
        address beacon = moveOrchestratorBeaconToSafe();
        vm.expectRevert(
            abi.encodeWithSelector(
                BeaconOwnerMismatch.selector,
                beacon,
                LibTimelockInvariants.timelockForChainId(block.chainid),
                LibSafeInvariants.safeForChainId(block.chainid)
            )
        );
        script.callAssertPostState();
    }

    function testPostStateRefusesTimelockDrift() external {
        HandSafeOwnedBaseVaultsToTimelockHarness script = handedOverFork("post-timelock");
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        vm.prank(timelock);
        TimelockController(payable(timelock)).updateDelay(1 hours);
        vm.expectRevert(timelockDrift(timelock));
        script.callAssertPostState();
    }

    function testPostStateRefusesSafeOffPolicy() external {
        HandSafeOwnedBaseVaultsToTimelockHarness script = handedOverFork("post-safe");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        vm.mockCall(safe, abi.encodeWithSignature("getThreshold()"), abi.encode(uint256(1)));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibSafe.SafeThresholdMismatch.selector,
                safe,
                LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD,
                uint256(1)
            )
        );
        script.callAssertPostState();
    }

    function testProofRefusesDirectTransferThatSucceeds() external {
        HandSafeOwnedBaseVaultsToTimelockHarness script = forkBaseAtBackfill("proof-direct");
        vm.expectRevert(
            abi.encodeWithSelector(
                DirectTransferNotRefused.selector, LibTokenInvariants.WMT_RECEIPT_VAULT, true, bytes("")
            )
        );
        script.callProveGovernance();

        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        bytes memory refusal = abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, safe);
        vm.mockCall(LibTokenInvariants.WMT_RECEIPT_VAULT, abi.encodeCall(Ownable.transferOwnership, (safe)), refusal);
        vm.expectRevert(
            abi.encodeWithSelector(
                DirectTransferNotRefused.selector, LibTokenInvariants.WMT_RECEIPT_VAULT, true, refusal
            )
        );
        script.callProveGovernance();
    }

    function testProofRefusesDirectTransferRevertingForAnotherReason() external {
        HandSafeOwnedBaseVaultsToTimelockHarness script = handedOverFork("proof-reason");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        bytes memory reason = bytes("not an ownership refusal");
        vm.mockCallRevert(
            LibTokenInvariants.WMT_RECEIPT_VAULT, abi.encodeCall(Ownable.transferOwnership, (safe)), reason
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                DirectTransferNotRefused.selector, LibTokenInvariants.WMT_RECEIPT_VAULT, false, reason
            )
        );
        script.callProveGovernance();
    }

    function testProofRefusesOperationReadyInsideDelay() external {
        HandSafeOwnedBaseVaultsToTimelockHarness script = handedOverFork("proof-delay");
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        vm.mockCall(timelock, abi.encodeWithSignature("isOperationReady(bytes32)"), abi.encode(true));
        vm.expectPartialRevert(ProofReadyInsideDelay.selector);
        script.callProveGovernance();
    }

    function testProofRefusesOperationNotPending() external {
        HandSafeOwnedBaseVaultsToTimelockHarness script = handedOverFork("proof-pending");
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        vm.mockCall(timelock, abi.encodeWithSignature("isOperationPending(bytes32)"), abi.encode(false));
        vm.expectPartialRevert(ProofReadyInsideDelay.selector);
        script.callProveGovernance();
    }

    function testProofRefusesATimelockOnlyTheSafeExecutes() external {
        HandSafeOwnedBaseVaultsToTimelockHarness script = handedOverFork("proof-executor");
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        bytes32 executor = TimelockController(payable(timelock)).EXECUTOR_ROLE();
        vm.startPrank(timelock);
        IAccessControl(timelock).revokeRole(executor, address(0));
        IAccessControl(timelock).grantRole(executor, LibSafeInvariants.safeForChainId(block.chainid));
        vm.stopPrank();
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(0xdead), executor)
        );
        script.callProveGovernance();
    }

    function testProofRefusesVaultNotHandedBack() external {
        HandSafeOwnedBaseVaultsToTimelockHarness script = handedOverFork("proof-owner");
        address stranger = makeAddr("stranger");
        // `onlyOwner` reads storage, so the mock reaches only the proof's final read.
        vm.mockCall(LibTokenInvariants.DIS_RECEIPT_VAULT, abi.encodeWithSignature("owner()"), abi.encode(stranger));
        vm.expectRevert(
            abi.encodeWithSelector(ProofNotExecuted.selector, LibTokenInvariants.DIS_RECEIPT_VAULT, stranger)
        );
        script.callProveGovernance();
    }

    function testReversibleRunsTheProofOnASnapshot() external {
        HandSafeOwnedBaseVaultsToTimelockHarness script = handedOverFork("reversible");
        uint256 before = block.timestamp;
        vm.recordLogs();
        script.callAssertReversible();
        bytes32 scheduled = TimelockController.CallScheduled.selector;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool sawSchedule = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == scheduled) sawSchedule = true;
        }
        assertTrue(sawSchedule, "assertReversible did not run the proof");
        assertEq(block.timestamp, before, "the proof's warp leaked");
        assertEq(
            Ownable(LibTokenInvariants.WMT_RECEIPT_VAULT).owner(),
            LibTimelockInvariants.timelockForChainId(block.chainid),
            "the proof's hand-back leaked"
        );
    }

    /// Off Base the governance proof schedules and executes its empty batch through the chain's timelock.
    function testProofRunsOffBase() external {
        HandSafeOwnedBaseVaultsToTimelockHarness script =
            forkAtBackfill(LibStoxDeployNetworks.ETHEREUM, "off-base-proof");
        LibSafeFork.executeBundle(
            vm, Safe(payable(LibSafeInvariants.safeForChainId(block.chainid))), script.callAuthorBundle()
        );
        TimelockController controller =
            TimelockController(payable(LibTimelockInvariants.timelockForChainId(block.chainid)));
        bytes32 id = controller.hashOperationBatch(
            new address[](0),
            new uint256[](0),
            new bytes[](0),
            bytes32(0),
            keccak256("st0x.hand-safe-owned-base-vaults-to-timelock.proof")
        );
        uint256 scheduledAt = block.timestamp;
        script.callProveGovernance();
        assertTrue(controller.isOperationDone(id), "proof executed");
        assertEq(block.timestamp, scheduledAt + LibTimelockInvariants.TIMELOCK_MIN_DELAY, "proof executed at the delay");
    }

    /// Off Base `assertReversible` runs the governance proof: the chain's timelock executes its empty batch, and the
    /// snapshot rolls the proof back.
    function testReversibleRunsTheProofOffBase() external {
        HandSafeOwnedBaseVaultsToTimelockHarness script =
            forkAtBackfill(LibStoxDeployNetworks.ETHEREUM, "off-base-reversible");
        LibSafeFork.executeBundle(
            vm, Safe(payable(LibSafeInvariants.safeForChainId(block.chainid))), script.callAuthorBundle()
        );
        TimelockController controller =
            TimelockController(payable(LibTimelockInvariants.timelockForChainId(block.chainid)));
        bytes32 salt = keccak256("st0x.hand-safe-owned-base-vaults-to-timelock.proof");
        bytes32 id = controller.hashOperationBatch(new address[](0), new uint256[](0), new bytes[](0), bytes32(0), salt);
        uint256 before = block.timestamp;
        vm.expectCall(
            address(controller),
            abi.encodeCall(
                TimelockController.executeBatch, (new address[](0), new uint256[](0), new bytes[](0), bytes32(0), salt)
            )
        );
        script.callAssertReversible();
        assertFalse(controller.isOperation(id), "the proof leaked");
        assertEq(block.timestamp, before, "the proof's warp leaked");
    }

    function testRefusesForeignReceipt() external {
        HandSafeOwnedBaseVaultsToTimelockHarness script = forkBaseAtBackfill("receipt");
        address stranger = makeAddr("stranger");
        vm.mockCall(LibTokenInvariants.DIS_RECEIPT_VAULT, abi.encodeWithSignature("receipt()"), abi.encode(stranger));
        vm.expectRevert(
            abi.encodeWithSelector(
                HandoverVaultReceiptMismatch.selector,
                LibTokenInvariants.DIS_RECEIPT_VAULT,
                LibTokenInvariants.DIS_RECEIPT,
                stranger
            )
        );
        script.callPreflight();
    }

    function testRefusesForeignReceiptBeacon() external {
        HandSafeOwnedBaseVaultsToTimelockHarness script = forkBaseAtBackfill("receipt-beacon");
        address receiptBeacon =
            LibBeaconInvariants.prodBeaconsForChainId(block.chainid)[LibBeaconInvariants.RECEIPT_BEACON_INDEX];
        UpgradeableBeacon foreign = new UpgradeableBeacon(IBeacon(receiptBeacon).implementation(), address(this));
        LibTestRegistryBeaconProxy.etch(vm, LibTokenInvariants.MC_RECEIPT, address(foreign));
        vm.expectRevert(
            abi.encodeWithSelector(
                HandoverReceiptBeaconMismatch.selector, LibTokenInvariants.MC_RECEIPT, receiptBeacon, foreign
            )
        );
        script.callPreflight();
    }

    function testRefusesOwnerFrozen() external {
        HandSafeOwnedBaseVaultsToTimelockHarness script = forkBaseAtBackfill("frozen");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        uint256 until = block.timestamp + 1 days;
        address[6] memory vaults = handoverVaults();
        for (uint256 i = 0; i < vaults.length; i++) {
            uint256 clean = vm.snapshotState();
            vm.prank(safe);
            IOwnerFreezableV1(vaults[i]).ownerFreezeUntil(until);
            vm.expectRevert(abi.encodeWithSelector(HandoverVaultOwnerFrozen.selector, vaults[i], until));
            script.callPreflight();
            vm.revertToState(clean);
        }
    }

    /// The freeze is inclusive of its deadline: a vault frozen until exactly now is refused.
    function testRefusesAFreezeEndingNow() external {
        HandSafeOwnedBaseVaultsToTimelockHarness script = forkBaseAtBackfill("frozen-now");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        uint256 until = vm.getBlockTimestamp() + 1 days;
        vm.prank(safe);
        IOwnerFreezableV1(LibTokenInvariants.WMT_RECEIPT_VAULT).ownerFreezeUntil(until);
        vm.warp(until);
        vm.expectRevert(
            abi.encodeWithSelector(HandoverVaultOwnerFrozen.selector, LibTokenInvariants.WMT_RECEIPT_VAULT, until)
        );
        script.callPreflight();
    }

    /// A freeze that has passed does not block the move: the deadline is never reset, and only an active freeze
    /// refuses.
    function testAcceptsAPassedOwnerFreeze() external {
        HandSafeOwnedBaseVaultsToTimelockHarness script = forkBaseAtBackfill("frozen-passed");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        uint256 until = block.timestamp + 1 days;
        vm.prank(safe);
        IOwnerFreezableV1(LibTokenInvariants.WMT_RECEIPT_VAULT).ownerFreezeUntil(until);
        vm.warp(until + 1);
        script.callPreflight();
    }

    function testVerifyRefusesTamperedArtifact() external {
        HandSafeOwnedBaseVaultsToTimelockHarness script = forkBaseAtBackfill("tamper");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        string memory json =
            LibSafeTxBuilderJson.toJson(vm, safe, block.chainid, "tamper test", script.callAuthorBundle());
        string memory cleanPath = "out/20261103-hand-safe-owned-base-vaults-to-timelock-clean.json";
        vm.writeFile(cleanPath, json);
        script.verify(cleanPath);
        string memory timelockHex = vm.replace(vm.toLowercase(vm.toString(timelock)), "0x", "");
        string memory tampered = vm.replace(json, timelockHex, "000000000000000000000000000000000000dead");
        assertTrue(keccak256(bytes(tampered)) != keccak256(bytes(json)), "tamper did not apply");
        string memory tamperedPath = "out/20261103-hand-safe-owned-base-vaults-to-timelock-tampered.json";
        vm.writeFile(tamperedPath, tampered);
        vm.expectRevert(abi.encodeWithSelector(LibSafeTxBuilderJson.ArtifactMismatch.selector, "data"));
        script.verify(tamperedPath);
    }
}
