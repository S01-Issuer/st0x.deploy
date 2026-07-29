// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";
import {TimelockController} from "@openzeppelin-contracts-5.6.1/governance/TimelockController.sol";

import {IGnosisSafe} from "../src/interface/IGnosisSafe.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibSafeOps, SafeTx} from "../src/lib/LibSafeOps.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "../src/lib/LibTokenInvariants.sol";

/// @notice The active chain's governance-timelock pin is still a
/// placeholder. The migration cannot be authored before the
/// `20260729-deploy-governance-timelock` broadcast has executed on this
/// chain and the post-execution pin PR has hydrated the pin.
/// @param chainId The active chain id whose pin is unhydrated.
error TimelockNotPinned(uint256 chainId);

/// @notice This chain has no production token table to migrate. A typed
/// revert rather than a silent fallback to another chain's table.
/// @param chainId The active chain id without a token table.
error UnsupportedChainForTokenTable(uint256 chainId);

/// @notice The chain's V4 authoriser clone has no runtime code.
/// @param authoriser The authoriser address with no code.
error MigrationAuthoriserNotDeployed(address authoriser);

/// @notice The chain's V4 authoriser clone's runtime codehash does not
/// match the pinned EIP-1167 codehash — the clone does not proxy the
/// audited implementation, so no admin role may be moved on it.
/// @param authoriser The authoriser inspected.
/// @param expected The pinned clone codehash.
/// @param actual The codehash observed on-chain.
error MigrationAuthoriserCodehashMismatch(address authoriser, bytes32 expected, bytes32 actual);

/// @notice An OPERATIONAL grant (service signer or Safe action role) is
/// missing on the chain's authoriser at pre-flight. These entries are
/// outside this migration's write set, so their absence is drift that must
/// abort the authoring.
/// @param authoriser The authoriser inspected.
/// @param role The missing role.
/// @param grantee The grantee that should hold it.
error ExpectedOperationalGrantMissing(address authoriser, bytes32 role, address grantee);

/// @notice A production receipt vault reports an owner that is neither the
/// Safe (the only acceptable pre-migration state) nor the timelock (already
/// migrated). Unknown ownership on a production vault is exactly the drift
/// this script must never paper over with a blind `transferOwnership`.
/// @param vault The receipt vault inspected.
/// @param actual The unexpected address returned by `owner()`.
error UnexpectedVaultOwner(address vault, address actual);

/// @notice An authoriser `_ADMIN` role is held by neither the Safe nor the
/// timelock. There is no principal to migrate FROM, so the grant map has
/// drifted outside both accepted states and the authoring aborts.
/// @param role The `_ADMIN` role in the unexpected state.
error UnexpectedAdminRoleState(bytes32 role);

/// @notice Every production vault is already timelock-owned and every
/// `_ADMIN` role already sits (exclusively) on the timelock — the migration
/// has fully landed. Dispatching again authors an empty bundle, which is
/// never meaningful.
error NothingToMigrate();

/// @notice The end-to-end governance-loop proof did not leave the scheduled
/// operation in the `Done` state — the schedule → delay → execute path a
/// future admin action must take does not work against the post-migration
/// state.
/// @param id The timelock operation id that failed to complete.
error GovernanceLoopNotProven(bytes32 id);

/// @title MigrateGovernanceToTimelock
/// @notice **PENDING.** Authors the Safe bundle that hands ST0x governance
/// on the active chain to the governance timelock:
///
///   1. Grants each of the authoriser's seven `_ADMIN` roles to the
///      timelock (`grantRole` — the Safe can, because each `_ADMIN` role
///      administers itself and the Safe holds it).
///   2. Transfers ownership of every production receipt vault from the
///      Safe to the timelock (`transferOwnership` — single-step
///      `OwnableUpgradeable`).
///   3. Renounces the Safe's own copy of each `_ADMIN` role
///      (`renounceRole` — last, so the Safe stays fully empowered until
///      every grant and transfer has landed inside the same atomic batch).
///
/// After execution the timelock is the only path to `setAuthorizer`,
/// `transferOwnership`, owner freezes, and authoriser grant-map changes:
/// the Safe schedules an operation on the timelock, waits out
/// `TIMELOCK_MIN_DELAY` (48h), then executes it. The Safe KEEPS its three
/// direct action roles (`DEPOSIT` / `WITHDRAW` / `CERTIFY`) — day-to-day
/// operations are not timelocked, only admin power is.
///
/// This is a Safe-routed operation (every call is `onlyOwner` /
/// role-gated on the Safe), so the script emits a Safe Tx Builder JSON
/// artifact for signer review + execution via the Safe UI. It never
/// broadcasts. Dispatch via `Actions → run-script` with
/// `script = 20260729-migrate-governance-to-timelock`, `sig = run()` and
/// the target network; execute the emitted bundle per chain.
///
/// The script is SELF-SCOPING: it reads every vault's live `owner()` and
/// every `_ADMIN` role's live holders and targets exactly what is still on
/// the Safe. A partial prior execution resumes cleanly (already-migrated
/// vaults and roles are skipped; a role held by both sides gets only the
/// renounce); full completion refuses with `NothingToMigrate`; any state
/// outside {Safe, timelock} aborts the authoring with a typed error.
///
/// @dev Flow:
/// 1. **Pre-flight** — the Safe carries the pinned policy; the chain's
///    timelock pin is hydrated and `assertTimelockState` passes (codehash,
///    48h delay, Safe as sole proposer/canceller/executor,
///    self-administration, no open roles); the chain's V4 authoriser clone
///    carries the pinned codehash and its six operational grants (service
///    signer + Safe action roles) are intact.
/// 2. **Select** — still-Safe-owned vaults and still-Safe-held `_ADMIN`
///    roles, from live chain state.
/// 3. **Build** — grants, then transfers, then renounces, in one bundle.
///    Compute the canonical MultiSend `SafeTxHash` against the live nonce
///    for signer cross-check.
/// 4. **Simulate** — prank-route each bundle item as the Safe.
/// 5. **Post-state** — every production vault reports the timelock as
///    `owner()` and the chain's authoriser as `authorizer()`; the full
///    grant map holds with the timelock as admin holder; the Safe holds no
///    `_ADMIN` role; Safe identity + threshold unchanged; timelock state
///    unchanged.
/// 6. **Artifact** — emit the Tx Builder JSON to
///    `out/20260729-governance-timelock-migration-<chainid>.json`.
/// 7. **Governance-loop proof** — schedule an idempotent admin operation
///    on the timelock through the Safe's threshold-gated `execTransaction`
///    (n+1 walk, which also proves undersigned attempts are rejected),
///    prove it is NOT executable inside the delay, warp past the delay,
///    execute it the same way, and assert the operation is `Done`. This is
///    the exact path every future governance action takes, proven
///    end-to-end against the post-migration state — the migration cannot
///    author a bundle that locks governance out.
contract MigrateGovernanceToTimelock is Script {
    /// @notice The number of authoriser `_ADMIN` roles the migration moves —
    /// the leading slice of `LibAuthoriserInvariants.expectedGrants`.
    uint256 internal constant ADMIN_ROLE_COUNT = 7;

    /// @notice Human-readable name embedded in the emitted Tx Builder
    /// JSON's `meta.name`. Visible to signers in the Safe Tx Builder UI.
    string internal constant BUNDLE_NAME = "ST0x governance to timelock: vault ownership + authoriser admin roles";

    /// @notice Salt for the governance-loop proof operation. Any constant
    /// works — the proof runs only in simulation.
    bytes32 internal constant LOOP_PROOF_SALT = keccak256("st0x.governance.timelock.loop-proof");

    /// @notice The chain's governance timelock. Virtual so the test harness
    /// can point the script at a fork-deployed timelock before the
    /// production pins are hydrated; production dispatch always reads the
    /// `LibTimelockInvariants` pin.
    /// @return The active chain's governance timelock.
    function activeChainTimelock() internal view virtual returns (address) {
        return LibTimelockInvariants.timelockForChainId(block.chainid);
    }

    /// @notice The chain's V4 authoriser clone, selected by chain id from
    /// `LibProdDeployV4`. Both chains' clones proxy the same Zoltu-deployed
    /// 0.1.1 impl address, so they share one EIP-1167 codehash pin.
    /// @return The active chain's authoriser clone.
    function activeChainAuthoriser() internal view returns (address) {
        if (block.chainid == LibSafeInvariants.BASE_CHAIN_ID) {
            return LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;
        }
        if (block.chainid == LibSafeInvariants.ETHEREUM_CHAIN_ID) {
            return LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM;
        }
        revert UnsupportedChainForTokenTable(block.chainid);
    }

    /// @notice The chain's production token table, selected by chain id.
    /// @return The active chain's token instances.
    function tokensForActiveChain() internal view returns (TokenInstance[] memory) {
        if (block.chainid == LibSafeInvariants.BASE_CHAIN_ID) {
            return LibTokenInvariants.productionTokensBase();
        }
        if (block.chainid == LibSafeInvariants.ETHEREUM_CHAIN_ID) {
            return LibTokenInvariants.productionTokensEthereum();
        }
        revert UnsupportedChainForTokenTable(block.chainid);
    }

    /// @notice The seven `_ADMIN` roles, sliced from the master grant map so
    /// this script cannot drift from the invariant lib's single source.
    /// @return roles The seven `_ADMIN` role hashes in map order.
    function adminRoles() internal pure returns (bytes32[] memory roles) {
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants(address(0), address(1));
        roles = new bytes32[](ADMIN_ROLE_COUNT);
        for (uint256 i = 0; i < ADMIN_ROLE_COUNT; i++) {
            // The `_ADMIN` slice is exactly the entries granted to the
            // sentinel admin holder — pinned by the slice test in
            // `LibAuthoriserInvariants.t.sol`.
            roles[i] = grants[i].role;
        }
    }

    /// @notice Author the governance migration: pre-flight, select from
    /// live state, build + simulate the bundle, assert the post-state, emit
    /// the artifact, and prove the schedule → delay → execute loop works
    /// against the post-migration state. Does not broadcast — execution
    /// happens via the Safe UI using the emitted artifact.
    function run() external {
        // --- Pre-flight ---------------------------------------------------

        IGnosisSafe safe = IGnosisSafe(LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid));

        address timelock = activeChainTimelock();
        if (timelock == address(0)) revert TimelockNotPinned(block.chainid);
        LibTimelockInvariants.assertTimelockState(timelock, address(safe));

        address authoriser = activeChainAuthoriser();
        _preflightAuthoriser(authoriser, address(safe), timelock);

        TokenInstance[] memory tokens = tokensForActiveChain();

        // --- Select from live state ---------------------------------------

        address[] memory vaultTargets = _selectVaultTargets(tokens, address(safe), timelock);
        (bytes32[] memory grantRoles, bytes32[] memory renounceRoles) =
            _selectRoleTargets(authoriser, address(safe), timelock);

        if (vaultTargets.length == 0 && grantRoles.length == 0 && renounceRoles.length == 0) {
            revert NothingToMigrate();
        }

        // --- Build the bundle ---------------------------------------------

        SafeTx[] memory txs = _buildBundle(authoriser, timelock, address(safe), vaultTargets, grantRoles, renounceRoles);

        // Capture the nonce before any simulation; the artifact executes as
        // a single MultiSend at this nonce, so this is the hash signers
        // cross-check in the Safe UI.
        uint256 nonce = safe.nonce();
        bytes32 bundleSafeTxHash = LibSafeOps.computeMultiSendSafeTxHash(safe, txs, nonce);

        // --- Simulate -----------------------------------------------------

        for (uint256 i = 0; i < txs.length; i++) {
            LibSafeOps.simulateExternalCall(safe, txs[i].to, txs[i].data);
        }

        // --- Post-state ---------------------------------------------------

        // Every production vault is timelock-owned and still gated by the
        // chain's authoriser.
        LibTokenInvariants.assertUniformOwnership(tokens, timelock);
        LibTokenInvariants.assertUniformAuthoriser(tokens, authoriser);

        // The full grant map holds with the timelock as admin holder, and
        // the Safe's admin copies are gone — admin power moves, operational
        // power stays.
        LibAuthoriserInvariants.assertExpectedGrants(authoriser, address(safe), timelock);
        bytes32[] memory roles = adminRoles();
        for (uint256 i = 0; i < roles.length; i++) {
            if (IAccessControl(authoriser).hasRole(roles[i], address(safe))) {
                revert UnexpectedAdminRoleState(roles[i]);
            }
        }

        // Safe identity + threshold unchanged; timelock configuration
        // unchanged.
        LibSafeInvariants.assertImmutableInvariants(safe);
        LibSafeInvariants.assertThreshold(safe, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD);
        LibTimelockInvariants.assertTimelockState(timelock, address(safe));

        // --- Artifact -----------------------------------------------------

        string memory artifactPath =
            string.concat("out/20260729-governance-timelock-migration-", vm.toString(block.chainid), ".json");
        string memory json = LibSafeOps.emitTxBuilderJson(address(safe), block.chainid, BUNDLE_NAME, txs);
        vm.writeFile(artifactPath, json);

        console2.log("==== TX BUILDER JSON BEGIN ====");
        console2.log(json);
        console2.log("==== TX BUILDER JSON END ====");
        console2.log("Artifact:", artifactPath);
        console2.log("Bundle MultiSend SafeTxHash:", vm.toString(bundleSafeTxHash));
        console2.log("Nonce:", nonce);
        console2.log("Timelock:", vm.toString(timelock));
        console2.log("Vault transfers:", vaultTargets.length);
        console2.log("Admin role grants:", grantRoles.length);
        console2.log("Admin role renounces:", renounceRoles.length);

        // --- Governance-loop proof ----------------------------------------

        _proveGovernanceLoop(safe, timelock, authoriser);
    }

    /// @notice Pre-flight the chain's authoriser: deployed with the pinned
    /// EIP-1167 codehash, and the six OPERATIONAL grants (service signer +
    /// Safe action roles — the entries this migration must not touch) are
    /// intact. The `_ADMIN` slice is deliberately NOT asserted here: a
    /// partial prior execution legitimately leaves it split between Safe
    /// and timelock, and the per-role state machine in `_selectRoleTargets`
    /// handles every accepted state (and aborts on any other).
    /// @param authoriser The chain's authoriser clone.
    /// @param safe The chain's token-owner Safe.
    /// @param timelock The chain's governance timelock.
    function _preflightAuthoriser(address authoriser, address safe, address timelock) internal view {
        if (authoriser.code.length == 0) revert MigrationAuthoriserNotDeployed(authoriser);
        bytes32 codehash = authoriser.codehash;
        if (codehash != LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH) {
            revert MigrationAuthoriserCodehashMismatch(
                authoriser, LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH, codehash
            );
        }
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants(safe, timelock);
        for (uint256 i = ADMIN_ROLE_COUNT; i < grants.length; i++) {
            if (!IAccessControl(authoriser).hasRole(grants[i].role, grants[i].grantee)) {
                revert ExpectedOperationalGrantMissing(authoriser, grants[i].role, grants[i].grantee);
            }
        }
    }

    /// @notice Select the vault migration targets from live chain state:
    /// every production receipt vault still owned by the Safe. A vault
    /// already owned by the timelock is skipped; any other owner aborts the
    /// authoring.
    /// @param tokens The chain's token table.
    /// @param safe The chain's token-owner Safe.
    /// @param timelock The chain's governance timelock.
    /// @return targets The still-Safe-owned receipt vaults, in table order.
    function _selectVaultTargets(TokenInstance[] memory tokens, address safe, address timelock)
        internal
        view
        returns (address[] memory targets)
    {
        address[] memory candidates = new address[](tokens.length);
        uint256 count = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            address actual = Ownable(tokens[i].receiptVault).owner();
            if (actual == timelock) {
                continue;
            }
            if (actual != safe) {
                revert UnexpectedVaultOwner(tokens[i].receiptVault, actual);
            }
            candidates[count] = tokens[i].receiptVault;
            count++;
        }
        targets = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            targets[i] = candidates[i];
        }
    }

    /// @notice Select the role migration work from live chain state. Per
    /// `_ADMIN` role: Safe-only → grant + renounce; both (partial prior
    /// run) → renounce only; timelock-only → done, skip; neither → abort.
    /// @param authoriser The chain's authoriser clone.
    /// @param safe The chain's token-owner Safe.
    /// @param timelock The chain's governance timelock.
    /// @return grantRoles Roles to grant to the timelock.
    /// @return renounceRoles Roles the Safe must renounce.
    function _selectRoleTargets(address authoriser, address safe, address timelock)
        internal
        view
        returns (bytes32[] memory grantRoles, bytes32[] memory renounceRoles)
    {
        bytes32[] memory roles = adminRoles();
        bytes32[] memory grantScratch = new bytes32[](roles.length);
        bytes32[] memory renounceScratch = new bytes32[](roles.length);
        uint256 grantCount = 0;
        uint256 renounceCount = 0;
        IAccessControl acl = IAccessControl(authoriser);
        for (uint256 i = 0; i < roles.length; i++) {
            bool safeHolds = acl.hasRole(roles[i], safe);
            bool timelockHolds = acl.hasRole(roles[i], timelock);
            if (!safeHolds && !timelockHolds) {
                revert UnexpectedAdminRoleState(roles[i]);
            }
            if (!timelockHolds) {
                grantScratch[grantCount] = roles[i];
                grantCount++;
            }
            if (safeHolds) {
                renounceScratch[renounceCount] = roles[i];
                renounceCount++;
            }
        }
        grantRoles = new bytes32[](grantCount);
        for (uint256 i = 0; i < grantCount; i++) {
            grantRoles[i] = grantScratch[i];
        }
        renounceRoles = new bytes32[](renounceCount);
        for (uint256 i = 0; i < renounceCount; i++) {
            renounceRoles[i] = renounceScratch[i];
        }
    }

    /// @notice Build the bundle in the safety-critical order: every grant
    /// first, then every vault transfer, then every renounce — the Safe
    /// gives nothing up until everything it is handing over has landed, and
    /// the whole sequence executes atomically in one MultiSend.
    /// @param authoriser The chain's authoriser clone.
    /// @param timelock The chain's governance timelock.
    /// @param safe The chain's token-owner Safe.
    /// @param vaultTargets The still-Safe-owned receipt vaults.
    /// @param grantRoles Roles to grant to the timelock.
    /// @param renounceRoles Roles the Safe renounces.
    /// @return txs The bundle transactions in execution order.
    function _buildBundle(
        address authoriser,
        address timelock,
        address safe,
        address[] memory vaultTargets,
        bytes32[] memory grantRoles,
        bytes32[] memory renounceRoles
    ) internal pure returns (SafeTx[] memory txs) {
        txs = new SafeTx[](grantRoles.length + vaultTargets.length + renounceRoles.length);
        uint256 t = 0;
        for (uint256 i = 0; i < grantRoles.length; i++) {
            txs[t] = SafeTx({
                to: authoriser,
                value: 0,
                data: abi.encodeCall(IAccessControl.grantRole, (grantRoles[i], timelock)),
                operation: 0
            });
            t++;
        }
        for (uint256 i = 0; i < vaultTargets.length; i++) {
            txs[t] = SafeTx({
                to: vaultTargets[i], value: 0, data: abi.encodeCall(Ownable.transferOwnership, (timelock)), operation: 0
            });
            t++;
        }
        for (uint256 i = 0; i < renounceRoles.length; i++) {
            txs[t] = SafeTx({
                to: authoriser,
                value: 0,
                data: abi.encodeCall(IAccessControl.renounceRole, (renounceRoles[i], safe)),
                operation: 0
            });
            t++;
        }
    }

    /// @notice Prove the post-migration governance loop end-to-end on the
    /// fork: the Safe schedules an idempotent admin operation on the
    /// timelock through its threshold-gated `execTransaction` (the n+1
    /// walk also proves undersigned attempts are rejected with `GS020`),
    /// the operation is pending-but-not-ready inside the 48h window, and
    /// after the delay the Safe executes it the same way, leaving the
    /// operation `Done`. The operation — re-granting `DEPOSIT` to the
    /// service signer — is a no-op on live state, so the proof leaves no
    /// residue beyond consumed Safe nonces (simulation-only anyway).
    /// @param safe The chain's token-owner Safe.
    /// @param timelock The chain's governance timelock.
    /// @param authoriser The chain's authoriser clone.
    function _proveGovernanceLoop(IGnosisSafe safe, address timelock, address authoriser) internal {
        bytes memory adminAction = abi.encodeCall(
            IAccessControl.grantRole, (keccak256("DEPOSIT"), LibAuthoriserInvariants.GRANTEE_SERVICE_1C66)
        );
        TimelockController controller = TimelockController(payable(timelock));
        bytes32 id = controller.hashOperation(authoriser, 0, adminAction, bytes32(0), LOOP_PROOF_SALT);

        // Schedule through the Safe's real signature-verified exec path.
        bytes memory scheduleData = abi.encodeCall(
            TimelockController.schedule,
            (authoriser, 0, adminAction, bytes32(0), LOOP_PROOF_SALT, LibTimelockInvariants.TIMELOCK_MIN_DELAY)
        );
        LibSafeOps.simulateNPlus1(safe, timelock, scheduleData, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD);

        // Inside the window: pending, not executable.
        if (!controller.isOperationPending(id) || controller.isOperationReady(id)) {
            revert GovernanceLoopNotProven(id);
        }

        // After the delay: executable, and execution completes the
        // operation.
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        if (!controller.isOperationReady(id)) {
            revert GovernanceLoopNotProven(id);
        }
        bytes memory executeData =
            abi.encodeCall(TimelockController.execute, (authoriser, 0, adminAction, bytes32(0), LOOP_PROOF_SALT));
        LibSafeOps.simulateNPlus1(safe, timelock, executeData, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD);
        if (!controller.isOperationDone(id)) {
            revert GovernanceLoopNotProven(id);
        }

        console2.log("Governance loop proven: schedule -> 48h delay -> execute, through the Safe threshold gate");
    }
}
