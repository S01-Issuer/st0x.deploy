// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
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
    HandoverNotOnBase,
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
import {HandWmtMcDisToTimelockHarness} from "./HandWmtMcDisToTimelockHarness.sol";
import {LibTestRegistryBeaconProxy} from "../lib/LibTestRegistryBeaconProxy.sol";
import {ScriptDeclaration} from "../../src/interface/IStoxScript.sol";
import {IOwnerFreezableV1} from "rain-vats-0.2.18/src/interface/IOwnerFreezableV1.sol";
import {IReceiptV3} from "rain-vats-0.2.18/src/interface/IReceiptV3.sol";
import {IReceiptVaultV3} from "rain-vats-0.2.18/src/interface/IReceiptVaultV3.sol";
import {ExpectedGrantMissing, LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {BeaconOwnerMismatch, LibBeaconInvariants} from "../../src/lib/LibBeaconInvariants.sol";
import {RoleGrant} from "../../src/lib/RoleGrant.sol";
import {LibInvariants} from "../../src/lib/LibInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {
    LibTokenInvariants,
    ReceiptVaultAuthoriserMismatch,
    ReceiptVaultOwnerMismatch,
    TokenInstance
} from "../../src/lib/LibTokenInvariants.sol";
import {LibUnderlyingNamingRollout} from "../../src/lib/LibUnderlyingNamingRollout.sol";

/// @title HandWmtMcDisToTimelockTest
/// @notice The Base handover of tWMT, tMC and tDIS to the governance
/// timelock, against a head fork. While the handover is pending on chain,
/// `run()` authors and proves the bundle, `verify` accepts the artifact, the
/// artifact executed by the owners leaves the three vaults in the same
/// governance state as the other 53, and a re-dispatch refuses. Once it has
/// executed on chain, the live state must be that post-state; the bundle and
/// refusal tests then rebuild the pre-handover state on the fork by handing
/// the three vaults back to the Safe through the timelock. Ownership is
/// checked over the rename rollout's fixed rows, so a vault pinned later
/// while still on the Safe does not fail these tests.
contract HandWmtMcDisToTimelockTest is Test {
    /// @notice Whether the timelock already owns all three vaults on the
    /// active fork.
    /// @param vaults The three vaults.
    /// @param timelock Base's timelock.
    /// @return True when the handover has executed.
    function handedOver(address[] memory vaults, address timelock) internal view returns (bool) {
        for (uint256 i = 0; i < vaults.length; i++) {
            if (Ownable(vaults[i]).owner() != timelock) return false;
        }
        return true;
    }

    /// @notice Forks Base in the pre-handover state: live if the handover is
    /// still pending there, or rebuilt on the fork by the timelock handing
    /// the three vaults back to the Safe.
    /// @param tag The harness's artifact tag.
    /// @return script The harness.
    function forkPreHandover(string memory tag) internal returns (HandWmtMcDisToTimelockHarness script) {
        vm.createSelectFork(LibRainDeploy.BASE);
        script = new HandWmtMcDisToTimelockHarness(tag);
        address safe = LibSafeInvariants.safeForChainId(vm.getChainId());
        address timelock = LibTimelockInvariants.timelockForChainId(vm.getChainId());
        address[] memory vaults = script.callHandoverVaults();
        if (!handedOver(vaults, timelock)) return script;
        console2.log("EXECUTED: rebuilding the pre-handover state on the fork");
        for (uint256 i = 0; i < vaults.length; i++) {
            vm.prank(timelock);
            Ownable(vaults[i]).transferOwnership(safe);
        }
    }

    /// @notice The handover on Base at head: the live post-state if it has
    /// executed; then, from the pre-handover state, the bundle authored,
    /// verified and executed as the Safe UI would, the resulting state, and
    /// the refusal of a re-dispatch.
    function testHandoverBase() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        HandWmtMcDisToTimelockHarness live = new HandWmtMcDisToTimelockHarness("live");
        address timelock = LibTimelockInvariants.timelockForChainId(vm.getChainId());
        if (handedOver(live.callHandoverVaults(), timelock)) {
            console2.log("EXECUTED: asserting the live post-handover state");
            assertGovernedLikeTheRest();
            vm.expectRevert(
                abi.encodeWithSelector(HandoverVaultNotOnSafe.selector, LibTokenInvariants.WMT_RECEIPT_VAULT, timelock)
            );
            live.callPreflight();
        } else {
            console2.log("PENDING: the Safe still owns tWMT, tMC and tDIS on Base");
        }

        HandWmtMcDisToTimelockHarness script = forkPreHandover("bundle");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);

        // Before the handover, the three vaults are what keeps the rename
        // rollout's ownership leg from passing on Base.
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
        assertEq(txs.length, 3, "three transfers");
        assertEq(vm.parseJsonString(vm.readFile(artifactPath), ".meta.name"), script.callBundleName(), "meta.name");
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), txs);

        assertGovernedLikeTheRest();

        // The Safe can no longer act as owner directly.
        vm.prank(safe);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, safe));
        Ownable(LibTokenInvariants.MC_RECEIPT_VAULT).transferOwnership(safe);

        vm.expectRevert(
            abi.encodeWithSelector(HandoverVaultNotOnSafe.selector, LibTokenInvariants.WMT_RECEIPT_VAULT, timelock)
        );
        script.callPreflight();
    }

    /// @notice External shim so `vm.expectRevert` can observe the rollout's
    /// ownership leg reverting.
    /// @param timelock Base's timelock.
    function externalAssertRolloutOwnership(address timelock) external view {
        LibTokenInvariants.assertUniformOwnership(LibUnderlyingNamingRollout.tokens(block.chainid), timelock);
    }

    /// @notice The three vaults are in the governance state of the other 53:
    /// the production invariants and the rename rollout's ownership and
    /// ticker legs hold for the whole table, and each of the three matches a
    /// vault the 2026-07-29 migration moved on owner, beacon, receipt
    /// binding and owner-freeze state.
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

        // The rename rollout's pre-flight legs over vault state.
        LibTokenInvariants.assertUniformOwnership(LibUnderlyingNamingRollout.tokens(block.chainid), timelock);
        LibUnderlyingNamingRollout.assertTickersBound(block.chainid);

        // tMSTR, row 0, moved by the 2026-07-29 migration.
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

    /// @notice The bundle is exactly `transferOwnership(timelock)` on tWMT,
    /// tMC and tDIS, and the script writes no migration record.
    function testBundleIsExactlyThreeTransfers() external {
        HandWmtMcDisToTimelockHarness script = new HandWmtMcDisToTimelockHarness("exact");
        SafeTx[] memory txs = script.callAuthorBundle();
        address[3] memory vaults = [
            LibTokenInvariants.WMT_RECEIPT_VAULT,
            LibTokenInvariants.MC_RECEIPT_VAULT,
            LibTokenInvariants.DIS_RECEIPT_VAULT
        ];
        assertEq(txs.length, vaults.length);
        for (uint256 i = 0; i < vaults.length; i++) {
            assertEq(txs[i].to, vaults[i]);
            assertEq(txs[i].value, 0);
            assertEq(uint8(txs[i].operation), uint8(Enum.Operation.Call));
            assertEq(
                txs[i].data, abi.encodeCall(Ownable.transferOwnership, (LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK))
            );
        }
        ScriptDeclaration memory declared = script.declaration();
        assertFalse(declared.migration, "not a recorded migration");
    }

    /// @notice Off Base the script refuses before it reads any state.
    function testRefusesOffBase() external {
        HandWmtMcDisToTimelockHarness script = new HandWmtMcDisToTimelockHarness("off-base");
        vm.chainId(LibSafeInvariants.ETHEREUM_CHAIN_ID);
        vm.expectRevert(abi.encodeWithSelector(HandoverNotOnBase.selector, LibSafeInvariants.ETHEREUM_CHAIN_ID));
        script.callPreflight();
    }

    /// @notice A partial handover is drift: one of the three already on the
    /// timelock refuses.
    function testRefusesPartialHandover() external {
        HandWmtMcDisToTimelockHarness script = forkPreHandover("partial");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        vm.prank(safe);
        Ownable(LibTokenInvariants.MC_RECEIPT_VAULT).transferOwnership(timelock);
        vm.expectRevert(
            abi.encodeWithSelector(HandoverVaultNotOnSafe.selector, LibTokenInvariants.MC_RECEIPT_VAULT, timelock)
        );
        script.callPreflight();
    }

    /// @notice One of the three on an unknown owner refuses.
    function testRefusesStrangerOwner() external {
        HandWmtMcDisToTimelockHarness script = forkPreHandover("stranger");
        address stranger = makeAddr("stranger");
        vm.mockCall(LibTokenInvariants.DIS_RECEIPT_VAULT, abi.encodeWithSignature("owner()"), abi.encode(stranger));
        vm.expectRevert(
            abi.encodeWithSelector(HandoverVaultNotOnSafe.selector, LibTokenInvariants.DIS_RECEIPT_VAULT, stranger)
        );
        script.callPreflight();
    }

    /// @notice Any other vault off the timelock refuses: the bundle fixes
    /// exactly three vaults.
    function testRefusesOtherVaultOffTimelock() external {
        HandWmtMcDisToTimelockHarness script = forkPreHandover("other-vault");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        address vault = LibTokenInvariants.MSTR_RECEIPT_VAULT;
        vm.prank(timelock);
        Ownable(vault).transferOwnership(safe);
        vm.expectRevert(abi.encodeWithSelector(VaultNotOnTimelock.selector, vault, safe));
        script.callPreflight();
    }

    /// @notice One of the three behind a beacon other than the in-use,
    /// timelock-owned one refuses, even when that beacon serves the same
    /// implementation.
    function testRefusesForeignBeacon() external {
        HandWmtMcDisToTimelockHarness script = forkPreHandover("beacon");
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

    /// @notice The Safe holding any of the seven `_ADMIN` roles on either
    /// authoriser refuses.
    function testRefusesEverySafeAdminRoleOnBothAuthorisers() external {
        HandWmtMcDisToTimelockHarness script = forkPreHandover("admin");
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

    /// @notice A Safe off the token-owner policy refuses.
    function testRefusesSafeOffPolicy() external {
        HandWmtMcDisToTimelockHarness script = forkPreHandover("safe-policy");
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

    /// @notice A timelock whose delay drifted refuses.
    function testRefusesTimelockDrift() external {
        HandWmtMcDisToTimelockHarness script = forkPreHandover("timelock-drift");
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        vm.prank(timelock);
        TimelockController(payable(timelock)).updateDelay(1 hours);
        vm.expectRevert(timelockDrift(timelock));
        script.callPreflight();
    }

    /// @notice The revert `assertTimelockState` gives for a 1h delay.
    /// @param timelock Base's timelock.
    /// @return The revert data.
    function timelockDrift(address timelock) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(
            LibTimelockController.TimelockMinDelayMismatch.selector,
            timelock,
            LibTimelockInvariants.TIMELOCK_MIN_DELAY,
            uint256(1 hours)
        );
    }

    /// @notice A beacon off the timelock refuses.
    function testRefusesBeaconOffTimelock() external {
        HandWmtMcDisToTimelockHarness script = forkPreHandover("beacon-owner");
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

    /// @notice Hands the orchestrator beacon from the timelock to the Safe.
    /// @return beacon The beacon.
    function moveOrchestratorBeaconToSafe() internal returns (address beacon) {
        beacon = LibBeaconInvariants.prodBeaconsForChainId(block.chainid)[LibBeaconInvariants.ORCHESTRATOR_BEACON_INDEX];
        vm.prank(LibTimelockInvariants.timelockForChainId(block.chainid));
        Ownable(beacon).transferOwnership(LibSafeInvariants.safeForChainId(block.chainid));
    }

    /// @notice An operational grant missing on either authoriser refuses.
    function testRefusesMissingGrants() external {
        HandWmtMcDisToTimelockHarness script = forkPreHandover("grants");
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

    /// @notice A vault on the wrong authoriser refuses.
    function testRefusesVaultOnWrongAuthoriser() external {
        HandWmtMcDisToTimelockHarness script = forkPreHandover("authoriser");
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

    /// @notice Mocks tWMT's `authorizer()` to a stranger.
    /// @return stranger The stranger.
    function mockWmtAuthoriser() internal returns (address stranger) {
        stranger = makeAddr("stranger");
        vm.mockCall(LibTokenInvariants.WMT_RECEIPT_VAULT, abi.encodeWithSignature("authorizer()"), abi.encode(stranger));
    }

    /// @notice Forks Base right after the bundle executed through the Safe,
    /// with the post-state holding.
    /// @param tag The harness's artifact tag.
    /// @return script The harness.
    function handedOverFork(string memory tag) internal returns (HandWmtMcDisToTimelockHarness script) {
        script = forkPreHandover(tag);
        LibSafeFork.executeBundle(
            vm, Safe(payable(LibSafeInvariants.safeForChainId(block.chainid))), script.callAuthorBundle()
        );
        script.callAssertPostState();
    }

    /// @notice The post-state refuses a vault left on the Safe.
    function testPostStateRefusesVaultLeftOnSafe() external {
        HandWmtMcDisToTimelockHarness script = forkPreHandover("post-owner");
        vm.expectRevert(
            abi.encodeWithSelector(
                ReceiptVaultOwnerMismatch.selector,
                LibTokenInvariants.WMT_RECEIPT_VAULT,
                LibTimelockInvariants.timelockForChainId(block.chainid),
                LibSafeInvariants.safeForChainId(block.chainid)
            )
        );
        script.callAssertPostState();
    }

    /// @notice The post-state refuses a vault on the wrong authoriser.
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

    /// @notice The post-state refuses a beacon off the timelock.
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

    /// @notice The post-state refuses timelock drift.
    function testPostStateRefusesTimelockDrift() external {
        HandWmtMcDisToTimelockHarness script = handedOverFork("post-timelock");
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        vm.prank(timelock);
        TimelockController(payable(timelock)).updateDelay(1 hours);
        vm.expectRevert(timelockDrift(timelock));
        script.callAssertPostState();
    }

    /// @notice The post-state refuses a Safe off the token-owner policy.
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

    /// @notice Before the handover the Safe still owns the vaults, so its
    /// direct transfer goes through and the proof refuses.
    function testProofRefusesDirectTransferThatSucceeds() external {
        HandWmtMcDisToTimelockHarness script = forkPreHandover("proof-direct");
        vm.expectRevert(
            abi.encodeWithSelector(
                DirectTransferNotRefused.selector, LibTokenInvariants.WMT_RECEIPT_VAULT, true, bytes("")
            )
        );
        script.callProveGovernance();
    }

    /// @notice The proof refuses a direct transfer that reverts for a reason
    /// other than lacking ownership.
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

    /// @notice The proof refuses an operation that is ready inside the delay.
    function testProofRefusesOperationReadyInsideDelay() external {
        HandWmtMcDisToTimelockHarness script = handedOverFork("proof-delay");
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        vm.mockCall(timelock, abi.encodeWithSignature("isOperationReady(bytes32)"), abi.encode(true));
        vm.expectPartialRevert(ProofReadyInsideDelay.selector);
        script.callProveGovernance();
    }

    /// @notice The proof refuses a vault the operation did not hand back.
    function testProofRefusesVaultNotHandedBack() external {
        HandWmtMcDisToTimelockHarness script = handedOverFork("proof-owner");
        address stranger = makeAddr("stranger");
        // `onlyOwner` reads the owner from storage, so the mock reaches only
        // the proof's final external read.
        vm.mockCall(LibTokenInvariants.DIS_RECEIPT_VAULT, abi.encodeWithSignature("owner()"), abi.encode(stranger));
        vm.expectRevert(
            abi.encodeWithSelector(ProofNotExecuted.selector, LibTokenInvariants.DIS_RECEIPT_VAULT, stranger)
        );
        script.callProveGovernance();
    }

    /// @notice `assertReversible` runs the proof, then restores the state and
    /// the clock.
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

    /// @notice The production artifact path and the bundle name signers see
    /// are pinned.
    function testArtifactPathAndBundleNameArePinned() external {
        HandWmtMcDisToTimelockHarness script = new HandWmtMcDisToTimelockHarness("names");
        assertEq(
            script.callScriptArtifactPath(),
            string.concat("out/20261103-hand-wmt-mc-dis-to-timelock-", vm.toString(block.chainid), ".json")
        );
        assertEq(
            script.callBundleName(), "ST0x Base: hand tWMT, tMC and tDIS vault ownership to the governance timelock"
        );
    }

    /// @notice One of the three reporting a receipt other than the table's
    /// refuses.
    function testRefusesForeignReceipt() external {
        HandWmtMcDisToTimelockHarness script = forkPreHandover("receipt");
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

    /// @notice A receipt of the three behind a beacon other than the in-use,
    /// timelock-owned receipt beacon refuses.
    function testRefusesForeignReceiptBeacon() external {
        HandWmtMcDisToTimelockHarness script = forkPreHandover("receipt-beacon");
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

    /// @notice One of the three under an owner freeze refuses.
    function testRefusesOwnerFrozen() external {
        HandWmtMcDisToTimelockHarness script = forkPreHandover("frozen");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        uint256 until = block.timestamp + 1 days;
        vm.prank(safe);
        IOwnerFreezableV1(LibTokenInvariants.WMT_RECEIPT_VAULT).ownerFreezeUntil(until);
        vm.expectRevert(
            abi.encodeWithSelector(HandoverVaultOwnerFrozen.selector, LibTokenInvariants.WMT_RECEIPT_VAULT, until)
        );
        script.callPreflight();
    }

    /// @notice `verify` refuses an artifact that hands the vaults to an
    /// address other than the timelock.
    function testVerifyRefusesTamperedArtifact() external {
        HandWmtMcDisToTimelockHarness script = forkPreHandover("tamper");
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        string memory json =
            LibSafeTxBuilderJson.toJson(vm, safe, block.chainid, "tamper test", script.callAuthorBundle());
        string memory cleanPath = "out/20261103-hand-wmt-mc-dis-to-timelock-clean.json";
        vm.writeFile(cleanPath, json);
        // Control: the untampered artifact verifies, so the refusal below is
        // the tamper's doing.
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
