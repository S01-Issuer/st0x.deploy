// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibTimelockController} from "rain-deploy-0.1.18/src/lib/LibTimelockController.sol";
import {LibSafeInvariants} from "./LibSafeInvariants.sol";
import {RoleGrant} from "./RoleGrant.sol";

/// @notice No ST0x governance timelock address is pinned for the active
/// chain. Deliberately a typed revert rather than a silent fallback to
/// another chain's timelock: asserting or migrating against the wrong
/// chain's timelock is the catastrophic failure this selector exists to
/// prevent.
/// @param chainId The chain id with no pinned governance timelock.
error UnsupportedChainForGovernanceTimelock(uint256 chainId);

/// @title LibTimelockInvariants
/// @notice The ST0x governance timelock's pins: its minimum delay, its
/// address per chain, and its role model's canceller, over `rain-deploy`'s
/// `LibTimelockController`, which owns the timelock's code (the
/// `TimelockController` record frozen in the release this repo pins), its
/// constructor arguments, its Zoltu address and its state assertion. The
/// timelock is an UNMODIFIED, pre-audited OpenZeppelin `TimelockController`
/// that sits between the token-owner Safe and the
/// privileged surfaces it governs. The timelock is the `owner()` of every
/// production receipt vault and of the four in-use upgrade beacons, and the
/// sole holder of the authoriser's seven `_ADMIN` roles, so every ownership action and every
/// grant-map change must be scheduled, wait out `TIMELOCK_MIN_DELAY`, and
/// only then execute.
///
/// Role model (`LibTimelockController`'s, pinned by `assertTimelockState`):
/// - The chain's token-owner Safe holds `PROPOSER_ROLE` and
///   `CANCELLER_ROLE` — it schedules, and can veto during the window.
/// - `EXECUTOR_ROLE` is held by `address(0)`, which OZ reads as "open to
///   everyone": once the delay has run ANYONE may execute. The operator
///   cannot censor a matured operation, and the Safe executes as a member of
///   the public rather than by privilege.
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
/// address is a pure function of its creation code — computable by
/// `expectedTimelockAddress`. The per-chain ADDRESS pins below are the
/// audit-trail constants scripts and invariants target; each is written
/// with its chain arm, derived from the frozen creation bytecode before
/// any deploy, and must equal the derivation unconditionally
/// (`testPinsMatchDerivedAddresses`). Constructor arguments embed the
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

    /// @notice The ST0x governance timelock on **Base**. Equals
    /// `expectedTimelockAddress(STOX_TOKEN_OWNER_SAFE)`, which
    /// `testPinsMatchDerivedAddresses` asserts.
    /// https://basescan.org/address/0x48ba1371a78e6cc54157c63721756ab444510db3
    address internal constant STOX_GOVERNANCE_TIMELOCK = address(0x48ba1371A78E6cC54157c63721756ab444510DB3);

    /// @notice The ST0x governance timelock on **Ethereum mainnet**. Equals
    /// `expectedTimelockAddress(STOX_TOKEN_OWNER_SAFE_ETHEREUM)`.
    /// https://etherscan.io/address/0x831e4e1bb2b9a67c00b7d17f252a18a22cd0bd2b
    address internal constant STOX_GOVERNANCE_TIMELOCK_ETHEREUM = address(0x831E4e1bB2b9a67C00b7d17F252A18a22cd0bD2B);

    /// @notice The ST0x governance timelock on **HyperEVM**. HyperEVM
    /// carries 29 live production tokens, so it is governed on exactly the
    /// same terms as Base and Ethereum.
    /// @dev HyperEVM's token-owner Safe shares Ethereum's ADDRESS
    /// (`STOX_TOKEN_OWNER_SAFE_HYPEREVM == STOX_TOKEN_OWNER_SAFE_ETHEREUM`),
    /// and the timelock's constructor embeds only that Safe — so the
    /// Zoltu-derived address is IDENTICAL on the two chains, as this pin and
    /// the Ethereum one show. That is correct and expected (same policy, same
    /// init code, same CREATE2 address); they stay separate constants because
    /// the DEPLOY is per-chain and either could diverge if a chain's Safe ever
    /// moves.
    /// https://hyperevmscan.io/address/0x831e4e1bb2b9a67c00b7d17f252a18a22cd0bd2b
    address internal constant STOX_GOVERNANCE_TIMELOCK_HYPEREVM = address(0x831E4e1bB2b9a67C00b7d17F252A18a22cd0bD2B);

    /// @notice The ST0x governance timelock on **Robinhood Chain** (chain id
    /// 4663). Equals `expectedTimelockAddress(STOX_TOKEN_OWNER_SAFE_ROBINHOOD)`.
    /// @dev Robinhood Chain's token-owner Safe shares the Ethereum / HyperEVM
    /// ADDRESS, and the Safe is the only constructor argument, so the derived
    /// timelock address is identical to theirs. Same policy, same init code,
    /// same CREATE2 address; a separate constant because the deploy is
    /// per-chain.
    /// https://robinhoodchain.blockscout.com/address/0x831e4e1bb2b9a67c00b7d17f252a18a22cd0bd2b
    address internal constant STOX_GOVERNANCE_TIMELOCK_ROBINHOOD = address(0x831E4e1bB2b9a67C00b7d17F252A18a22cd0bD2B);

    /// @notice The ST0x governance timelock on **BNB Smart Chain** (chain id
    /// 56). Equals `expectedTimelockAddress(STOX_TOKEN_OWNER_SAFE_BSC)`; the
    /// shared Safe address gives the shared derived address, as on Ethereum,
    /// HyperEVM and Robinhood Chain.
    /// https://bscscan.com/address/0x831e4e1bb2b9a67c00b7d17f252a18a22cd0bd2b
    address internal constant STOX_GOVERNANCE_TIMELOCK_BSC = address(0x831E4e1bB2b9a67C00b7d17F252A18a22cd0bD2B);

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
    /// selected by chain id. Zero is never a legitimate reading: every pin
    /// is a pure function of the frozen creation bytecode and its chain's
    /// Safe pin, written with the chain arm before any deploy
    /// (`testPinsMatchDerivedAddresses` pins the equality), so consumers
    /// refuse a zero pin as a reverted or never-hydrated arm. Reverts for
    /// any chain without an arm rather than falling back to another
    /// chain's timelock.
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
        if (chainId == LibSafeInvariants.ROBINHOOD_CHAIN_ID) {
            return STOX_GOVERNANCE_TIMELOCK_ROBINHOOD;
        }
        if (chainId == LibSafeInvariants.BSC_CHAIN_ID) {
            return STOX_GOVERNANCE_TIMELOCK_BSC;
        }
        revert UnsupportedChainForGovernanceTimelock(chainId);
    }

    /// @notice The creation code the governance timelock deploy broadcasts:
    /// `LibTimelockController.timelockInitCode` at `TIMELOCK_MIN_DELAY`, with
    /// the chain's Safe as sole proposer (and so canceller), execution open
    /// and the timelock self-administered from birth.
    /// @param proposerSafe The chain's token-owner Safe.
    /// @return The creation code including constructor arguments.
    function timelockInitCode(address proposerSafe) internal pure returns (bytes memory) {
        return LibTimelockController.timelockInitCode(TIMELOCK_MIN_DELAY, proposerSafe);
    }

    /// @notice The Zoltu address `timelockInitCode` deploys to. The deploy
    /// script asserts the landed address equals this, and
    /// `testPinsMatchDerivedAddresses` holds every per-chain pin to it.
    /// @param proposerSafe The chain's token-owner Safe.
    /// @return The deterministic timelock address for that Safe.
    function expectedTimelockAddress(address proposerSafe) internal pure returns (address) {
        return LibTimelockController.expectedTimelockAddress(TIMELOCK_MIN_DELAY, proposerSafe);
    }

    /// @notice The pairs the governance timelock must carry.
    /// @param timelock The timelock.
    /// @param proposerSafe The chain's token-owner Safe.
    /// @return The expected `(role, grantee)` pairs.
    function expectedGrants(address timelock, address proposerSafe) internal pure returns (RoleGrant[] memory) {
        RoleGrant[] memory grants = new RoleGrant[](TIMELOCK_CANCELLER == address(0) ? 4 : 5);
        grants[0] = RoleGrant(TIMELOCK_PROPOSER_ROLE, proposerSafe);
        grants[1] = RoleGrant(TIMELOCK_CANCELLER_ROLE, proposerSafe);
        grants[2] = RoleGrant(TIMELOCK_DEFAULT_ADMIN_ROLE, timelock);
        grants[3] = RoleGrant(TIMELOCK_EXECUTOR_ROLE, address(0));
        if (TIMELOCK_CANCELLER != address(0)) {
            grants[4] = RoleGrant(TIMELOCK_CANCELLER_ROLE, TIMELOCK_CANCELLER);
        }
        return grants;
    }

    /// @notice The pairs the governance timelock must not carry.
    /// @param proposerSafe The chain's token-owner Safe.
    /// @return The forbidden `(role, grantee)` pairs.
    function forbiddenGrants(address proposerSafe) internal pure returns (RoleGrant[] memory) {
        RoleGrant[] memory grants = new RoleGrant[](4);
        grants[0] = RoleGrant(TIMELOCK_DEFAULT_ADMIN_ROLE, proposerSafe);
        grants[1] = RoleGrant(TIMELOCK_PROPOSER_ROLE, address(0));
        grants[2] = RoleGrant(TIMELOCK_CANCELLER_ROLE, address(0));
        grants[3] = RoleGrant(TIMELOCK_DEFAULT_ADMIN_ROLE, address(0));
        return grants;
    }

    /// @notice Assert the governance timelock at `timelock` is in its pinned
    /// state: `LibTimelockController.assertTimelockState` at
    /// `TIMELOCK_MIN_DELAY` with `proposerSafe` as the proposer, and, once
    /// `TIMELOCK_CANCELLER` is hydrated, that canceller holding
    /// `CANCELLER_ROLE`. Reverts with `LibTimelockController`'s typed errors.
    /// @param timelock The governance timelock to validate.
    /// @param proposerSafe The chain's token-owner Safe, the timelock's
    /// proposer.
    function assertTimelockState(address timelock, address proposerSafe) internal view {
        address[] memory cancellers = new address[](TIMELOCK_CANCELLER == address(0) ? 0 : 1);
        if (TIMELOCK_CANCELLER != address(0)) {
            cancellers[0] = TIMELOCK_CANCELLER;
        }
        LibTimelockController.assertTimelockState(timelock, TIMELOCK_MIN_DELAY, proposerSafe, cancellers);
    }
}
