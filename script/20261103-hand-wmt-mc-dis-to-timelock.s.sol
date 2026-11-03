// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {console2} from "forge-std-1.17.0/src/console2.sol";
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

/// @notice The script runs only on Base: the three vaults it moves are Base
/// vaults, and on every other chain every vault is already timelock-owned.
/// @param chainId The active chain id.
error HandoverNotOnBase(uint256 chainId);

/// @notice One of the three vaults this script moves is not owned by the
/// Safe. Either the handover has executed, or the vault has drifted to an
/// owner nobody expects. The bundle is atomic, so a partial state is drift
/// too.
/// @param vault The vault.
/// @param owner Its live owner.
error HandoverVaultNotOnSafe(address vault, address owner);

/// @notice A vault of the rename rollout's rows, outside the three, is not
/// owned by the timelock. The script hands over exactly three vaults, so any
/// other of those rows off the timelock is drift this bundle does not fix.
/// @param vault The vault.
/// @param owner Its live owner.
error VaultNotOnTimelock(address vault, address owner);

/// @notice One of the three vaults does not proxy the chain's in-use
/// receipt-vault beacon, which the timelock owns. Its `transferOwnership`
/// would then not be the audited implementation's.
/// @param vault The vault.
/// @param expected The in-use receipt-vault beacon.
/// @param actual The beacon the vault's runtime bytecode dispatches through,
/// or zero when it is not a registry beacon proxy.
error HandoverVaultBeaconMismatch(address vault, address expected, address actual);

/// @notice One of the three vaults is not wired to the receipt in the token
/// table.
/// @param vault The vault.
/// @param expected The receipt in the token table.
/// @param actual The receipt the vault reports.
error HandoverVaultReceiptMismatch(address vault, address expected, address actual);

/// @notice One of the three vaults' receipts does not proxy the chain's
/// in-use receipt beacon, which the timelock owns.
/// @param receipt The receipt.
/// @param expected The in-use receipt beacon.
/// @param actual The beacon the receipt's runtime bytecode dispatches
/// through, or zero when it is not a registry beacon proxy.
error HandoverReceiptBeaconMismatch(address receipt, address expected, address actual);

/// @notice One of the three vaults carries an owner freeze. The freeze is
/// owner state, so the bundle would hand it to the timelock unseen; no
/// production vault has one.
/// @param vault The vault.
/// @param frozenUntil Its `ownerFrozenUntil()`.
error HandoverVaultOwnerFrozen(address vault, uint256 frozenUntil);

/// @notice The Safe still holds an `_ADMIN` role on one of the chain's two
/// authorisers. Every `_ADMIN` must sit on the timelock alone.
/// @param authoriser The authoriser.
/// @param role The role.
error SafeHoldsAdminRole(address authoriser, bytes32 role);

/// @notice After the move, the Safe's direct `transferOwnership` did not
/// revert for lacking ownership.
/// @param vault The vault.
/// @param success Whether the call went through.
/// @param reason The revert data, when it did not.
error DirectTransferNotRefused(address vault, bool success, bytes reason);

/// @notice The proof operation is not pending, or is already ready, inside
/// the delay.
/// @param id The timelock operation.
error ProofReadyInsideDelay(bytes32 id);

/// @notice The proof operation did not execute after the delay, or did not
/// hand the vault back to the Safe.
/// @param vault The vault.
/// @param owner Its owner after the operation.
error ProofNotExecuted(address vault, address owner);

/// @title HandWmtMcDisToTimelock
/// @notice Authors the Base Safe Tx Builder bundle that hands tWMT, tMC and
/// tDIS from the token-owner Safe to the governance timelock. Three calls,
/// one atomic MultiSend: `transferOwnership(timelock)` on each vault.
///
/// The 2026-07-29 governance migration moved every Base vault that existed
/// then. These three were deployed afterwards and handed to the Safe, so
/// their `owner()` is the only governance surface left on the Safe: on Base
/// they share the timelock-owned beacons and authorisers with the other 53
/// vaults (tMC uses the EU assets authoriser, which the timelock also
/// administers), their receipts are managed by the vaults, the wrappers have
/// no owner, and no owner freeze has ever been set on them. The vault is
/// single-step `OwnableUpgradeable`, so the transfer completes in the bundle
/// and the timelock does not have to accept it.
///
/// After execution every `onlyOwner` surface of the three (`setAuthorizer`,
/// `setUnderlying`, owner freezes, `transferOwnership`) is delayed by 48h
/// like the rest, and the underlying-naming rename batch, whose pre-flight
/// requires every vault to be timelock-owned, can be scheduled on Base.
///
/// Not recorded in the migration registry. It completes the 2026-07-29
/// migration on Base only; that migration is declared as history in
/// `migrations.json`, and its record lands with the pending orchestrator
/// EMERGENCY bundle. A record in this repo's namespace would join the Safe's
/// single line after the four Safe migrations still pending there
/// (`LibScriptDeclarations` forbids a forked line), so it could not execute
/// before them. The pre-flight makes the script one-shot instead: it refuses
/// unless, over the rename rollout's rows, the Safe owns exactly these three
/// vaults, and a replayed bundle
/// reverts because the Safe no longer owns them.
///
/// **Before signing: cancel any timelock operation already scheduled against
/// the three vaults.** `schedule` does not run the inner call, so an
/// operation on a vault the timelock does not own yet can sit pending or
/// ready, and once the timelock owns the vault anyone can execute it with no
/// further delay. Read them on the rain-org-health dashboard's Role changes
/// tab, https://rainlanguage.github.io/rain-org-health/deployments.html, or
/// from the RBAC subgraph (`st0x-rbac-base`, version `prod`):
/// `{ timelockOperations(where: {timelock: "<timelock>", status: PENDING, targets_contains: ["<vault>"]}) { operationId readyAt calls { target data } } }`
/// for each vault. Check that the network's index reads as current first: a
/// lagging index returns no rows. Then cancel exactly the pending ids:
/// `cancel` reverts on anything not pending, so one cancelled or done id
/// reverts the whole Safe transaction.
///
/// `20260729-migrate-governance-to-timelock` selects its targets from live
/// state, so a `run()` of it on Base today authors the same three
/// transactions. This script exists for the stricter pre-flight: that one
/// accepts any mix of Safe- and timelock-owned vaults, while this one
/// refuses unless, over the rename rollout's rows, the Safe owns exactly
/// these three, and it pins the vaults'
/// beacons, receipts and freeze state.
///
/// `run()` and `verify()` are `SafeBundleScript`'s: `run()` executes the
/// bundle through the Safe on a fork, requires the post-state, proves the
/// timelock governs the three vaults afterwards and can hand them back
/// (`assertReversible`), and writes the artifact; `verify(path)` holds a
/// downloaded artifact to the bundle re-derived from live state.
///
/// @dev Dispatch via `Actions → run-script` with
/// `script = 20261103-hand-wmt-mc-dis-to-timelock`, `sig = run()` and
/// `network = base`.
contract HandWmtMcDisToTimelock is SafeBundleScript, IStoxScript {
    /// @notice Salt of the post-move governance proof's timelock operation.
    /// Fork-only; never scheduled on chain.
    bytes32 internal constant PROOF_SALT = keccak256("st0x.hand-wmt-mc-dis-to-timelock.proof");

    /// @inheritdoc IStoxScript
    function declaration() external pure returns (ScriptDeclaration memory) {
        return LibStoxMigrations.notAMigration();
    }

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x Base: hand tWMT, tMC and tDIS vault ownership to the governance timelock";
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat("out/20261103-hand-wmt-mc-dis-to-timelock-", vm.toString(block.chainid), ".json");
    }

    /// @inheritdoc SafeBundleScript
    /// @dev Base's token-owner Safe. `preflight` proves it in policy.
    function safe() internal pure override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(LibSafeInvariants.BASE_CHAIN_ID)));
    }

    /// @notice Base's governance timelock. `preflight` proves its state.
    /// @return The timelock.
    function timelock() internal pure returns (address) {
        return LibTimelockInvariants.timelockForChainId(LibSafeInvariants.BASE_CHAIN_ID);
    }

    /// @notice The three vaults this script moves, in token-table order.
    /// @return vaults tWMT, tMC and tDIS.
    function handoverVaults() internal pure returns (address[] memory vaults) {
        vaults = new address[](3);
        vaults[0] = LibTokenInvariants.WMT_RECEIPT_VAULT;
        vaults[1] = LibTokenInvariants.MC_RECEIPT_VAULT;
        vaults[2] = LibTokenInvariants.DIS_RECEIPT_VAULT;
    }

    /// @notice Whether `vault` is one of the three this script moves.
    /// @param vault The vault.
    /// @return True for tWMT, tMC and tDIS.
    function isHandoverVault(address vault) internal pure returns (bool) {
        address[] memory vaults = handoverVaults();
        for (uint256 i = 0; i < vaults.length; i++) {
            if (vaults[i] == vault) return true;
        }
        return false;
    }

    /// @inheritdoc SafeBundleScript
    /// @dev Base only. The Safe and timelock are what this repo pins; every
    /// beacon is timelock-owned; both authorisers carry their pinned map with
    /// every `_ADMIN` on the timelock and none on the Safe; every vault is on
    /// its region's authoriser; the three vaults are Safe-owned, carry no
    /// owner freeze, proxy the in-use vault beacon and are bound to receipts
    /// that proxy the in-use receipt beacon; every other vault is
    /// timelock-owned (over the rename rollout's fixed rows).
    function preflight() internal view override {
        if (block.chainid != LibSafeInvariants.BASE_CHAIN_ID) revert HandoverNotOnBase(block.chainid);
        TokenInstance[] memory tokens = LibTokenInvariants.productionTokensForChainId(block.chainid);
        address authoriser = LibAuthoriserInvariants.authoriserForChainId(block.chainid);
        // Safe policy, timelock state, beacon owners, every vault on its
        // region's authoriser, and the US authoriser's map.
        LibInvariants.assertProductionState(tokens, authoriser);
        address chainSafe = address(safe());
        address chainTimelock = timelock();

        address euAuthoriser = LibAuthoriserInvariants.euAuthoriserForChainId(block.chainid);
        LibAuthoriserInvariants.assertExpectedEuGrants(
            euAuthoriser, chainTimelock, LibAuthoriserInvariants.GRANTEE_EU_MINTER
        );
        assertSafeHoldsNoAdmin(authoriser, chainSafe);
        assertSafeHoldsNoAdmin(euAuthoriser, chainSafe);

        address[4] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(block.chainid);
        address vaultBeacon = beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX];
        address receiptBeacon = beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX];
        // Ownership over the rename rollout's fixed rows only: a vault pinned
        // later, still on the Safe, is not this bundle's to move and must not
        // make it refuse.
        tokens = LibUnderlyingNamingRollout.tokens(block.chainid);
        for (uint256 i = 0; i < tokens.length; i++) {
            address vault = tokens[i].receiptVault;
            address owner = Ownable(vault).owner();
            if (!isHandoverVault(vault)) {
                if (owner != chainTimelock) revert VaultNotOnTimelock(vault, owner);
                continue;
            }
            if (owner != chainSafe) revert HandoverVaultNotOnSafe(vault, owner);
            uint256 frozenUntil = IOwnerFreezableV1(vault).ownerFrozenUntil();
            if (frozenUntil != 0) revert HandoverVaultOwnerFrozen(vault, frozenUntil);
            address beacon = beaconOf(vault);
            if (beacon != vaultBeacon) revert HandoverVaultBeaconMismatch(vault, vaultBeacon, beacon);
            address receipt = address(IReceiptVaultV3(payable(vault)).receipt());
            if (receipt != tokens[i].receipt) revert HandoverVaultReceiptMismatch(vault, tokens[i].receipt, receipt);
            beacon = beaconOf(receipt);
            if (beacon != receiptBeacon) revert HandoverReceiptBeaconMismatch(receipt, receiptBeacon, beacon);
        }
    }

    /// @notice The beacon a registry beacon proxy dispatches through, read
    /// from its runtime bytecode (the beacon is an immutable; the ERC-1967
    /// slot is never read for dispatch).
    /// @param proxy The proxy.
    /// @return beacon The beacon, or zero when `proxy` is not a registry
    /// beacon proxy.
    function beaconOf(address proxy) internal view returns (address beacon) {
        (, beacon) = LibExtrospectRegistryBeaconProxy.isRegistryBeaconProxy(proxy.code);
    }

    /// @notice Revert if the Safe holds any of the seven `_ADMIN` roles on
    /// `authoriser`. `assertExpectedGrants` checks only what must be held.
    /// @param authoriser The authoriser.
    /// @param chainSafe The chain's Safe.
    function assertSafeHoldsNoAdmin(address authoriser, address chainSafe) internal view {
        // The `_ADMIN` roles are the map's leading `ADMIN_ROLE_COUNT` entries,
        // the same seven on the EU map; the holder arguments do not change
        // which roles they are.
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants(chainSafe, address(0));
        for (uint256 i = 0; i < LibAuthoriserInvariants.ADMIN_ROLE_COUNT; i++) {
            if (IAccessControl(authoriser).hasRole(grants[i].role, chainSafe)) {
                revert SafeHoldsAdminRole(authoriser, grants[i].role);
            }
        }
    }

    /// @inheritdoc SafeBundleScript
    /// @dev `transferOwnership(timelock)` on tWMT, tMC and tDIS.
    function authorBundle() internal pure override returns (SafeTx[] memory txs) {
        address[] memory vaults = handoverVaults();
        txs = new SafeTx[](vaults.length);
        for (uint256 i = 0; i < vaults.length; i++) {
            txs[i] = SafeTx({
                to: vaults[i],
                value: 0,
                data: abi.encodeCall(Ownable.transferOwnership, (timelock())),
                operation: Enum.Operation.Call
            });
        }
    }

    /// @inheritdoc SafeBundleScript
    /// @dev Every vault the rename rollout covers, the three included, is
    /// timelock-owned; every Base vault is on its region's authoriser; the
    /// beacons and the timelock are unchanged; the Safe still carries the
    /// token-owner policy.
    function assertPostState() internal view override {
        LibTokenInvariants.assertUniformOwnership(LibUnderlyingNamingRollout.tokens(block.chainid), timelock());
        LibInvariants.assertProductionState(
            LibTokenInvariants.productionTokensForChainId(block.chainid),
            LibAuthoriserInvariants.authoriserForChainId(block.chainid)
        );
    }

    /// @inheritdoc SafeBundleScript
    /// @dev Runs the governance proof on a snapshot, so `run()` writes the
    /// artifact from the post-bundle state rather than 48h later.
    function assertReversible() internal override {
        uint256 postBundle = vm.snapshotState();
        proveGovernance();
        vm.revertToState(postBundle);
    }

    /// @notice The move's governance proof: the Safe's direct
    /// `transferOwnership` on each vault now reverts, and handing the three
    /// back to the Safe, scheduled through the timelock by the Safe's real
    /// threshold-gated exec, is not ready inside the 48h window, executes
    /// after it from a roleless key, and leaves the Safe the owner again. The
    /// Safe keeps power over the three, 48h later, including the power to
    /// undo this move.
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
        console2.log("Governance proven: direct transfer refused; schedule -> 48h -> execute hands the vaults back");
    }
}
