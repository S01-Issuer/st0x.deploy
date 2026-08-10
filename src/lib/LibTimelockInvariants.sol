// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {TimelockController} from "@openzeppelin-contracts-5.6.1/governance/TimelockController.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {LibSafeInvariants} from "./LibSafeInvariants.sol";

/// @notice No ST0x governance timelock address is pinned for the active
/// chain. Deliberately a typed revert rather than a silent fallback to
/// another chain's timelock: asserting or migrating against the wrong
/// chain's timelock is the catastrophic failure this selector exists to
/// prevent.
/// @param chainId The chain id with no pinned governance timelock.
error UnsupportedChainForGovernanceTimelock(uint256 chainId);

/// @notice The governance timelock has no runtime code. Either the pin is
/// stale, the deploy never ran on this chain, or the address was computed
/// from different constructor arguments than the deployed instance.
/// @param timelock The timelock address that has no code.
error TimelockNotDeployed(address timelock);

/// @notice The runtime codehash at the timelock address does not match the
/// codehash of the audited OZ `TimelockController` this repo compiles
/// against. The contract at the pin is not the expected timelock.
/// @param timelock The timelock address inspected.
/// @param expected The expected `TimelockController` runtime codehash.
/// @param actual The codehash observed on-chain.
error TimelockCodehashMismatch(address timelock, bytes32 expected, bytes32 actual);

/// @notice The timelock's `getMinDelay()` does not match the pinned
/// `TIMELOCK_MIN_DELAY`. Either the deploy used different constructor
/// arguments or a scheduled `updateDelay` has executed without the pin
/// being updated in the same operational window.
/// @param timelock The timelock inspected.
/// @param expected The pinned minimum delay in seconds.
/// @param actual The minimum delay reported by the live timelock.
error TimelockMinDelayMismatch(address timelock, uint256 expected, uint256 actual);

/// @notice An account that must hold a role on the governance timelock does
/// not hold it. Surfaces the exact `(role, account)` pair that broke the
/// invariant.
/// @param timelock The timelock inspected.
/// @param role The role that should be held.
/// @param account The account that should hold the role.
error TimelockMissingRole(address timelock, bytes32 role, address account);

/// @notice An account holds a role on the governance timelock that the
/// pinned configuration does not sanction — e.g. the zero address holding
/// `EXECUTOR_ROLE` (which OZ treats as "execution open to everyone") or the
/// proposer Safe holding `DEFAULT_ADMIN_ROLE` (an instant-bypass escalation
/// path around the delay).
/// @param timelock The timelock inspected.
/// @param role The role that must not be held.
/// @param account The account that must not hold the role.
error TimelockUnexpectedRole(address timelock, bytes32 role, address account);

/// @title LibTimelockInvariants
/// @notice Reusable constants and invariant assertions for the ST0x
/// governance timelock: an UNMODIFIED, pre-audited OpenZeppelin
/// `TimelockController` (from the version-locked soldeer dependency this
/// repo compiles against) that sits between the token-owner Safe and the
/// privileged surfaces it governs. Post-migration the timelock is the
/// `owner()` of every production receipt vault and the sole holder of the
/// authoriser's seven `_ADMIN` roles, so every ownership action and every
/// grant-map change must be scheduled, wait out `TIMELOCK_MIN_DELAY`, and
/// only then execute.
///
/// Role model (pinned by `assertTimelockState`):
/// - The chain's token-owner Safe holds `PROPOSER_ROLE`, `CANCELLER_ROLE`
///   and `EXECUTOR_ROLE` — it schedules, can cancel during the window, and
///   executes once the delay elapses.
/// - The timelock holds `DEFAULT_ADMIN_ROLE` on itself (OZ
///   self-administration): role changes — e.g. provisioning the dedicated
///   canceller once `TIMELOCK_CANCELLER` is decided — must themselves go
///   through the delay.
/// - Nobody else holds anything. In particular the deploy key holds no role
///   (the deploy passes `admin = address(0)`, so the constructor grants the
///   deployer nothing — there is nothing to revoke), and the zero address
///   holds no role (OZ's "open role" semantics stay disabled).
///
/// @dev The timelock is deployed via the Zoltu deterministic factory, so its
/// address is a pure function of its creation code — computable in-source by
/// `expectedTimelockAddress`. The per-chain ADDRESS pins below are the
/// audit-trail constants scripts and invariants target; each is hydrated by
/// a post-deploy pin PR and must equal the derived address (a structure test
/// pins that equality once hydrated). Constructor arguments embed the
/// chain's Safe, so the timelock address is a per-chain deploy artifact —
/// same policy, different address per chain, exactly like the Safe itself.
library LibTimelockInvariants {
    /// @notice The timelock's minimum delay in seconds: every governance
    /// operation (vault ownership actions, authoriser grant-map changes)
    /// must wait at least this long between `schedule` and `execute`.
    /// 48 hours: long enough for depositors and integrating protocols to
    /// observe a pending admin action and exit, short enough for routine
    /// operations to remain practical. Changing it post-deploy is itself a
    /// timelocked operation (`updateDelay` is self-administered) and must
    /// update this pin in the same operational window.
    uint256 internal constant TIMELOCK_MIN_DELAY = 48 hours;

    /// @notice OZ `TimelockController` proposer role. Mirrored from the OZ
    /// source as a constant so invariant call sites don't need a deployed
    /// instance to name the role; `LibTimelockInvariantsTest` pins each
    /// mirror against the live getter.
    bytes32 internal constant TIMELOCK_PROPOSER_ROLE = keccak256("PROPOSER_ROLE");

    /// @notice OZ `TimelockController` executor role.
    bytes32 internal constant TIMELOCK_EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    /// @notice OZ `TimelockController` canceller role.
    bytes32 internal constant TIMELOCK_CANCELLER_ROLE = keccak256("CANCELLER_ROLE");

    /// @notice OZ `AccessControl` root admin role — held by the timelock on
    /// itself (self-administration) and nobody else.
    bytes32 internal constant TIMELOCK_DEFAULT_ADMIN_ROLE = bytes32(0);

    /// @notice The ST0x governance timelock on **Base**.
    ///
    /// **PLACEHOLDER** (`address(0)`) until the
    /// `20260729-deploy-governance-timelock` broadcast executes on Base and
    /// the post-execution pin PR hydrates this constant with the logged
    /// address (which must equal `expectedTimelockAddress(Base Safe)`).
    address internal constant STOX_GOVERNANCE_TIMELOCK = address(0);

    /// @notice The ST0x governance timelock on **Ethereum mainnet**.
    ///
    /// **PLACEHOLDER** (`address(0)`) until the
    /// `20260729-deploy-governance-timelock` broadcast executes on Ethereum
    /// and the post-execution pin PR hydrates this constant. A distinct
    /// per-chain address: the constructor embeds the chain's Safe, so the
    /// Zoltu-derived address differs per chain by construction.
    address internal constant STOX_GOVERNANCE_TIMELOCK_ETHEREUM = address(0);

    /// @notice The ST0x governance timelock on **HyperEVM**.
    ///
    /// **PLACEHOLDER** (`address(0)`) until the
    /// `20260729-deploy-governance-timelock` broadcast executes on HyperEVM
    /// and the post-execution pin PR hydrates this constant. HyperEVM
    /// carries 29 live production tokens, so it is governed on exactly the
    /// same terms as Base and Ethereum — not a follow-up.
    /// @dev HyperEVM's token-owner Safe shares Ethereum's ADDRESS
    /// (`STOX_TOKEN_OWNER_SAFE_HYPEREVM == STOX_TOKEN_OWNER_SAFE_ETHEREUM`),
    /// and the timelock's constructor embeds only that Safe — so the
    /// Zoltu-derived address is IDENTICAL on the two chains. That is
    /// correct and expected (same policy, same init code, same CREATE2
    /// address), but it means the two pins will read the same value once
    /// hydrated; they are kept as separate constants because the DEPLOY is
    /// per-chain and either could diverge if a chain's Safe ever moves.
    address internal constant STOX_GOVERNANCE_TIMELOCK_HYPEREVM = address(0);

    /// @notice **PLACEHOLDER** for a dedicated canceller principal (a
    /// separate key or Safe that can veto a scheduled operation during the
    /// delay window without being able to propose or execute). Undecided:
    /// until it is chosen the token-owner Safe holds `CANCELLER_ROLE` (the
    /// OZ constructor grants it alongside `PROPOSER_ROLE`). Provisioning a
    /// dedicated canceller later is itself a timelocked operation — schedule
    /// `grantRole(CANCELLER_ROLE, canceller)` on the timelock — and hydrates
    /// this constant in the same operational window. `assertTimelockState`
    /// starts asserting the grant once this pin is non-zero.
    address internal constant TIMELOCK_CANCELLER = address(0);

    /// @notice The ST0x governance timelock address for the active chain,
    /// selected by chain id — `address(0)` until that chain's timelock is
    /// deployed and the pin hydrated. Reverts for any chain without a pin
    /// rather than falling back to another chain's timelock.
    /// @param chainId The active chain id (`block.chainid`).
    /// @return timelock The chain's governance timelock pin.
    function timelockForChainId(uint256 chainId) internal pure returns (address timelock) {
        if (chainId == LibSafeInvariants.BASE_CHAIN_ID) {
            return STOX_GOVERNANCE_TIMELOCK;
        }
        if (chainId == LibSafeInvariants.ETHEREUM_CHAIN_ID) {
            return STOX_GOVERNANCE_TIMELOCK_ETHEREUM;
        }
        if (chainId == LibSafeInvariants.HYPEREVM_CHAIN_ID) {
            return STOX_GOVERNANCE_TIMELOCK_HYPEREVM;
        }
        revert UnsupportedChainForGovernanceTimelock(chainId);
    }

    /// @notice The exact creation code the governance timelock deploy
    /// broadcasts: the audited OZ `TimelockController` creation bytecode
    /// (compiled from the version-locked soldeer dependency under this
    /// repo's single compiler profile) with the pinned constructor
    /// arguments appended — `TIMELOCK_MIN_DELAY`, the supplied Safe as sole
    /// proposer (which also makes it canceller) and sole executor, and
    /// `admin = address(0)` so the timelock is self-administered from birth
    /// and the deploy key is never granted anything.
    /// @param proposerExecutorSafe The chain's token-owner Safe.
    /// @return The creation code including constructor arguments.
    function timelockInitCode(address proposerExecutorSafe) internal pure returns (bytes memory) {
        address[] memory proposers = new address[](1);
        proposers[0] = proposerExecutorSafe;
        address[] memory executors = new address[](1);
        executors[0] = proposerExecutorSafe;
        return abi.encodePacked(
            type(TimelockController).creationCode, abi.encode(TIMELOCK_MIN_DELAY, proposers, executors, address(0))
        );
    }

    /// @notice The deterministic address `timelockInitCode` deploys to via
    /// the Zoltu factory: `CREATE2` with the factory as deployer and a zero
    /// salt (the factory hardcodes it), so the address is a pure function
    /// of the creation code. The deploy script asserts the landed address
    /// equals this; once the per-chain pin is hydrated a structure test
    /// pins `pin == expectedTimelockAddress(chain's Safe)`.
    /// @param proposerExecutorSafe The chain's token-owner Safe.
    /// @return The deterministic timelock address for that Safe.
    function expectedTimelockAddress(address proposerExecutorSafe) internal pure returns (address) {
        bytes32 initCodeHash = keccak256(timelockInitCode(proposerExecutorSafe));
        // forge-lint: disable-next-line(unsafe-typecast)
        return address(
            uint160(
                uint256(keccak256(abi.encodePacked(hex"ff", LibRainDeploy.ZOLTU_FACTORY, bytes32(0), initCodeHash)))
            )
        );
    }

    /// @notice The runtime codehash every deployed governance timelock must
    /// carry: the hash of the OZ `TimelockController` runtime bytecode this
    /// repo compiles. Derived in-source (the contract has no immutables, so
    /// `type(...).runtimeCode` is the exact deployed shape) rather than
    /// pinned as a literal, so a dependency or compiler-settings change
    /// surfaces as a codehash mismatch against the live deployment instead
    /// of silently moving the expectation.
    /// @return The expected `TimelockController` runtime codehash.
    function timelockRuntimeCodehash() internal pure returns (bytes32) {
        return keccak256(type(TimelockController).runtimeCode);
    }

    /// @notice Assert the governance timelock at `timelock` is in its pinned
    /// state: deployed with the expected `TimelockController` runtime
    /// codehash, `getMinDelay() == TIMELOCK_MIN_DELAY`, the Safe holds
    /// proposer + canceller + executor, the timelock self-administers, and
    /// no unsanctioned holder exists on the checked surface — the Safe does
    /// not hold root admin, and the zero address holds nothing (OZ's "open
    /// role" semantics stay disabled). Reverts with a typed error on the
    /// first failure; returns silently otherwise.
    /// @dev The negative checks are targeted assertions over the named
    /// principals, not an exhaustive holder scan (a plain `AccessControl`
    /// cannot enumerate members) — the same bound `LibAuthoriserInvariants`
    /// documents for the authoriser's grant map. Once `TIMELOCK_CANCELLER`
    /// is hydrated the dedicated canceller's grant is asserted too.
    /// @param timelock The governance timelock to validate.
    /// @param proposerExecutorSafe The chain's token-owner Safe expected to
    /// hold the proposer / canceller / executor roles.
    function assertTimelockState(address timelock, address proposerExecutorSafe) internal view {
        if (timelock.code.length == 0) revert TimelockNotDeployed(timelock);
        bytes32 expectedCodehash = timelockRuntimeCodehash();
        bytes32 actualCodehash = timelock.codehash;
        if (actualCodehash != expectedCodehash) {
            revert TimelockCodehashMismatch(timelock, expectedCodehash, actualCodehash);
        }

        uint256 actualMinDelay = TimelockController(payable(timelock)).getMinDelay();
        if (actualMinDelay != TIMELOCK_MIN_DELAY) {
            revert TimelockMinDelayMismatch(timelock, TIMELOCK_MIN_DELAY, actualMinDelay);
        }

        IAccessControl acl = IAccessControl(timelock);

        // The Safe drives every stage of the operation lifecycle: schedule,
        // cancel (until a dedicated canceller is provisioned), execute.
        _assertHasRole(acl, timelock, TIMELOCK_PROPOSER_ROLE, proposerExecutorSafe);
        _assertHasRole(acl, timelock, TIMELOCK_CANCELLER_ROLE, proposerExecutorSafe);
        _assertHasRole(acl, timelock, TIMELOCK_EXECUTOR_ROLE, proposerExecutorSafe);

        // Self-administration: role changes go through the delay.
        _assertHasRole(acl, timelock, TIMELOCK_DEFAULT_ADMIN_ROLE, timelock);

        // The Safe must NOT hold root admin — that would let it re-grant
        // roles instantly, bypassing the delay the timelock exists to
        // impose.
        if (acl.hasRole(TIMELOCK_DEFAULT_ADMIN_ROLE, proposerExecutorSafe)) {
            revert TimelockUnexpectedRole(timelock, TIMELOCK_DEFAULT_ADMIN_ROLE, proposerExecutorSafe);
        }

        // OZ treats a zero-address grantee as "role open to everyone".
        // Every lifecycle role must stay closed: open-proposer or
        // open-canceller is an obvious takeover, and open-executor would
        // let anyone execute (acceptable in some designs, but not the
        // pinned one — execution stays with the Safe).
        _assertNotOpenRole(acl, timelock, TIMELOCK_PROPOSER_ROLE);
        _assertNotOpenRole(acl, timelock, TIMELOCK_CANCELLER_ROLE);
        _assertNotOpenRole(acl, timelock, TIMELOCK_EXECUTOR_ROLE);
        _assertNotOpenRole(acl, timelock, TIMELOCK_DEFAULT_ADMIN_ROLE);

        // Once the dedicated canceller is decided and its pin hydrated, it
        // must hold CANCELLER_ROLE (provisioned via a timelocked
        // `grantRole`).
        if (TIMELOCK_CANCELLER != address(0)) {
            _assertHasRole(acl, timelock, TIMELOCK_CANCELLER_ROLE, TIMELOCK_CANCELLER);
        }
    }

    /// @notice Revert `TimelockMissingRole` unless `account` holds `role`.
    /// @param acl The timelock's `IAccessControl` surface.
    /// @param timelock The timelock address (surfaced in the revert).
    /// @param role The role to check.
    /// @param account The account that must hold the role.
    function _assertHasRole(IAccessControl acl, address timelock, bytes32 role, address account) private view {
        if (!acl.hasRole(role, account)) {
            revert TimelockMissingRole(timelock, role, account);
        }
    }

    /// @notice Revert `TimelockUnexpectedRole` if the zero address holds
    /// `role` — OZ's `onlyRoleOrOpenRole` treats that as the role being
    /// open to every caller.
    /// @param acl The timelock's `IAccessControl` surface.
    /// @param timelock The timelock address (surfaced in the revert).
    /// @param role The role that must not be open.
    function _assertNotOpenRole(IAccessControl acl, address timelock, bytes32 role) private view {
        if (acl.hasRole(role, address(0))) {
            revert TimelockUnexpectedRole(timelock, role, address(0));
        }
    }
}
