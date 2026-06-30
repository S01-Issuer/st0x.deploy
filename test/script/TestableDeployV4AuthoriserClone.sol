// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployV4AuthoriserClone} from "../../script/20260619-deploy-v4-authoriser-clone.s.sol";
import {VmSafe} from "forge-std-1.16.1/src/Vm.sol";

/// @title TestableDeployV4AuthoriserClone
/// @notice Test scaffolding around `DeployV4AuthoriserClone` that lets the
/// suite inject a simulated post-hydrate clone address into
/// `_resolveClone()`. Production code reads
/// `LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE` directly, which lives in
/// library bytecode (not storage), so `vm.store` cannot move the pin. The
/// subclass-override pattern sidesteps that: tests instantiate this contract
/// instead of the bare script, call `setResolvedClone(addr)` to pre-load the
/// pin, and the script's `mirrorGrants()` / `verify()` happily reads the
/// injected value via the overridden `_resolveClone()`.
/// @dev Kept in a sibling `.sol` file (not `.t.sol`) and not inheriting from
/// `forge-std`'s `Test`, so it counts as zero test contracts and avoids
/// breaking the rainix one-contract-per-`.t.sol`-file convention enforced
/// by `rainix-sol-single-contract`. The test file imports this contract
/// rather than declaring it locally.
contract TestableDeployV4AuthoriserClone is DeployV4AuthoriserClone {
    /// @notice The address `_resolveClone()` returns. Defaults to
    /// `address(0)` so a freshly-instantiated subclass behaves identically
    /// to the un-overridden script (i.e. trips `V4AuthoriserCloneNotPinned`
    /// on the first `mirrorGrants()` / grants-branch `verify()` call).
    address public resolvedClone;

    /// @notice The codehash `_resolveCloneCodehash()` returns. Defaults to
    /// `bytes32(0)` (the lib pin's compile-time value); tests that need a
    /// passing codehash check call `setResolvedCloneCodehash` to inject
    /// the actual EIP-1167 codehash of the fork-deployed clone.
    bytes32 public resolvedCloneCodehash;

    /// @notice The predicted clone address from the most recent `run()`
    /// invocation, captured via `_recordPredictedClone()`. Defaults to
    /// `address(0)` until `run()` is called.
    address public lastPredictedClone;

    /// @notice Inject a simulated post-hydrate clone address. Tests call
    /// this before invoking `mirrorGrants()` / `verify()` to simulate the
    /// state of the world after the post-execution pin PR has merged.
    /// @param clone The address `_resolveClone()` should subsequently
    /// return.
    function setResolvedClone(address clone) external {
        resolvedClone = clone;
    }

    /// @notice Inject a simulated post-hydrate clone codehash. Tests that
    /// exercise the happy-path call this with the captured clone's actual
    /// codehash so the pre-flight codehash check passes; tests that
    /// exercise the codehash-mismatch revert leave it at the default
    /// `bytes32(0)` and rely on a real (non-zero) codehash at the
    /// resolved address.
    /// @param codehash The codehash `_resolveCloneCodehash()` should
    /// subsequently return.
    function setResolvedCloneCodehash(bytes32 codehash) external {
        resolvedCloneCodehash = codehash;
    }

    /// @inheritdoc DeployV4AuthoriserClone
    function _resolveClone() internal view override returns (address) {
        return resolvedClone;
    }

    /// @inheritdoc DeployV4AuthoriserClone
    function _resolveCloneCodehash() internal view override returns (bytes32) {
        return resolvedCloneCodehash;
    }

    /// @inheritdoc DeployV4AuthoriserClone
    function _recordPredictedClone(address predictedClone) internal override {
        lastPredictedClone = predictedClone;
    }

    /// @notice Test-only wrapper exposing the internal `assertCloneCodehash`
    /// so its `CloneCodehashMismatch` revert path can be exercised directly —
    /// the production call site in `run()` always sees a correctly-shaped
    /// simulated clone, so the branch is otherwise unreachable.
    function exposed_assertCloneCodehash(address clone, bytes32 expected) external view {
        assertCloneCodehash(clone, expected);
    }

    /// @notice Test-only wrapper exposing the internal `assertAutoGrantsHeld`
    /// so its `AutoGrantMissing` revert path can be exercised directly.
    function exposed_assertAutoGrantsHeld(address clone, address admin) external view {
        assertAutoGrantsHeld(clone, admin);
    }

    /// @notice Test-only wrapper exposing the internal
    /// `assertNonAdminGrantsAbsent` so its `UnexpectedAutoGrantHeld` revert
    /// path can be exercised directly.
    function exposed_assertNonAdminGrantsAbsent(address clone) external view {
        assertNonAdminGrantsAbsent(clone);
    }

    /// @notice Test-only wrapper exposing the internal
    /// `extractCloneAddressFromLogs` so its NewClone-absent and impl-mismatch
    /// revert paths can be exercised with hand-built logs (the production call
    /// site reads the real factory, which always emits a matching event).
    function exposed_extractCloneAddressFromLogs(VmSafe.Log[] memory logs, address factory, address expectedImpl)
        external
        pure
        returns (address)
    {
        return extractCloneAddressFromLogs(logs, factory, expectedImpl);
    }
}
