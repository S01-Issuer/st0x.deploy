// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibProdSafes} from "../../../src/lib/LibProdSafes.sol";
import {LibTokenOwnership, IOwnable, ReceiptVaultOwnerMismatch} from "../../../src/lib/LibTokenOwnership.sol";
import {IGnosisSafe} from "../../../src/interface/IGnosisSafe.sol";
import {LibRainDeploy} from "rain-deploy-0.1.2/src/lib/LibRainDeploy.sol";
import {
    SafeProxyCodehashMismatch,
    SafeSingletonMismatch,
    SafeSingletonBytecodeMismatch,
    SafeVersionMismatch,
    SafeUnexpectedModules,
    SafeUnexpectedGuard,
    SafeFallbackHandlerMismatch,
    SafeOwnerCountMismatch,
    SafeOwnerMismatch,
    SafeThresholdMismatch
} from "../../../src/lib/LibSafeInvariants.sol";

/// @title LibSafeInvariantsHarness
/// @notice External-call shim around the internal library so
/// `vm.expectRevert` can intercept the typed errors. `vm.expectRevert` only
/// catches reverts from external calls; library `internal` functions inline
/// and would fail the depth check otherwise.
contract LibSafeInvariantsHarness {
    function callAssertImmutableInvariants(IGnosisSafe safe) external view {
        LibSafeInvariants.assertImmutableInvariants(safe);
    }

    function callAssertOwnerSet(IGnosisSafe safe, address[] memory expected) external view {
        LibSafeInvariants.assertOwnerSet(safe, expected);
    }

    function callAssertThreshold(IGnosisSafe safe, uint256 expected) external view {
        LibSafeInvariants.assertThreshold(safe, expected);
    }

    function callAssertAllChecks(IGnosisSafe safe, address[] memory expectedOwners, uint256 expectedThreshold)
        external
        view
    {
        LibSafeInvariants.assertAllChecks(safe, expectedOwners, expectedThreshold);
    }
}

/// @title LibSafeInvariantsTest
/// @notice Live fork tests that exercise each invariant in `LibSafeInvariants`
/// against the production ST0x token-owner Safe on Base, plus one inverted
/// test per invariant that injects drift via `vm.mockCall` and asserts the
/// matching typed error is raised. Uses an unpinned head fork to keep drift
/// detection live; see the rationale in `LibProdSafes.t.sol::selectBaseFork`.
contract LibSafeInvariantsTest is Test {
    /// @notice Wrapper for the production Safe address; reset by every test
    /// after `selectBaseFork` because `vm.createSelectFork` resets cheatcode
    /// state between forks.
    IGnosisSafe internal safe;

    /// @notice External-call harness deployed fresh per test (via fork
    /// rebuild). Kept off the fork via `vm.makePersistent` is unnecessary
    /// here because each test calls `selectBaseFork` before deploying the
    /// harness; the harness is recreated against the active fork.
    LibSafeInvariantsHarness internal harness;

    /// @notice Selects the Base fork at chain head — deliberately unpinned.
    /// Mirrors the precedent set in `LibProdSafes.t.sol::selectBaseFork`
    /// (and `StoxProdV2.t.sol::testProdDeployBaseV2`): pinning would freeze
    /// the invariant assertions against a stale snapshot and let new drift
    /// slip through unnoticed.
    function selectBaseFork() internal {
        vm.createSelectFork(LibRainDeploy.BASE);
        safe = IGnosisSafe(LibProdSafes.STOX_TOKEN_OWNER_SAFE);
        harness = new LibSafeInvariantsHarness();
    }

    /// @notice The immutable-invariant bundle passes against the live Safe
    /// (including the uniform-ownership leg now folded in via
    /// `LibTokenOwnership.assertUniformOwnership`).
    function testAssertImmutableInvariantsLive() external {
        selectBaseFork();
        LibSafeInvariants.assertImmutableInvariants(safe);
    }

    /// @notice The expected 4-owner roster matches the live Safe in order.
    function testAssertOwnerSetLive() external {
        selectBaseFork();
        LibSafeInvariants.assertOwnerSet(safe, LibProdSafes.expectedOwners());
    }

    /// @notice The pre-migration threshold of `1` matches the live Safe.
    function testAssertThresholdLive() external {
        selectBaseFork();
        LibSafeInvariants.assertThreshold(safe, LibProdSafes.STOX_TOKEN_OWNER_SAFE_THRESHOLD_PRE_MIGRATION);
    }

    /// @notice `assertAllChecks` accepts the live Safe at its pre-migration
    /// pinned state (4-owner roster, threshold `1`). This is the call site
    /// the migration script's pre-flight uses.
    function testAssertAllChecksLivePreMigration() external {
        selectBaseFork();
        LibSafeInvariants.assertAllChecks(
            safe, LibProdSafes.expectedOwners(), LibProdSafes.STOX_TOKEN_OWNER_SAFE_THRESHOLD_PRE_MIGRATION
        );
    }

    /// @notice Token-side ownership drift bubbles
    /// `ReceiptVaultOwnerMismatch` through `assertImmutableInvariants`.
    /// Confirms the token-ownership leg is exercised by the immutable
    /// bundle rather than only by direct calls into `LibTokenOwnership`.
    function testInvertedImmutableInvariantsTokenOwnershipDrift() external {
        selectBaseFork();
        address rogueOwner = address(0xBADC0DE);
        address victim = LibTokenOwnership.ST0X_RECEIPT_VAULT_NVDA;
        vm.mockCall(victim, abi.encodeWithSelector(IOwnable.owner.selector), abi.encode(rogueOwner));
        vm.expectRevert(abi.encodeWithSelector(ReceiptVaultOwnerMismatch.selector, victim, address(safe), rogueOwner));
        harness.callAssertImmutableInvariants(safe);
    }

    /// @notice Drift in the proxy runtime codehash trips
    /// `SafeProxyCodehashMismatch`. Simulated by overwriting the proxy
    /// bytecode with a single `INVALID` opcode; `extcodehash` then returns
    /// the hash of `0xFE`, which differs from the pinned codehash.
    function testInvertedCodehashMismatch() external {
        selectBaseFork();
        bytes memory mutatedCode = hex"FE";
        vm.etch(address(safe), mutatedCode);
        bytes32 mutatedCodehash;
        address safeAddr = address(safe);
        assembly ("memory-safe") {
            mutatedCodehash := extcodehash(safeAddr)
        }
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeProxyCodehashMismatch.selector,
                safeAddr,
                LibProdSafes.SAFE_V1_4_1_L2_PROXY_CODEHASH,
                mutatedCodehash
            )
        );
        harness.callAssertImmutableInvariants(safe);
    }

    /// @notice Drift in the singleton pointer (slot 0) trips
    /// `SafeSingletonMismatch`. Simulated by mocking `getStorageAt(0, 1)` to
    /// return a different address.
    function testInvertedSingletonMismatch() external {
        selectBaseFork();
        address impostor = address(0xDEAD);
        vm.mockCall(
            address(safe),
            abi.encodeWithSelector(IGnosisSafe.getStorageAt.selector, uint256(0), uint256(1)),
            abi.encode(abi.encodePacked(bytes32(uint256(uint160(impostor)))))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeSingletonMismatch.selector, address(safe), LibProdSafes.SAFE_V1_4_1_L2_SINGLETON, impostor
            )
        );
        harness.callAssertImmutableInvariants(safe);
    }

    /// @notice Drift in the singleton's bytecode trips
    /// `SafeSingletonBytecodeMismatch`. Simulated by `vm.etch`-ing alien
    /// bytecode at the singleton address — the codehash diverges from
    /// the pinned `SAFE_V1_4_1_L2_SINGLETON_CODEHASH` even though slot
    /// 0 still points at the canonical address.
    /// @dev `vm.etch` on the singleton breaks every delegate-routed
    /// read on the proxy, so the slot-0 fetch is mocked back to the
    /// canonical singleton address. Only the explicit `getStorageAt(0,
    /// 1)` calldata is mocked; later `getStorageAt` reads (guard slot,
    /// fallback handler slot) are unaffected and never execute, because
    /// the bytecode check reverts first.
    function testInvertedSingletonBytecodeMismatch() external {
        selectBaseFork();
        bytes memory bogusCode = hex"60016000526001601ff3";
        vm.etch(LibProdSafes.SAFE_V1_4_1_L2_SINGLETON, bogusCode);
        vm.mockCall(
            address(safe),
            abi.encodeWithSelector(IGnosisSafe.getStorageAt.selector, uint256(0), uint256(1)),
            abi.encode(abi.encodePacked(bytes32(uint256(uint160(LibProdSafes.SAFE_V1_4_1_L2_SINGLETON)))))
        );
        bytes32 expected = LibProdSafes.SAFE_V1_4_1_L2_SINGLETON_CODEHASH;
        bytes32 actual = keccak256(bogusCode);
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeSingletonBytecodeMismatch.selector,
                address(safe),
                LibProdSafes.SAFE_V1_4_1_L2_SINGLETON,
                expected,
                actual
            )
        );
        harness.callAssertImmutableInvariants(safe);
    }

    /// @notice Drift in the singleton's reported version trips
    /// `SafeVersionMismatch`. Simulated by mocking `VERSION()` to return an
    /// unexpected string.
    function testInvertedVersionMismatch() external {
        selectBaseFork();
        string memory bogus = "9.9.9";
        vm.mockCall(address(safe), abi.encodeWithSelector(IGnosisSafe.VERSION.selector), abi.encode(bogus));
        vm.expectRevert(
            abi.encodeWithSelector(SafeVersionMismatch.selector, address(safe), LibProdSafes.SAFE_V1_4_1_VERSION, bogus)
        );
        harness.callAssertImmutableInvariants(safe);
    }

    /// @notice A non-empty module list trips `SafeUnexpectedModules`.
    /// Simulated by mocking the paginated enumeration to return a single
    /// rogue module.
    function testInvertedUnexpectedModules() external {
        selectBaseFork();
        address rogueModule = address(0xBEEF);
        address[] memory mockModules = new address[](1);
        mockModules[0] = rogueModule;
        vm.mockCall(
            address(safe),
            abi.encodeWithSelector(
                IGnosisSafe.getModulesPaginated.selector, LibSafeInvariants.SAFE_MODULES_SENTINEL, uint256(10)
            ),
            abi.encode(mockModules, LibSafeInvariants.SAFE_MODULES_SENTINEL)
        );
        vm.expectRevert(abi.encodeWithSelector(SafeUnexpectedModules.selector, address(safe), rogueModule));
        harness.callAssertImmutableInvariants(safe);
    }

    /// @notice A non-zero guard slot trips `SafeUnexpectedGuard`. Simulated
    /// by mocking `getStorageAt` at the guard slot to return a guard
    /// address.
    function testInvertedUnexpectedGuard() external {
        selectBaseFork();
        address rogueGuard = address(0xCAFE);
        vm.mockCall(
            address(safe),
            abi.encodeWithSelector(
                IGnosisSafe.getStorageAt.selector, uint256(LibSafeInvariants.SAFE_GUARD_STORAGE_SLOT), uint256(1)
            ),
            abi.encode(abi.encodePacked(bytes32(uint256(uint160(rogueGuard)))))
        );
        vm.expectRevert(abi.encodeWithSelector(SafeUnexpectedGuard.selector, address(safe), rogueGuard));
        harness.callAssertImmutableInvariants(safe);
    }

    /// @notice Drift in the fallback handler slot trips
    /// `SafeFallbackHandlerMismatch`. Simulated by mocking `getStorageAt` at
    /// the fallback handler slot to return a different address.
    function testInvertedFallbackHandlerMismatch() external {
        selectBaseFork();
        address impostor = address(0xFACE);
        vm.mockCall(
            address(safe),
            abi.encodeWithSelector(
                IGnosisSafe.getStorageAt.selector,
                uint256(LibSafeInvariants.SAFE_FALLBACK_HANDLER_STORAGE_SLOT),
                uint256(1)
            ),
            abi.encode(abi.encodePacked(bytes32(uint256(uint160(impostor)))))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeFallbackHandlerMismatch.selector,
                address(safe),
                LibProdSafes.SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER,
                impostor
            )
        );
        harness.callAssertImmutableInvariants(safe);
    }

    /// @notice Owner count drift trips `SafeOwnerCountMismatch`. The caller
    /// passes a 3-entry array against the live 4-owner Safe.
    function testInvertedOwnerCountMismatch() external {
        selectBaseFork();
        address[] memory truncated = new address[](3);
        truncated[0] = LibProdSafes.STOX_TOKEN_OWNER_SAFE_OWNER_1;
        truncated[1] = LibProdSafes.STOX_TOKEN_OWNER_SAFE_OWNER_2;
        truncated[2] = LibProdSafes.STOX_TOKEN_OWNER_SAFE_OWNER_3;
        vm.expectRevert(abi.encodeWithSelector(SafeOwnerCountMismatch.selector, address(safe), uint256(3), uint256(4)));
        harness.callAssertOwnerSet(safe, truncated);
    }

    /// @notice Owner address drift trips `SafeOwnerMismatch`. The caller
    /// supplies an array with the correct length but a swapped owner at
    /// index 1.
    function testInvertedOwnerMismatch() external {
        selectBaseFork();
        address[] memory swapped = LibProdSafes.expectedOwners();
        address impostor = address(0xC0FFEE);
        swapped[1] = impostor;
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeOwnerMismatch.selector,
                address(safe),
                uint256(1),
                impostor,
                LibProdSafes.STOX_TOKEN_OWNER_SAFE_OWNER_2
            )
        );
        harness.callAssertOwnerSet(safe, swapped);
    }

    /// @notice Threshold drift trips `SafeThresholdMismatch`. Caller asks
    /// for `3` against a live threshold of `1`.
    function testInvertedThresholdMismatch() external {
        selectBaseFork();
        vm.expectRevert(abi.encodeWithSelector(SafeThresholdMismatch.selector, address(safe), uint256(3), uint256(1)));
        harness.callAssertThreshold(safe, 3);
    }
}
