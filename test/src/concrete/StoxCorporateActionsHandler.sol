// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {Float, LibDecimalFloat} from "rain-math-float-0.1.1/src/lib/LibDecimalFloat.sol";
import {ACTION_TYPE_STOCK_SPLIT_V1} from "../../../src/interface/ICorporateActionsV1.sol";
import {NODE_NONE} from "../../../src/lib/LibCorporateActionNode.sol";
import {LibStockSplit} from "../../../src/lib/LibStockSplit.sol";
import {InvariantVault} from "./InvariantVault.sol";
import {InvariantReceipt} from "./InvariantReceipt.sol";

/// @dev Handler for the corporate-actions invariant suite. Foundry's invariant
/// fuzzer targets this contract's external functions; each call drives one
/// operation against the vault with bounded, fuzzer-supplied inputs. After
/// every operation that migrates an account, the handler asserts the cursor-
/// equality invariant inline so violations surface at the offending call
/// rather than at the periodic invariant sweep.
///
/// Actors: a fixed set of 5 addresses plus the zero address (for mint/burn).
/// Multipliers: bounded to {1, 2, 3} (and their reciprocals via fractional
/// form) to keep Float precision inside well-tested territory without losing
/// the fractional vs integer distinction.
/// Amounts: bounded per-op against current balances to avoid OZ underflow
/// reverts that would mask real bugs.
contract StoxCorporateActionsHandler is Test {
    InvariantVault public immutable VAULT;
    InvariantReceipt public immutable RECEIPT;

    /// @dev Fixed set of actors the handler cycles through. Each actor is
    /// paired with a fixed receipt id (`i + 1`) for the proportionality
    /// invariant: `deposit` and `withdraw` create / destroy matching amounts
    /// of both the share balance and the receipt at that actor's id, so
    /// `vault.balanceOf(actor_i) == receipt.balanceOf(actor_i, i+1)` holds
    /// at every post-handler-call checkpoint. Share-only transfers would
    /// break this proportionality (shares fungible, receipts per-id), so
    /// the handler deliberately does not expose them.
    address[5] public actors;

    /// @dev Total number of mints executed (for ghost-variable assertions).
    uint256 public totalMinted;
    /// @dev Total number of burns executed.
    uint256 public totalBurned;
    /// @dev Track the most recent share-side cursor value per actor, to
    /// verify monotonicity (invariant 3).
    mapping(address => uint256) public lastSeenCursor;
    /// @dev Track the most recent receipt-side cursor per (actor, id) pair
    /// for the receipt cursor monotonicity invariant.
    mapping(address => mapping(uint256 => uint256)) public lastSeenReceiptCursor;

    constructor(InvariantVault vault_, InvariantReceipt receipt_) {
        VAULT = vault_;
        RECEIPT = receipt_;
        actors[0] = address(0xA11CE);
        actors[1] = address(0xB0B);
        actors[2] = address(0xCA401);
        actors[3] = address(0xDAFE);
        actors[4] = address(0xEFFE);
        // Start time past 0 so `block.timestamp > 0` and fresh effectiveTime
        // values can land strictly in the future.
        vm.warp(1000);
    }

    /// @dev Each actor has a fixed receipt id = index + 1. Id 0 is avoided
    /// (reserved for "no id" semantics in various tests).
    function _actorId(uint256 actorIndex) internal pure returns (uint256) {
        return actorIndex + 1;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _asFloat(int256 coefficient, int256 exponent) internal pure returns (Float) {
        return LibDecimalFloat.packLossless(coefficient, exponent);
    }

    /// @dev Bounded set of stock split multipliers used by schedule. Fractional
    /// reverse splits (1/3, 1/2) are produced by `div(packLossless(1,0),
    /// packLossless(n,0))`.
    function _multiplier(uint256 seed) internal pure returns (bytes memory) {
        uint256 bucket = seed % 6;
        if (bucket == 0) return LibStockSplit.encodeParametersV1(_asFloat(2, 0));
        if (bucket == 1) return LibStockSplit.encodeParametersV1(_asFloat(3, 0));
        if (bucket == 2) return LibStockSplit.encodeParametersV1(_asFloat(1, 0)); // 1x — a no-op split (valid)
        if (bucket == 3) {
            return LibStockSplit.encodeParametersV1(LibDecimalFloat.div(_asFloat(1, 0), _asFloat(2, 0)));
        }
        if (bucket == 4) {
            return LibStockSplit.encodeParametersV1(LibDecimalFloat.div(_asFloat(1, 0), _asFloat(3, 0)));
        }
        // bucket 5: another 2x (slight weighting toward common cases)
        return LibStockSplit.encodeParametersV1(_asFloat(2, 0));
    }

    /// @dev Schedule a stock split at a bounded future time. Time is drawn
    /// from a small window ahead of `block.timestamp` so multiple scheduled
    /// actions end up in mixed order inside the list.
    function schedule(uint256 multiplierSeed, uint8 timeDelta) external {
        // time in [1, 256] seconds in the future.
        uint64 effectiveTime = uint64(block.timestamp + 1 + (uint256(timeDelta) % 256));
        bytes memory parameters = _multiplier(multiplierSeed);
        VAULT.publicSchedule(ACTION_TYPE_STOCK_SPLIT_V1, effectiveTime, parameters);
    }

    /// @dev Cancel a scheduled action. Bounded to the current nodes array
    /// length so it hits legitimate indices most of the time; indices that
    /// point at already-cancelled or already-completed nodes revert cleanly
    /// (caught by the inline try / ignore pattern).
    function cancel(uint256 indexSeed) external {
        uint256 len = VAULT.nodesLength();
        if (len <= 1) return; // only sentinel; nothing to cancel
        uint256 actionIndex = (indexSeed % (len - 1)) + 1; // in [1, len-1]
        // forge-lint: disable-next-line(unchecked-call)
        try VAULT.publicCancel(actionIndex) {} catch {}
    }

    /// @dev Advance block.timestamp by a bounded delta so scheduled actions
    /// cross into the past and `fold()` picks them up on the next _update.
    function warp(uint8 delta) external {
        vm.warp(block.timestamp + 1 + uint256(delta));
    }

    /// @dev Deposit — mints matching amounts of share and receipt to an
    /// actor at their assigned id. Models the real vault flow where a
    /// deposit creates both a share balance and a receipt in lockstep.
    /// This is the only mint path in the handler so that the
    /// share-receipt proportionality invariant holds at every checkpoint.
    function deposit(uint256 actorSeed, uint64 amountSeed) external {
        uint256 actorIndex = actorSeed % actors.length;
        address to = actors[actorIndex];
        uint256 id = _actorId(actorIndex);
        uint256 amount = uint256(amountSeed) % 1e24 + 1;

        // Share side.
        VAULT.publicUpdate(address(0), to, amount);

        // Receipt side — manager-authorized mint of the same amount at the
        // actor's assigned id. `managerMint(sender, account, id, amount, data)`.
        vm.prank(address(VAULT));
        RECEIPT.managerMint(address(VAULT), to, id, amount, "");

        totalMinted += amount;
        _assertCursorInvariant(to);
        _assertReceiptCursorInvariant(to, id);
        _recordCursor(to);
        _recordReceiptCursor(to, id);
    }

    /// @dev Withdraw — burns matching amounts of share and receipt from an
    /// actor at their assigned id. Capped at the actor's current effective
    /// balance (which must match the receipt balance by proportionality)
    /// so OZ does not underflow.
    function withdraw(uint256 actorSeed, uint64 amountSeed) external {
        uint256 actorIndex = actorSeed % actors.length;
        address from = actors[actorIndex];
        uint256 id = _actorId(actorIndex);

        uint256 effective = VAULT.balanceOf(from);
        if (effective == 0) return;
        uint256 amount = uint256(amountSeed) % (effective + 1);
        if (amount == 0) return;

        // Share side.
        VAULT.publicUpdate(from, address(0), amount);

        // Receipt side.
        vm.prank(address(VAULT));
        RECEIPT.managerBurn(address(VAULT), from, id, amount, "");

        totalBurned += amount;
        _assertCursorInvariant(from);
        _assertReceiptCursorInvariant(from, id);
        _recordCursor(from);
        _recordReceiptCursor(from, id);
    }

    /// @dev Touch an actor by performing a zero-value self-deposit-equivalent
    /// on both sides. Exercises cursor-only advancement paths (both share
    /// and receipt).
    function touch(uint256 actorSeed) external {
        uint256 actorIndex = actorSeed % actors.length;
        address a = actors[actorIndex];
        uint256 id = _actorId(actorIndex);

        // Share side — zero-value self-send.
        VAULT.publicUpdate(a, a, 0);

        // Receipt side — zero-value self-transfer via manager path.
        vm.prank(address(VAULT));
        RECEIPT.managerTransferFrom(address(VAULT), a, a, id, 0, "");

        _assertCursorInvariant(a);
        _assertReceiptCursorInvariant(a, id);
        _recordCursor(a);
        _recordReceiptCursor(a, id);
    }

    // -----------------------------------------------------------------------
    // Ghost assertions / recording

    /// @dev Assert cursor invariant #4: after any migration, the actor's
    /// cursor equals the global `totalSupplyLatestCursor`.
    function _assertCursorInvariant(address a) internal view {
        assertEq(
            VAULT.migrationCursor(a),
            VAULT.totalSupplyLatestCursor(),
            "invariant 4: cursor(actor) == totalSupplyLatestCursor after migrateAccount"
        );
    }

    /// @dev Record the actor's cursor to check monotonicity (invariant 3).
    /// Cursor IDs are allocation indices, not chronological positions — a
    /// later-scheduled action with an earlier effectiveTime is inserted
    /// before older actions in the list, so a valid migration can move a
    /// cursor to a numerically lower id. Monotonicity is therefore defined
    /// in LIST order (forward along `next` pointers), not numeric order.
    function _recordCursor(address a) internal {
        uint256 current = VAULT.migrationCursor(a);
        uint256 last = lastSeenCursor[a];
        assertTrue(
            cursorReachableForward(last, current), "invariant 3: per-actor cursor must advance forward in list order"
        );
        lastSeenCursor[a] = current;
    }

    /// @dev After any migration on the receipt, the (holder, id) cursor
    /// equals the vault's `totalSupplyLatestCursor`. A receipt cursor that
    /// drifted behind would cause `LibReceiptRebase.migratedBalance` to
    /// silently re-apply multipliers to an already-rasterized stored
    /// balance on the next read.
    function _assertReceiptCursorInvariant(address a, uint256 id) internal view {
        assertEq(
            RECEIPT.holderIdCursor(a, id),
            VAULT.totalSupplyLatestCursor(),
            "receipt invariant: holderIdCursor == totalSupplyLatestCursor after migrateHolderId"
        );
    }

    /// @dev Record the receipt-side cursor to check per-(holder, id)
    /// monotonicity. Same list-order semantics as the share side: a
    /// later-scheduled earlier-effective split can land at a numerically
    /// smaller node id but still be reachable forward from `last`, so a
    /// raw `assertGe` would falsely flag a valid schedule. Walk forward
    /// via `next` pointers instead.
    function _recordReceiptCursor(address a, uint256 id) internal {
        uint256 current = RECEIPT.holderIdCursor(a, id);
        uint256 last = lastSeenReceiptCursor[a][id];
        assertTrue(
            cursorReachableForward(last, current),
            "receipt invariant: per-(holder, id) cursor must advance forward in list order"
        );
        lastSeenReceiptCursor[a][id] = current;
    }

    /// @dev True iff `current` is `last` itself or reachable by walking
    /// `next` pointers starting from `last`. Walk is bounded by
    /// `nodesLength` so a cycle (violation of invariant 1) does not hang.
    /// External so framework-level invariants can call it too.
    function cursorReachableForward(uint256 last, uint256 current) public view returns (bool) {
        if (last == current) return true;

        uint256 len = VAULT.nodesLength();
        uint256 cursor = last;
        for (uint256 i = 0; i < len && cursor != NODE_NONE; i++) {
            cursor = VAULT.getNode(cursor).next;
            if (cursor == current) return true;
        }
        return false;
    }

    function actorCount() external pure returns (uint256) {
        return 5;
    }

    function actor(uint256 i) external view returns (address) {
        return actors[i];
    }
}
