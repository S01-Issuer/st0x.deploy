// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.30/src/abstract/SafeBundleScript.sol";
import {IOwnerFreezableV1} from "rain-vats-0.2.18/src/interface/IOwnerFreezableV1.sol";
import {IReceiptVaultV3} from "rain-vats-0.2.18/src/interface/IReceiptVaultV3.sol";
import {LibExtrospectRegistryBeaconProxy} from "rain-extrospection-0.1.16/src/lib/LibExtrospectRegistryBeaconProxy.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.30/src/lib/LibSafeFork.sol";

import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibAuthoriserInvariants} from "../src/lib/LibAuthoriserInvariants.sol";
import {RoleGrant} from "../src/lib/RoleGrant.sol";
import {LibBeaconInvariants} from "../src/lib/LibBeaconInvariants.sol";
import {LibInvariants} from "../src/lib/LibInvariants.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "../src/lib/LibTokenInvariants.sol";
import {LibUnderlyingNamingRollout} from "../src/lib/LibUnderlyingNamingRollout.sol";

error HandoverVaultNotOnSafe(address vault, address owner);

error VaultNotOnTimelock(address vault, address owner);

error HandoverVaultBeaconMismatch(address vault, address expected, address actual);

error HandoverVaultReceiptMismatch(address vault, address expected, address actual);

error HandoverReceiptBeaconMismatch(address receipt, address expected, address actual);

error HandoverVaultOwnerFrozen(address vault, uint256 frozenUntil);

error SafeHoldsAdminRole(address authoriser, bytes32 role);

error HandoverUnexpectedMigrationLine(bytes32 head);

error HandoverRecordMismatch(uint256 expected, uint256 actual);

error HandoverLineHeadMismatch(bytes32 head);

error DirectTransferNotRefused(address vault, bool success, bytes reason);

error ProofReadyInsideDelay(bytes32 id);

error ProofNotExecuted(address vault, address owner);

function handSafeOwnedBaseVaultsToTimelockDeclaration() pure returns (ScriptDeclaration memory) {
    return ScriptDeclaration({
        id: LibStoxMigrations.HAND_SAFE_OWNED_BASE_VAULTS_TO_TIMELOCK,
        onto: LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK,
        history: false
    });
}

/// @title HandSafeOwnedBaseVaultsToTimelock
/// @notice Per-chain Safe bundle: on Base, `transferOwnership(timelock)` on
/// each of tWMT, tMC, tDIS, tIFX, tSOI and tTPRO the Safe still owns; on every
/// chain, this migration's root-line record. A vault the timelock already owns
/// is skipped. So if the Safe's older queued transfer of the same six (Base
/// nonce 706, authored by `20260729-migrate-governance-to-timelock`) executes
/// before this script is dispatched, the bundle is the record alone. A bundle
/// authored while nonce 706 is still queued reverts on its first transfer if
/// 706 executes first, and must be rejected and dispatched again.
contract HandSafeOwnedBaseVaultsToTimelock is SafeBundleScript, IStoxScript {
    bytes32 internal constant PROOF_SALT = keccak256("st0x.hand-safe-owned-base-vaults-to-timelock.proof");

    /// @inheritdoc IStoxScript
    function declaration(uint256) external pure returns (ScriptDeclaration memory) {
        return handSafeOwnedBaseVaultsToTimelockDeclaration();
    }

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x: hand the Safe-owned Base vaults (tWMT, tMC, tDIS, tIFX, tSOI, tTPRO) to the governance timelock";
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view virtual override returns (string memory) {
        return
            string.concat("out/20261103-hand-safe-owned-base-vaults-to-timelock-", vm.toString(block.chainid), ".json");
    }

    /// @inheritdoc SafeBundleScript
    function safe() internal view override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    function timelock() internal view returns (address) {
        return LibTimelockInvariants.timelockForChainId(block.chainid);
    }

    function handoverVaults() internal view returns (address[] memory) {
        if (block.chainid != LibSafeInvariants.BASE_CHAIN_ID) return new address[](0);
        address[] memory vaults = new address[](6);
        vaults[0] = LibTokenInvariants.WMT_RECEIPT_VAULT;
        vaults[1] = LibTokenInvariants.MC_RECEIPT_VAULT;
        vaults[2] = LibTokenInvariants.DIS_RECEIPT_VAULT;
        vaults[3] = LibTokenInvariants.IFX_RECEIPT_VAULT;
        vaults[4] = LibTokenInvariants.SOI_RECEIPT_VAULT;
        vaults[5] = LibTokenInvariants.TPRO_RECEIPT_VAULT;
        return vaults;
    }

    /// @notice The handover vaults the Safe still owns: the ones the bundle
    /// transfers.
    /// @return vaults The vaults.
    function vaultsOnSafe() internal view returns (address[] memory vaults) {
        address[] memory all = handoverVaults();
        vaults = new address[](all.length);
        uint256 count = 0;
        for (uint256 i = 0; i < all.length; i++) {
            if (Ownable(all[i]).owner() == address(safe())) vaults[count++] = all[i];
        }
        assembly ("memory-safe") {
            mstore(vaults, count)
        }
    }

    /// @notice The vaults whose owner this migration checks: every Base
    /// production vault, and elsewhere the rename's rows.
    /// @return The tokens.
    function ownershipRows() internal view returns (TokenInstance[] memory) {
        if (block.chainid == LibSafeInvariants.BASE_CHAIN_ID) {
            return LibTokenInvariants.productionTokensForChainId(block.chainid);
        }
        return LibUnderlyingNamingRollout.tokens(block.chainid);
    }

    function isHandoverVault(address vault) internal view returns (bool) {
        address[] memory vaults = handoverVaults();
        for (uint256 i = 0; i < vaults.length; i++) {
            if (vaults[i] == vault) return true;
        }
        return false;
    }

    /// @inheritdoc SafeBundleScript
    function preflight() internal view override {
        address chainSafe = address(safe());
        address chainTimelock = timelock();

        bytes32 head = LibStoxMigrations.head();
        if (head != handSafeOwnedBaseVaultsToTimelockDeclaration().onto) revert HandoverUnexpectedMigrationLine(head);

        // The Safe, the timelock and the beacon owners are checked on every
        // chain. The authoriser grant maps matter only where vaults move: off
        // Base the bundle is the record alone, and checking unrelated grant
        // maps there would stall the root line on a routine signer change.
        LibTimelockInvariants.assertTimelockState(
            chainTimelock, LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid)
        );
        LibBeaconInvariants.assertProdBeaconsOwnedByChainTimelock(block.chainid);
        if (block.chainid == LibSafeInvariants.BASE_CHAIN_ID) {
            address authoriser = LibAuthoriserInvariants.authoriserForChainId(block.chainid);
            LibInvariants.assertProductionState(
                LibTokenInvariants.productionTokensForChainId(block.chainid), authoriser
            );
            address euAuthoriser = LibAuthoriserInvariants.euAuthoriserForChainId(block.chainid);
            LibAuthoriserInvariants.assertExpectedEuGrants(
                euAuthoriser, chainTimelock, LibAuthoriserInvariants.GRANTEE_EU_MINTER
            );
            assertSafeHoldsNoAdmin(authoriser, chainSafe);
            assertSafeHoldsNoAdmin(euAuthoriser, chainSafe);
        }

        address[4] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(block.chainid);
        address vaultBeacon = beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX];
        address receiptBeacon = beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX];
        TokenInstance[] memory tokens = ownershipRows();
        for (uint256 i = 0; i < tokens.length; i++) {
            address vault = tokens[i].receiptVault;
            address owner = Ownable(vault).owner();
            if (!isHandoverVault(vault)) {
                if (owner != chainTimelock) revert VaultNotOnTimelock(vault, owner);
                continue;
            }
            // Already handed over, for example by the Safe's older queued
            // transfer of the same vaults: nothing to move.
            if (owner == chainTimelock) continue;
            if (owner != chainSafe) revert HandoverVaultNotOnSafe(vault, owner);
            // Policy, not mechanics: the owner freeze gates transfers, not
            // `transferOwnership`, but a vault frozen by its owner is not
            // handed over mid-freeze. The freeze is inclusive of its
            // deadline, which is never reset, so a passed freeze is fine.
            uint256 frozenUntil = IOwnerFreezableV1(vault).ownerFrozenUntil();
            // forge-lint: disable-next-line(block-timestamp)
            if (frozenUntil >= block.timestamp) revert HandoverVaultOwnerFrozen(vault, frozenUntil);
            address beacon = beaconOf(vault);
            if (beacon != vaultBeacon) revert HandoverVaultBeaconMismatch(vault, vaultBeacon, beacon);
            address receipt = address(IReceiptVaultV3(payable(vault)).receipt());
            if (receipt != tokens[i].receipt) revert HandoverVaultReceiptMismatch(vault, tokens[i].receipt, receipt);
            beacon = beaconOf(receipt);
            if (beacon != receiptBeacon) revert HandoverReceiptBeaconMismatch(receipt, receiptBeacon, beacon);
        }
    }

    function beaconOf(address proxy) internal view returns (address) {
        (, address beacon) = LibExtrospectRegistryBeaconProxy.isRegistryBeaconProxy(proxy.code);
        return beacon;
    }

    function assertSafeHoldsNoAdmin(address authoriser, address chainSafe) internal view {
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants(chainSafe, address(0));
        for (uint256 i = 0; i < LibAuthoriserInvariants.ADMIN_ROLE_COUNT; i++) {
            if (IAccessControl(authoriser).hasRole(grants[i].role, chainSafe)) {
                revert SafeHoldsAdminRole(authoriser, grants[i].role);
            }
        }
    }

    /// @inheritdoc SafeBundleScript
    function authorBundle() internal view override returns (SafeTx[] memory) {
        address[] memory vaults = vaultsOnSafe();
        SafeTx[] memory txs = new SafeTx[](vaults.length + 1);
        for (uint256 i = 0; i < vaults.length; i++) {
            txs[i] = SafeTx({
                to: vaults[i],
                value: 0,
                data: abi.encodeCall(Ownable.transferOwnership, (timelock())),
                operation: Enum.Operation.Call
            });
        }
        (address recordTo, bytes memory recordData) =
            LibStoxMigrations.recordCall(handSafeOwnedBaseVaultsToTimelockDeclaration());
        txs[vaults.length] = SafeTx({to: recordTo, value: 0, data: recordData, operation: Enum.Operation.Call});
        return txs;
    }

    /// @inheritdoc SafeBundleScript
    function assertPostState() internal view override {
        uint256 record = LibStoxMigrations.applied(LibStoxMigrations.HAND_SAFE_OWNED_BASE_VAULTS_TO_TIMELOCK);
        // forge-lint: disable-next-line(block-timestamp)
        if (record != block.timestamp) revert HandoverRecordMismatch(block.timestamp, record);
        bytes32 head = LibStoxMigrations.head();
        if (head != handSafeOwnedBaseVaultsToTimelockDeclaration().id) revert HandoverLineHeadMismatch(head);
        LibTokenInvariants.assertUniformOwnership(ownershipRows(), timelock());
        if (block.chainid == LibSafeInvariants.BASE_CHAIN_ID) {
            LibInvariants.assertProductionState(
                LibTokenInvariants.productionTokensForChainId(block.chainid),
                LibAuthoriserInvariants.authoriserForChainId(block.chainid)
            );
        }
    }

    /// @inheritdoc SafeBundleScript
    function assertReversible() internal override {
        if (handoverVaults().length == 0) return;
        // `run()` writes the artifact from the post-bundle state, not 48h later.
        uint256 postBundle = vm.snapshotState();
        proveGovernance();
        vm.revertToState(postBundle);
    }

    function proveGovernance() internal {
        Safe chainSafe = safe();
        address controllerAddress = timelock();
        address[] memory vaults = handoverVaults();
        bytes memory transfer = abi.encodeCall(Ownable.transferOwnership, (address(chainSafe)));

        uint256[] memory values = new uint256[](vaults.length);
        bytes[] memory payloads = new bytes[](vaults.length);
        for (uint256 i = 0; i < vaults.length; i++) {
            payloads[i] = transfer;
            vm.prank(address(chainSafe));
            // slither-disable-next-line low-level-calls
            (bool ok, bytes memory ret) = vaults[i].call(transfer);
            if (
                ok
                    || keccak256(ret)
                        != keccak256(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, chainSafe))
            ) {
                revert DirectTransferNotRefused(vaults[i], ok, ret);
            }
        }

        TimelockController controller = TimelockController(payable(controllerAddress));
        bytes32 id = controller.hashOperationBatch(vaults, values, payloads, bytes32(0), PROOF_SALT);
        LibSafeFork.simulateNPlus1(
            vm,
            chainSafe,
            controllerAddress,
            abi.encodeCall(
                TimelockController.scheduleBatch,
                (vaults, values, payloads, bytes32(0), PROOF_SALT, LibTimelockInvariants.TIMELOCK_MIN_DELAY)
            )
        );
        if (!controller.isOperationPending(id) || controller.isOperationReady(id)) {
            revert ProofReadyInsideDelay(id);
        }

        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        vm.prank(address(0xdead));
        controller.executeBatch(vaults, values, payloads, bytes32(0), PROOF_SALT);
        for (uint256 i = 0; i < vaults.length; i++) {
            address owner = Ownable(vaults[i]).owner();
            if (owner != address(chainSafe)) revert ProofNotExecuted(vaults[i], owner);
        }
    }
}
