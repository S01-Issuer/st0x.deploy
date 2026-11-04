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
    HandoverUnexpectedMigrationLine,
    ProofNotExecuted,
    ProofReadyInsideDelay,
    HandoverReceiptBeaconMismatch,
    HandoverVaultBeaconMismatch,
    HandoverVaultNotOnSafe,
    HandoverVaultOwnerFrozen,
    HandoverVaultReceiptMismatch,
    SafeHoldsAdminRole,
    VaultNotOnTimelock
} from "../../script/20261103-hand-wmt-mc-dis-to-timelock.s.sol";
import {BackfillMigrationRegistryV5Harness} from "./BackfillMigrationRegistryV5Harness.sol";
import {HandWmtMcDisToTimelockHarness} from "./HandWmtMcDisToTimelockHarness.sol";
import {LibTestPreBackfillFork} from "../lib/LibTestPreBackfillFork.sol";
import {LibTestRegistryBeaconProxy} from "../lib/LibTestRegistryBeaconProxy.sol";
import {LibTestRootLine} from "../lib/LibTestRootLine.sol";
import {ScriptDeclaration} from "../../src/interface/IStoxScript.sol";
import {IOwnerFreezableV1} from "rain-vats-0.2.18/src/interface/IOwnerFreezableV1.sol";
import {IReceiptV3} from "rain-vats-0.2.18/src/interface/IReceiptV3.sol";
import {IReceiptVaultV3} from "rain-vats-0.2.18/src/interface/IReceiptVaultV3.sol";
import {ExpectedGrantMissing, LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {BeaconOwnerMismatch, LibBeaconInvariants} from "../../src/lib/LibBeaconInvariants.sol";
import {RoleGrant} from "../../src/lib/RoleGrant.sol";
import {LibInvariants} from "../../src/lib/LibInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {
    LibTokenInvariants,
    ReceiptVaultAuthoriserMismatch,
    ReceiptVaultOwnerMismatch,
    TokenInstance
} from "../../src/lib/LibTokenInvariants.sol";
import {LibUnderlyingNamingRollout} from "../../src/lib/LibUnderlyingNamingRollout.sol";

contract HandWmtMcDisToTimelockTest is Test {
    function forkAtBackfill(string memory network, string memory tag) internal returns (HandWmtMcDisToTimelockHarness) {
        LibTestPreBackfillFork.select(vm, network);
        BackfillMigrationRegistryV5Harness backfill = new BackfillMigrationRegistryV5Harness(tag);
        LibSafeFork.executeBundle(
            vm, Safe(payable(LibSafeInvariants.safeForChainId(block.chainid))), backfill.callAuthorBundle()
        );
        return new HandWmtMcDisToTimelockHarness(tag);
    }

    function forkBaseAtBackfill(string memory tag) internal returns (HandWmtMcDisToTimelockHarness) {
        return forkAtBackfill(LibRainDeploy.BASE, tag);
    }

    function expectedDeclaration() internal pure returns (ScriptDeclaration memory) {
        return ScriptDeclaration({
            id: LibStoxMigrations.HAND_WMT_MC_DIS_TO_TIMELOCK,
            onto: LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5,
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
        HandWmtMcDisToTimelockHarness script = forkBaseAtBackfill("bundle");
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
        assertEq(txs.length, 4, "three transfers and the record");
        assertEq(vm.parseJsonString(vm.readFile(artifactPath), ".meta.name"), script.callBundleName(), "meta.name");
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), txs);

        assertGovernedLikeTheRest();
        assertEq(LibStoxMigrations.applied(LibStoxMigrations.HAND_WMT_MC_DIS_TO_TIMELOCK), block.timestamp);
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.HAND_WMT_MC_DIS_TO_TIMELOCK);

        vm.prank(safe);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, safe));
        Ownable(LibTokenInvariants.MC_RECEIPT_VAULT).transferOwnership(safe);

        vm.expectRevert(
            abi.encodeWithSelector(
                HandoverUnexpectedMigrationLine.selector, LibStoxMigrations.HAND_WMT_MC_DIS_TO_TIMELOCK
            )
        );
        script.callPreflight();
    }

    function externalAssertRolloutOwnership(address timelock) external view {
        LibTokenInvariants.assertUniformOwnership(LibUnderlyingNamingRollout.tokens(block.chainid), timelock);
    }

    function assertGovernedLikeTheRest() internal {
        HandWmtMcDisToTimelockHarness probe = new HandWmtMcDisToTimelockHarness("probe");
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
        LibTokenInvariants.assertUniformOwnership(LibUnderlyingNamingRollout.tokens(block.chainid), timelock);
        LibUnderlyingNamingRollout.assertTickersBound(block.chainid);

        // tMSTR, moved to the timelock by the 2026-07-29 migration.
        TokenInstance memory migrated = tokens[0];
        address referenceBeacon = probe.callBeaconOf(migrated.receiptVault);
        for (uint256 i = 0; i < tokens.length; i++) {
            TokenInstance memory token = tokens[i];
            if (
                token.receiptVault != LibTokenInvariants.WMT_RECEIPT_VAULT
                    && token.receiptVault != LibTokenInvariants.MC_RECEIPT_VAULT
                    && token.receiptVault != LibTokenInvariants.DIS_RECEIPT_VAULT
            ) continue;
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

    function testBaseBundleIsTheThreeTransfersThenTheRecord() external {
        LibTestRootLine.etchRegistry(vm);
        vm.chainId(LibSafeInvariants.BASE_CHAIN_ID);
        HandWmtMcDisToTimelockHarness script = new HandWmtMcDisToTimelockHarness("exact");
        ScriptDeclaration memory declared = script.declaration(block.chainid);
        assertEq(declared.id, LibStoxMigrations.HAND_WMT_MC_DIS_TO_TIMELOCK);
        assertEq(declared.onto, LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5);
        assertFalse(declared.history);

        SafeTx[] memory txs = script.callAuthorBundle();
        address[3] memory vaults = [
            LibTokenInvariants.WMT_RECEIPT_VAULT,
            LibTokenInvariants.MC_RECEIPT_VAULT,
            LibTokenInvariants.DIS_RECEIPT_VAULT
        ];
        assertEq(txs.length, vaults.length + 1);
        for (uint256 i = 0; i < vaults.length; i++) {
            assertEq(txs[i].to, vaults[i]);
            assertEq(txs[i].value, 0);
            assertEq(uint8(txs[i].operation), uint8(Enum.Operation.Call));
            assertEq(
                txs[i].data, abi.encodeCall(Ownable.transferOwnership, (LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK))
            );
        }
        assertRecordTx(txs[vaults.length]);
    }

    function assertRecordAloneOffBase(string memory network) internal {
        HandWmtMcDisToTimelockHarness script = forkAtBackfill(network, network);
        SafeTx[] memory txs = script.callAuthorBundle();
        assertEq(txs.length, 1, "the record alone");
        assertRecordTx(txs[0]);

        script.callPreflight();
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address vault = LibUnderlyingNamingRollout.tokens(block.chainid)[0].receiptVault;
        vm.prank(LibTimelockInvariants.timelockForChainId(block.chainid));
        Ownable(vault).transferOwnership(safe);
        vm.expectRevert(abi.encodeWithSelector(VaultNotOnTimelock.selector, vault, safe));
        script.callPreflight();
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

    function testRefusesPartialHandover() external {
        HandWmtMcDisToTimelockHarness script = forkBaseAtBackfill("partial");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        vm.prank(safe);
        Ownable(LibTokenInvariants.MC_RECEIPT_VAULT).transferOwnership(timelock);
        vm.expectRevert(
            abi.encodeWithSelector(HandoverVaultNotOnSafe.selector, LibTokenInvariants.MC_RECEIPT_VAULT, timelock)
        );
        script.callPreflight();
    }

    function testRefusesStrangerOwner() external {
        HandWmtMcDisToTimelockHarness script = forkBaseAtBackfill("stranger");
        address stranger = makeAddr("stranger");
        vm.mockCall(LibTokenInvariants.DIS_RECEIPT_VAULT, abi.encodeWithSignature("owner()"), abi.encode(stranger));
        vm.expectRevert(
            abi.encodeWithSelector(HandoverVaultNotOnSafe.selector, LibTokenInvariants.DIS_RECEIPT_VAULT, stranger)
        );
        script.callPreflight();
    }

    function testRefusesOtherVaultOffTimelock() external {
        HandWmtMcDisToTimelockHarness script = forkBaseAtBackfill("other-vault");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        address vault = LibTokenInvariants.MSTR_RECEIPT_VAULT;
        vm.prank(timelock);
        Ownable(vault).transferOwnership(safe);
        vm.expectRevert(abi.encodeWithSelector(VaultNotOnTimelock.selector, vault, safe));
        script.callPreflight();
    }

    function testRefusesForeignBeacon() external {
        HandWmtMcDisToTimelockHarness script = forkBaseAtBackfill("beacon");
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
        HandWmtMcDisToTimelockHarness script = forkBaseAtBackfill("admin");
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

    function testRefusesSafeOffPolicy() external {
        HandWmtMcDisToTimelockHarness script = forkBaseAtBackfill("safe-policy");
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
        script.callPreflight();
    }

    function testRefusesTimelockDrift() external {
        HandWmtMcDisToTimelockHarness script = forkBaseAtBackfill("timelock-drift");
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
        HandWmtMcDisToTimelockHarness script = forkBaseAtBackfill("beacon-owner");
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
        HandWmtMcDisToTimelockHarness script = forkBaseAtBackfill("grants");
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
        HandWmtMcDisToTimelockHarness script = forkBaseAtBackfill("authoriser");
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

    function handedOverFork(string memory tag) internal returns (HandWmtMcDisToTimelockHarness) {
        HandWmtMcDisToTimelockHarness script = forkBaseAtBackfill(tag);
        LibSafeFork.executeBundle(
            vm, Safe(payable(LibSafeInvariants.safeForChainId(block.chainid))), script.callAuthorBundle()
        );
        script.callAssertPostState();
        return script;
    }

    function testPostStateRefusesAVaultBackOnTheSafe() external {
        HandWmtMcDisToTimelockHarness script = handedOverFork("post-owner");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        vm.prank(timelock);
        Ownable(LibTokenInvariants.WMT_RECEIPT_VAULT).transferOwnership(safe);
        vm.expectRevert(
            abi.encodeWithSelector(
                ReceiptVaultOwnerMismatch.selector, LibTokenInvariants.WMT_RECEIPT_VAULT, timelock, safe
            )
        );
        script.callAssertPostState();
    }

    function testPostStateRefusesWrongAuthoriser() external {
        HandWmtMcDisToTimelockHarness script = handedOverFork("post-authoriser");
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
        HandWmtMcDisToTimelockHarness script = handedOverFork("post-beacon");
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
        HandWmtMcDisToTimelockHarness script = handedOverFork("post-timelock");
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        vm.prank(timelock);
        TimelockController(payable(timelock)).updateDelay(1 hours);
        vm.expectRevert(timelockDrift(timelock));
        script.callAssertPostState();
    }

    function testPostStateRefusesSafeOffPolicy() external {
        HandWmtMcDisToTimelockHarness script = handedOverFork("post-safe");
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
        HandWmtMcDisToTimelockHarness script = forkBaseAtBackfill("proof-direct");
        vm.expectRevert(
            abi.encodeWithSelector(
                DirectTransferNotRefused.selector, LibTokenInvariants.WMT_RECEIPT_VAULT, true, bytes("")
            )
        );
        script.callProveGovernance();
    }

    function testProofRefusesDirectTransferRevertingForAnotherReason() external {
        HandWmtMcDisToTimelockHarness script = handedOverFork("proof-reason");
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
        HandWmtMcDisToTimelockHarness script = handedOverFork("proof-delay");
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        vm.mockCall(timelock, abi.encodeWithSignature("isOperationReady(bytes32)"), abi.encode(true));
        vm.expectPartialRevert(ProofReadyInsideDelay.selector);
        script.callProveGovernance();
    }

    function testProofRefusesVaultNotHandedBack() external {
        HandWmtMcDisToTimelockHarness script = handedOverFork("proof-owner");
        address stranger = makeAddr("stranger");
        // `onlyOwner` reads storage, so the mock reaches only the proof's final read.
        vm.mockCall(LibTokenInvariants.DIS_RECEIPT_VAULT, abi.encodeWithSignature("owner()"), abi.encode(stranger));
        vm.expectRevert(
            abi.encodeWithSelector(ProofNotExecuted.selector, LibTokenInvariants.DIS_RECEIPT_VAULT, stranger)
        );
        script.callProveGovernance();
    }

    function testReversibleRunsTheProofOnASnapshot() external {
        HandWmtMcDisToTimelockHarness script = handedOverFork("reversible");
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

    function testRefusesForeignReceipt() external {
        HandWmtMcDisToTimelockHarness script = forkBaseAtBackfill("receipt");
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
        HandWmtMcDisToTimelockHarness script = forkBaseAtBackfill("receipt-beacon");
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
        HandWmtMcDisToTimelockHarness script = forkBaseAtBackfill("frozen");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        uint256 until = block.timestamp + 1 days;
        vm.prank(safe);
        IOwnerFreezableV1(LibTokenInvariants.WMT_RECEIPT_VAULT).ownerFreezeUntil(until);
        vm.expectRevert(
            abi.encodeWithSelector(HandoverVaultOwnerFrozen.selector, LibTokenInvariants.WMT_RECEIPT_VAULT, until)
        );
        script.callPreflight();
    }

    function testVerifyRefusesTamperedArtifact() external {
        HandWmtMcDisToTimelockHarness script = forkBaseAtBackfill("tamper");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        string memory json =
            LibSafeTxBuilderJson.toJson(vm, safe, block.chainid, "tamper test", script.callAuthorBundle());
        string memory cleanPath = "out/20261103-hand-wmt-mc-dis-to-timelock-clean.json";
        vm.writeFile(cleanPath, json);
        script.verify(cleanPath);
        string memory timelockHex = vm.replace(vm.toLowercase(vm.toString(timelock)), "0x", "");
        string memory tampered = vm.replace(json, timelockHex, "000000000000000000000000000000000000dead");
        assertTrue(keccak256(bytes(tampered)) != keccak256(bytes(json)), "tamper did not apply");
        string memory tamperedPath = "out/20261103-hand-wmt-mc-dis-to-timelock-tampered.json";
        vm.writeFile(tamperedPath, tampered);
        vm.expectRevert(abi.encodeWithSelector(LibSafeTxBuilderJson.ArtifactMismatch.selector, "data"));
        script.verify(tamperedPath);
    }
}
