// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {LibDecimalFloat} from "rain-math-float-0.1.1/src/lib/LibDecimalFloat.sol";
import {ACTION_TYPE_STOCK_SPLIT_V1} from "../../../src/interface/ICorporateActionsV1.sol";
import {LibStockSplit} from "../../../src/lib/LibStockSplit.sol";
import {TestStoxReceiptVault} from "./TestStoxReceiptVault.sol";

/// Regression guards for Protofire H01 (report `st0x.deploy 5.0`, July 2026,
/// audited at `ed767bf2`): "Raw OZ `_totalSupply` can block minting".
///
/// A stock split rewrites holder balances directly through
/// `LibERC20Storage.setUnderlyingBalance`, bypassing `_mint` / `_burn`. Before
/// the fix, OZ's own `_totalSupply` accumulator was never adjusted to match, so
/// it drifted below the true sum of balances. OZ subtracts from that
/// accumulator **unchecked** on burn and adds to it **checked** on mint, so the
/// drift eventually wrapped the slot to ~2**256 and every subsequent mint
/// reverted with `Panic(0x11)` — while `totalSupply()`, `balanceOf()` and all
/// events kept reporting correct, mutually consistent values.
///
/// The invariant these tests pin is OZ's own:
///
///   `_totalSupply == Σ _balances`
///
/// which is a *different* quantity from the rebase-aware `totalSupply()`.
/// During partial migration the raw slot tracks the sum of *stored* balances
/// while `totalSupply()` projects unmigrated pots forward through every
/// completed multiplier; the two converge once every holder has migrated.
contract StoxReceiptVaultRawTotalSupplyTest is Test {
    TestStoxReceiptVault internal vault;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);

    function setUp() public {
        vault = new TestStoxReceiptVault();
        vm.warp(1000);
    }

    function _splitParams(int256 multiplier) internal pure returns (bytes memory) {
        return LibStockSplit.encodeParametersV1(LibDecimalFloat.packLossless(multiplier, 0));
    }

    /// The exact scenario tabulated in the H01 finding.
    ///
    /// Alice mints 1000, a 2x split completes, Alice redeems 1002. Before the
    /// fix the raw slot went `1000 - 1002` and wrapped to `2**256 - 2`.
    function testH01RedeemAcrossSplitDoesNotWrapRawTotalSupply() external {
        vault.publicUpdate(address(0), ALICE, 1000);
        assertEq(vault.rawTotalSupply(), 1000, "raw slot tracks the mint");

        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);

        assertEq(vault.balanceOf(ALICE), 2000, "2x split doubles Alice's balance");
        assertEq(vault.totalSupply(), 2000, "rebase-aware supply doubles too");

        // Redeem more than the pre-split supply. This is the step that
        // underflowed OZ's accumulator before the fix.
        vault.publicUpdate(ALICE, address(0), 1002);

        assertEq(vault.balanceOf(ALICE), 998, "Alice keeps 2000 - 1002");
        assertEq(vault.totalSupply(), 998, "reported supply follows");
        assertEq(vault.rawTotalSupply(), 998, "raw OZ slot must not wrap");
        assertEq(vault.rawTotalSupply(), vault.rawStoredBalance(ALICE), "OZ invariant: _totalSupply == sum of balances");
    }

    /// The impact the finding describes: after the wrap, new issuance is
    /// permanently capped because OZ's mint path adds to the raw slot with
    /// overflow checks enabled. Post-fix, minting after the redeem is
    /// unremarkable.
    function testH01MintAfterRedeemAcrossSplitStillSucceeds() external {
        vault.publicUpdate(address(0), ALICE, 1000);
        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(2));
        vm.warp(2000);
        vault.publicUpdate(ALICE, address(0), 1002);

        // Pre-fix this reverted with Panic(0x11) — arithmetic overflow — because
        // the raw slot sat at 2**256 - 2.
        vault.publicUpdate(address(0), BOB, 500);

        assertEq(vault.balanceOf(BOB), 500, "Bob receives exactly the minted amount");
        assertEq(vault.totalSupply(), 1498, "998 + 500");
        assertEq(vault.rawTotalSupply(), 1498, "raw slot keeps pace with the mint");
        assertEq(
            vault.rawTotalSupply(),
            vault.rawStoredBalance(ALICE) + vault.rawStoredBalance(BOB),
            "OZ invariant holds across both holders"
        );
    }

    /// A reverse split shrinks balances; the raw slot must follow downward
    /// rather than stranding the difference.
    function testRawTotalSupplyFollowsReverseSplit() external {
        vault.publicUpdate(address(0), ALICE, 1000);

        // 1-for-2 reverse split.
        vault.publicSchedule(
            ACTION_TYPE_STOCK_SPLIT_V1,
            1500,
            LibStockSplit.encodeParametersV1(
                LibDecimalFloat.div(LibDecimalFloat.packLossless(1, 0), LibDecimalFloat.packLossless(2, 0))
            )
        );
        vm.warp(2000);

        // Touch Alice so the lazy migration actually runs.
        vault.publicUpdate(ALICE, BOB, 100);

        assertEq(
            vault.rawTotalSupply(),
            vault.rawStoredBalance(ALICE) + vault.rawStoredBalance(BOB),
            "OZ invariant holds after a reverse split"
        );
    }

    /// Migration is lazy, so the raw slot must stay consistent with the sum of
    /// *stored* balances at every step, including while some holders are still
    /// unmigrated.
    function testRawTotalSupplyMatchesStoredBalancesDuringPartialMigration() external {
        vault.publicUpdate(address(0), ALICE, 1000);
        vault.publicUpdate(address(0), BOB, 400);

        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(3));
        vm.warp(2000);

        // Touch Alice only — Bob stays unmigrated.
        vault.publicUpdate(ALICE, address(0), 1);

        assertEq(
            vault.rawTotalSupply(),
            vault.rawStoredBalance(ALICE) + vault.rawStoredBalance(BOB),
            "OZ invariant holds mid-migration"
        );

        // Now migrate Bob too.
        vault.publicUpdate(BOB, address(0), 1);

        assertEq(
            vault.rawTotalSupply(),
            vault.rawStoredBalance(ALICE) + vault.rawStoredBalance(BOB),
            "OZ invariant holds once fully migrated"
        );
        assertEq(vault.totalSupply(), vault.rawTotalSupply(), "supplies converge after full migration");
    }

    /// Fuzz the whole shape: arbitrary holdings, an arbitrary integer split and
    /// an arbitrary burn must never break OZ's accumulator invariant.
    function testFuzzRawTotalSupplyInvariantAcrossSplitAndBurn(uint64 aliceAmount, uint64 bobAmount, uint8 multiplier)
        external
    {
        aliceAmount = uint64(bound(aliceAmount, 1, type(uint64).max));
        bobAmount = uint64(bound(bobAmount, 1, type(uint64).max));
        multiplier = uint8(bound(multiplier, 1, 10));

        vault.publicUpdate(address(0), ALICE, aliceAmount);
        vault.publicUpdate(address(0), BOB, bobAmount);

        vault.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, 1500, _splitParams(int256(uint256(multiplier))));
        vm.warp(2000);

        // Burn everything Alice holds post-split.
        vault.publicUpdate(ALICE, address(0), vault.balanceOf(ALICE));

        assertEq(
            vault.rawTotalSupply(),
            vault.rawStoredBalance(ALICE) + vault.rawStoredBalance(BOB),
            "OZ invariant survives an arbitrary split then burn"
        );
    }
}
