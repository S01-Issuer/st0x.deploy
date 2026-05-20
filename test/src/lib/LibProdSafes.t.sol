// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibProdSafes} from "../../../src/lib/LibProdSafes.sol";
import {IGnosisSafe} from "../../../src/interface/IGnosisSafe.sol";
import {LibRainDeploy} from "rain-deploy-0.1.2/src/lib/LibRainDeploy.sol";

/// @title LibProdSafesTest
/// @notice Live fork tests that bind the pinned constants in `LibProdSafes`
/// to the real ST0x token-owner Safe on Base. Any drift between the file
/// and on-chain reality (singleton swap, threshold change, owner roster
/// edit, proxy bytecode update, etc.) trips CI. These tests are the source
/// of truth for the constants used by every downstream migration script.
contract LibProdSafesTest is Test {
    /// @notice Selects the Base fork at chain head — deliberately unpinned.
    ///
    /// The Safe constants in `LibProdSafes` are intended to track the
    /// current production owner-set and threshold. A pinned historical
    /// block would freeze the assertion against a stale snapshot and let
    /// the file silently drift from reality between bumps; an unpinned
    /// head fork makes the next CI run the canary for any owner-set,
    /// threshold, singleton or fallback-handler change.
    ///
    /// We intentionally do NOT use `LibTestProd.createSelectForkBase(vm)`
    /// here. That helper pins
    /// `LibTestProd.PROD_TEST_BLOCK_NUMBER_BASE = 45775000`, which predates
    /// the 2026-05-18 `RemovedOwner` event at block 46156528. Asserting the
    /// post-removal 4-owner state against the pinned block would fail, and
    /// bumping the shared constant would invalidate every other prod pin
    /// in the repo (`LibProdTokensBase.t.sol`,
    /// `StoxWrappedTokenVaultV1.prod.base.t.sol`, etc.). The repo already
    /// uses the unpinned head-fork pattern for drift detectors — see
    /// `StoxProdV2.t.sol::testProdDeployBaseV2`.
    ///
    /// Resolves the `base` RPC alias from `foundry.toml` (which expands
    /// `${BASE_RPC_URL}`), matching the convention used by every other
    /// fork test in this repo.
    function selectBaseFork() internal {
        vm.createSelectFork(LibRainDeploy.BASE);
    }

    /// @notice The Safe responds to every function declared on
    /// `IGnosisSafe`. We do not assert specific values for read-only calls
    /// here (other tests cover that) — we only assert the ABI surface
    /// resolves, i.e. each call returns rather than reverts.
    function testIGnosisSafeAbiResolvesOnLiveSafe() external {
        selectBaseFork();
        IGnosisSafe safe = IGnosisSafe(LibProdSafes.STOX_TOKEN_OWNER_SAFE);

        // Every read selector must succeed (return is checked
        // structurally; concrete values are asserted in other tests).
        safe.getThreshold();
        safe.getOwners();
        safe.nonce();
        safe.getModulesPaginated(address(0x1), 10);
        safe.getStorageAt(0, 1);
        safe.VERSION();

        // `getTransactionHash` is pure-view from a no-op transaction; it
        // must resolve without revert.
        safe.getTransactionHash(address(safe), 0, "", 0, 0, 0, 0, address(0), address(0), safe.nonce());
    }

    /// @notice `getOwners()` returns exactly the addresses pinned in
    /// `LibProdSafes.expectedOwners()` in the same order. Exercises the
    /// post-2026-05-18 4-owner roster against the chain head.
    function testGetOwnersMatchesExpected() external {
        selectBaseFork();
        IGnosisSafe safe = IGnosisSafe(LibProdSafes.STOX_TOKEN_OWNER_SAFE);

        address[] memory actual = safe.getOwners();
        address[] memory expected = LibProdSafes.expectedOwners();

        assertEq(actual.length, expected.length, "owner count drift");
        for (uint256 i = 0; i < expected.length; i++) {
            assertEq(actual[i], expected[i], "owner address drift");
        }
    }

    /// @notice The pre-RAI-296 threshold is `1`. (Still `1` post-roster-
    /// reduction; RAI-296 will bump it to `3` against the 4-owner set.)
    function testGetThresholdIsPreRai296() external {
        selectBaseFork();
        IGnosisSafe safe = IGnosisSafe(LibProdSafes.STOX_TOKEN_OWNER_SAFE);

        assertEq(safe.getThreshold(), LibProdSafes.STOX_TOKEN_OWNER_SAFE_THRESHOLD_PRE_RAI296);
    }

    /// @notice The proxy runtime codehash matches the pinned Safe v1.4.1
    /// L2 proxy codehash. This is the strongest single check against the
    /// Safe address being silently swapped under us.
    function testProxyCodehashMatches() external {
        selectBaseFork();
        bytes32 actual;
        address safe = LibProdSafes.STOX_TOKEN_OWNER_SAFE;
        assembly ("memory-safe") {
            actual := extcodehash(safe)
        }
        assertEq(actual, LibProdSafes.SAFE_V1_4_1_L2_PROXY_CODEHASH);
    }
}
