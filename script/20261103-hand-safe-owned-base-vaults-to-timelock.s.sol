// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.30/src/abstract/SafeBundleScript.sol";
import {IOwnerFreezableV1} from "rain-vats-0.2.20/src/interface/IOwnerFreezableV1.sol";
import {IReceiptVaultV3} from "rain-vats-0.2.20/src/interface/IReceiptVaultV3.sol";
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

/// @notice A handover vault is owned by neither the Safe nor the timelock.
/// @param vault The vault.
/// @param owner Its owner.
error HandoverVaultNotOnSafe(address vault, address owner);

/// @notice A checked vault this migration does not hand over is not owned by the timelock.
/// @param vault The vault.
/// @param owner Its owner.
error VaultNotOnTimelock(address vault, address owner);

/// @notice A handover vault's beacon is not the chain's production receipt vault beacon.
/// @param vault The vault.
/// @param expected The production receipt vault beacon.
/// @param actual The vault's beacon.
error HandoverVaultBeaconMismatch(address vault, address expected, address actual);

/// @notice A handover vault's receipt is not the receipt in its token row.
/// @param vault The vault.
/// @param expected The token row's receipt.
/// @param actual The vault's receipt.
error HandoverVaultReceiptMismatch(address vault, address expected, address actual);

/// @notice A handover vault's receipt's beacon is not the chain's production receipt beacon.
/// @param receipt The receipt.
/// @param expected The production receipt beacon.
/// @param actual The receipt's beacon.
error HandoverReceiptBeaconMismatch(address receipt, address expected, address actual);

/// @notice A handover vault is owner-frozen until at least the current block's timestamp.
/// @param vault The vault.
/// @param frozenUntil The end of its owner freeze.
error HandoverVaultOwnerFrozen(address vault, uint256 frozenUntil);

/// @notice The Safe holds an admin role on an authoriser.
/// @param authoriser The authoriser.
/// @param role The admin role.
error SafeHoldsAdminRole(address authoriser, bytes32 role);

/// @notice After the bundle, the Safe's direct `transferOwnership` on a handover
/// vault is not refused with `OwnableUnauthorizedAccount(safe)`.
/// @param vault The vault.
/// @param success Whether the call succeeded.
/// @param reason The call's return data.
error DirectTransferNotRefused(address vault, bool success, bytes reason);

/// @notice After the Safe schedules the proof batch, it is not pending, or is ready inside its delay.
/// @param id The operation id.
error ProofReadyInsideDelay(bytes32 id);

/// @notice After the timelock executes the proof batch, a handover vault is not owned by the Safe.
/// @param vault The vault.
/// @param owner Its owner.
error ProofNotExecuted(address vault, address owner);

/// @notice This script's declaration: the Safe's record, after the orchestrator admin handover.
/// @return The declaration.
function handSafeOwnedBaseVaultsToTimelockDeclaration() pure returns (ScriptDeclaration memory) {
    return ScriptDeclaration({
        id: LibStoxMigrations.HAND_SAFE_OWNED_BASE_VAULTS_TO_TIMELOCK,
        onto: LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK,
        history: false
    });
}

/// @title HandSafeOwnedBaseVaultsToTimelock
/// @notice Per-chain Safe bundle: on Base, `transferOwnership(timelock)` on each of tWMT, tMC, tDIS, tIFX, tSOI and
/// tTPRO the Safe still owns, then this migration's root-line record; elsewhere the record alone.
/// @dev A vault the timelock already owns is skipped, so after Base Safe nonce 706 executes the Base bundle is the
/// record alone.
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

    /// @notice The chain's governance timelock.
    /// @return The timelock.
    function timelock() internal view returns (address) {
        return LibTimelockInvariants.timelockForChainId(block.chainid);
    }

    /// @notice The vaults this migration hands over: tWMT, tMC, tDIS, tIFX, tSOI and tTPRO on Base, none elsewhere.
    /// @return The vaults.
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

    /// @notice The handover vaults the Safe still owns: the ones the bundle transfers.
    /// @return The vaults.
    function vaultsOnSafe() internal view returns (address[] memory) {
        address[] memory all = handoverVaults();
        address[] memory vaults = new address[](all.length);
        uint256 count = 0;
        for (uint256 i = 0; i < all.length; i++) {
            if (Ownable(all[i]).owner() == address(safe())) vaults[count++] = all[i];
        }
        assembly ("memory-safe") {
            mstore(vaults, count)
        }
        return vaults;
    }

    /// @notice The vaults whose owner this migration checks: every production vault on the chain.
    /// @return The tokens.
    function ownershipRows() internal view returns (TokenInstance[] memory) {
        return LibTokenInvariants.productionTokensForChainId(block.chainid);
    }

    /// @notice Whether `vault` is one of the handover vaults.
    /// @param vault The vault.
    /// @return True if it is.
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

        LibStoxMigrations.assertNext(handSafeOwnedBaseVaultsToTimelockDeclaration(), chainSafe);

        // Authoriser grant maps are checked only on Base, the one chain where vaults move.
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
            // Already on the timelock: nothing to move.
            if (owner == chainTimelock) continue;
            if (owner != chainSafe) revert HandoverVaultNotOnSafe(vault, owner);
            // Policy: a vault frozen by its owner, inclusive of the deadline, is not handed over.
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

    /// @notice The beacon read from `proxy`'s registry beacon proxy bytecode.
    /// @param proxy The proxy.
    /// @return The beacon.
    function beaconOf(address proxy) internal view returns (address) {
        (, address beacon) = LibExtrospectRegistryBeaconProxy.isRegistryBeaconProxy(proxy.code);
        return beacon;
    }

    /// @notice Reverts if the Safe holds any of the authoriser's admin roles.
    /// @param authoriser The authoriser.
    /// @param chainSafe The chain's Safe.
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
        txs[vaults.length] = LibStoxMigrations.recordTx(handSafeOwnedBaseVaultsToTimelockDeclaration());
        return txs;
    }

    /// @inheritdoc SafeBundleScript
    function assertPostState() internal view override {
        LibStoxMigrations.assertRecorded(handSafeOwnedBaseVaultsToTimelockDeclaration());
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
        // `run()` writes the artifact from the post-bundle state, not 48h later.
        uint256 postBundle = vm.snapshotState();
        proveGovernance();
        vm.revertToState(postBundle);
    }

    /// @notice Proves the timelock governs the handover vaults: the Safe's direct
    /// `transferOwnership` is refused, and a timelock batch handing them back to
    /// the Safe, scheduled through the Safe, is pending inside its delay and,
    /// after it, executes from an address with no role.
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
