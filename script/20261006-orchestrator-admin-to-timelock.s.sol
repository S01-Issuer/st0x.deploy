// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin-contracts-5.6.1/governance/TimelockController.sol";
import {IMigrationRegistryV2} from "rain-deploy-0.1.12/src/interface/IMigrationRegistryV2.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.12/src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.12/src/lib/LibMigrationRegistryDeploy.sol";

import {IGnosisSafe} from "../src/interface/IGnosisSafe.sol";
import {LibOrchestratorInvariants} from "../src/lib/LibOrchestratorInvariants.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibSafeOps, SafeTx} from "../src/lib/LibSafeOps.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";

/// @notice The Safe's line in the migration registry is not at the
/// orchestrator EMERGENCY grant, which this migration is applied onto:
/// either the grant has not executed on this chain, or this bundle already
/// has.
/// @param head The line's head.
error UnexpectedMigrationLine(bytes32 head);

/// @notice The post-move governance proof failed.
/// @param reason What did not hold.
error OrchestratorGovernanceNotProven(string reason);

/// @title OrchestratorAdminToTimelock
/// @notice Authors the per-chain Safe Tx Builder bundle that moves the
/// orchestrator's `DEFAULT_ADMIN_ROLE` from the chain's token-owner Safe to
/// the chain's governance timelock. Three calls, one atomic MultiSend:
///
/// 1. `orchestrator.grantRole(DEFAULT_ADMIN, timelock)`.
/// 2. `orchestrator.renounceRole(DEFAULT_ADMIN, safe)`.
/// 3. `registry.applyMigration(ORCHESTRATOR_ADMIN_TO_TIMELOCK,
///    [ORCHESTRATOR_EMERGENCY])`.
///
/// `DEFAULT_ADMIN_ROLE` administers `MINT_ROLE`, `BURN_ROLE` and
/// `EMERGENCY_ROLE` on the audited 0.1.30 orchestrator, so after this every
/// grant and revoke of those roles is a timelock operation: Safe schedules,
/// 48h, anyone executes. The roles themselves are untouched, so minting,
/// burning and emergency recovery are not delayed. A holder can still
/// `renounceRole` itself immediately.
///
/// The record is applied onto the EMERGENCY grant's, so the registry
/// refuses it on a chain where that grant has not executed: the Safe must be
/// granted `EMERGENCY_ROLE` while it can still do so directly.
///
/// @dev Dispatch via `Actions → run-script` with
/// `script = 20261006-orchestrator-admin-to-timelock` per chain, only after
/// `20261006-grant-orchestrator-emergency` has executed there.
contract OrchestratorAdminToTimelock is Script {
    /// @notice Signer-visible `meta.name` for the emitted bundle.
    string internal constant BUNDLE_NAME = "ST0x orchestrator: move DEFAULT_ADMIN_ROLE to the governance timelock";

    /// @notice Salt for the post-move governance proof's timelock operation.
    /// Fork-only; never scheduled on chain.
    bytes32 internal constant PROOF_SALT = keccak256("st0x.orchestrator-admin-to-timelock.proof");

    /// @notice Chain-suffixed artifact path.
    /// @return path The artifact path for the ACTIVE chain.
    function artifactPath() internal view virtual returns (string memory path) {
        path = string.concat("out/20261006-orchestrator-admin-to-timelock-", vm.toString(block.chainid), ".json");
    }

    /// @notice Pre-flight live state: the Safe, the timelock and the
    /// orchestrator are what this repo pins, the Safe's registry line is at
    /// the EMERGENCY grant, and the orchestrator's roles are exactly what
    /// that implies (Safe admin, Safe EMERGENCY, nothing on the timelock).
    /// @return safe The chain's token-owner Safe.
    /// @return timelock The chain's governance timelock.
    function preflight() internal view returns (address safe, address timelock) {
        safe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        LibTimelockInvariants.assertTimelockState(timelock, safe);
        LibOrchestratorInvariants.assertBeaconSet();

        bytes32 head = LibStoxMigrations.head(safe);
        if (head != LibStoxMigrations.ORCHESTRATOR_EMERGENCY) {
            revert UnexpectedMigrationLine(head);
        }
        LibOrchestratorInvariants.assertInstance(safe);
    }

    /// @notice The bundle for the active chain.
    /// @param safe The chain's token-owner Safe.
    /// @param timelock The chain's governance timelock.
    /// @return txs The grant, the renounce, then the record.
    function authorBundle(address safe, address timelock) internal pure returns (SafeTx[] memory txs) {
        address orchestrator = LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE;
        txs = new SafeTx[](3);
        txs[0] = SafeTx({
            to: orchestrator,
            value: 0,
            data: abi.encodeCall(IAccessControl.grantRole, (bytes32(0), timelock)),
            operation: 0
        });
        txs[1] = SafeTx({
            to: orchestrator,
            value: 0,
            data: abi.encodeCall(IAccessControl.renounceRole, (bytes32(0), safe)),
            operation: 0
        });
        txs[2] = SafeTx({
            to: LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS,
            value: 0,
            data: abi.encodeCall(
                IMigrationRegistryV2.applyMigration,
                (
                    LibStoxMigrations.NAMESPACE,
                    LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK,
                    LibStoxMigrations.onto(safe, LibStoxMigrations.ORCHESTRATOR_EMERGENCY)
                )
            ),
            operation: 0
        });
    }

    /// @notice Assert the post-bundle state on the active fork.
    /// @param safe The chain's token-owner Safe.
    function assertPostState(address safe) internal view {
        // The registry stamps the block the record lands in, which on the
        // fork is this block: an equality with a known value, not a window.
        require(
            // forge-lint: disable-next-line(block-timestamp)
            LibStoxMigrations.applied(safe, LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK) == block.timestamp,
            "OrchestratorAdminToTimelock: record"
        );
        require(
            LibStoxMigrations.head(safe) == LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK,
            "OrchestratorAdminToTimelock: line head"
        );
        LibOrchestratorInvariants.assertInstance(safe);
    }

    /// @notice Prove on the fork that the move did what it is for: the
    /// Safe's direct grant now reverts, and the same grant scheduled through
    /// the timelock by the Safe's real threshold-gated exec is not ready
    /// inside the 48h window and executes after it.
    ///
    /// The operation re-grants `EMERGENCY_ROLE` to the Safe, which already
    /// holds it, so it changes nothing; it still only succeeds if the
    /// timelock administers the role, because `grantRole` checks the
    /// caller's admin role before it checks membership.
    /// @param safe The chain's token-owner Safe.
    /// @param timelock The chain's governance timelock.
    function proveGovernance(IGnosisSafe safe, address timelock) internal {
        address orchestrator = LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE;
        bytes memory grant =
            abi.encodeCall(IAccessControl.grantRole, (LibOrchestratorInvariants.EMERGENCY_ROLE, address(safe)));

        vm.prank(address(safe));
        // slither-disable-next-line low-level-calls
        (bool directOk, bytes memory directRet) = orchestrator.call(grant);
        if (
            directOk
                || keccak256(directRet)
                    != keccak256(
                        abi.encodeWithSelector(
                            IAccessControl.AccessControlUnauthorizedAccount.selector, address(safe), bytes32(0)
                        )
                    )
        ) {
            revert OrchestratorGovernanceNotProven("the Safe can still grant directly");
        }

        TimelockController controller = TimelockController(payable(timelock));
        bytes32 id = controller.hashOperation(orchestrator, 0, grant, bytes32(0), PROOF_SALT);
        LibSafeOps.simulateNPlus1(
            safe,
            timelock,
            abi.encodeCall(
                TimelockController.schedule,
                (orchestrator, 0, grant, bytes32(0), PROOF_SALT, LibTimelockInvariants.TIMELOCK_MIN_DELAY)
            ),
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD
        );
        if (!controller.isOperationPending(id) || controller.isOperationReady(id)) {
            revert OrchestratorGovernanceNotProven("the grant is executable inside the delay");
        }

        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        // Execution is open to anyone; executing from an address with no
        // role proves the operation does not depend on the Safe.
        vm.prank(address(0xdead));
        controller.execute(orchestrator, 0, grant, bytes32(0), PROOF_SALT);
        if (!controller.isOperationDone(id)) {
            revert OrchestratorGovernanceNotProven("the scheduled grant did not execute");
        }
        console2.log("Governance proven: direct grant refused; schedule -> 48h -> execute through the timelock");
    }

    /// @notice Author the bundle for the active chain. Does not broadcast:
    /// execution happens in the Safe UI from the emitted artifact.
    function run() external {
        // --- Pre-flight ---------------------------------------------------

        (address safeAddr, address timelock) = preflight();
        IGnosisSafe safe = IGnosisSafe(safeAddr);

        // --- Build the bundle ----------------------------------------------

        SafeTx[] memory txs = authorBundle(safeAddr, timelock);
        uint256 nonce = safe.nonce();
        bytes32 bundleSafeTxHash = LibSafeOps.computeMultiSendSafeTxHash(safe, txs, nonce);

        // --- Simulate -----------------------------------------------------

        for (uint256 i = 0; i < txs.length; i++) {
            LibSafeOps.simulateExternalCall(safe, txs[i].to, txs[i].data);
        }

        // --- Post-state ---------------------------------------------------

        assertPostState(safeAddr);
        LibSafeInvariants.assertImmutableInvariants(safe);
        LibSafeInvariants.assertThreshold(safe, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD);

        // --- Artifact -----------------------------------------------------

        string memory json = LibSafeOps.emitTxBuilderJson(safeAddr, block.chainid, BUNDLE_NAME, txs);
        vm.writeFile(artifactPath(), json);

        console2.log("==== TX BUILDER JSON BEGIN ====");
        console2.log(json);
        console2.log("==== TX BUILDER JSON END ====");
        console2.log("Bundle MultiSend SafeTxHash:", vm.toString(bundleSafeTxHash));
        console2.log("Nonce:", nonce);
        console2.log("Bundle item count:", txs.length);
        console2.log("Chain:", block.chainid);
        console2.log("Timelock:", timelock);

        // --- Governance proof ---------------------------------------------

        proveGovernance(safe, timelock);
    }

    /// @notice Signer-side integrity check for a CI-authored artifact, run
    /// LOCALLY against a live fork before signing: re-derives the bundle
    /// from current chain state, asserts the artifact matches it exactly,
    /// and prints the MultiSend `SafeTxHash` at the live nonce.
    /// @param jsonPath Filesystem path to the downloaded Tx Builder JSON.
    function verify(string calldata jsonPath) external view {
        (address safeAddr, address timelock) = preflight();
        IGnosisSafe safe = IGnosisSafe(safeAddr);
        LibMigrationRegistry.checkCodeHash();

        SafeTx[] memory expected = authorBundle(safeAddr, timelock);
        LibSafeOps.assertParsedTxsMatch(expected, jsonPath);

        uint256 nonce = safe.nonce();
        console2.log("Artifact verified against live state.");
        console2.log(
            "Bundle MultiSend SafeTxHash:", vm.toString(LibSafeOps.computeMultiSendSafeTxHash(safe, expected, nonce))
        );
        console2.log("Nonce:", nonce);
    }
}
