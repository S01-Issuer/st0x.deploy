// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std/Test.sol";
import {StoxReceipt} from "../../../src/concrete/StoxReceipt.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {Float, LibDecimalFloat} from "rain.math.float/lib/LibDecimalFloat.sol";
import {ICorporateActionsV1} from "../../../src/interface/ICorporateActionsV1.sol";
import {CompletionFilter} from "../../../src/lib/LibCorporateActionNode.sol";
import {ACTION_TYPE_STOCK_SPLIT_V1} from "../../../src/lib/LibCorporateAction.sol";
import {
    LibCorporateActionReceipt,
    CORPORATE_ACTION_RECEIPT_STORAGE_LOCATION
} from "../../../src/lib/LibCorporateActionReceipt.sol";
import {LibERC1155Storage} from "../../../src/lib/LibERC1155Storage.sol";
import {IReceiptManagerV2} from "rain.vats/interface/IReceiptManagerV2.sol";

contract StoxReceiptTest is Test {
    /// Constructor disables initializers on the implementation.
    function testConstructorDisablesInitializers() external {
        StoxReceipt impl = new StoxReceipt();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize(abi.encode(address(1)));
    }
}

/// @dev Mock vault combining `ICorporateActionsV1` (corporate-action read
/// surface) and `IReceiptManagerV2` (receipt transfer authorizer). The
/// receipt's base `_update` calls `s.manager.authorizeReceiptTransfer3(...)`
/// before applying the transfer, and our override reads multipliers via
/// `this.manager()` cast to `ICorporateActionsV1`. A single mock serving
/// both interfaces matches the real topology where the vault is a single
/// contract implementing both.
///
/// `IReceiptManagerV2` also requires `symbol()`, `decimals()` etc. via the
/// Receipt's `_vaultShareSymbol` helper. In tests we only call `balanceOf`
/// and `_update` paths that don't hit `uri()`, so the stub implementations
/// below are minimal.
contract MockVault is ICorporateActionsV1, IReceiptManagerV2 {
    bytes[] internal splits; // splits[i-1] is the parameters blob for cursor i

    /// Authorize hook — always allows the transfer in tests.
    function authorizeReceiptTransfer3(address, address, address, uint256[] memory, uint256[] memory)
        external
        pure
        override
    {}

    function addSplit(Float multiplier) external {
        splits.push(abi.encode(multiplier));
    }

    // ICorporateActionsV1

    function nextOfType(uint256 cursor, uint256 mask, CompletionFilter filter)
        external
        view
        override
        returns (uint256 nextCursor, uint256 actionType, uint64 effectiveTime)
    {
        require(mask == ACTION_TYPE_STOCK_SPLIT_V1, "mock: unexpected mask");
        require(filter == CompletionFilter.COMPLETED, "mock: unexpected filter");
        uint256 candidate = cursor + 1;
        if (candidate > splits.length) {
            return (0, 0, 0);
        }
        return (candidate, ACTION_TYPE_STOCK_SPLIT_V1, 1);
    }

    function getActionParameters(uint256 cursor) external view override returns (bytes memory) {
        require(cursor >= 1 && cursor <= splits.length, "mock: cursor out of range");
        return splits[cursor - 1];
    }

    function scheduleCorporateAction(bytes32, uint64, bytes calldata) external pure override returns (uint256) {
        revert("mock");
    }

    function cancelCorporateAction(uint256) external pure override {
        revert("mock");
    }

    function completedActionCount() external view override returns (uint256) {
        return splits.length;
    }

    function latestActionOfType(uint256, CompletionFilter) external pure override returns (uint256, uint256, uint64) {
        revert("mock");
    }

    function earliestActionOfType(uint256, CompletionFilter) external pure override returns (uint256, uint256, uint64) {
        revert("mock");
    }

    function prevOfType(uint256, uint256, CompletionFilter) external pure override returns (uint256, uint256, uint64) {
        revert("mock");
    }

    /// Expose minimal IERC20Metadata surface that `Receipt._vaultShareSymbol`
    /// calls via `IERC20Metadata(address(manager)).symbol()`. Not actually
    /// used in our tests (we never hit `uri()`), but the `_update` path may
    /// touch it if anything inspects name/symbol. Stubbed for safety.
    function symbol() external pure returns (string memory) {
        return "TEST";
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function asset() external view returns (address) {
        return address(this);
    }
}

/// @dev Test-only subclass that exposes an `initialize` path bypassing the
/// `initializer` modifier of the real `Receipt`, so tests can directly drive
/// a `StoxReceipt` against our mock. `publicManagerMint` / `publicManagerBurn`
/// go through the vault-as-manager path.
contract TestStoxReceipt is StoxReceipt {
    function testInit(address vaultAddr) external {
        // Bypass ethgild's `initializer` lock by writing the manager slot
        // directly. We're initializing a fresh deployment in-test, so the
        // one-shot initializer guard is irrelevant for our purposes.
        bytes32 slot = 0xe5444a702a2f437387f4eb075af275e349f1dba9a68923d27352f035d01dc200;
        assembly {
            sstore(slot, vaultAddr)
        }
    }

    /// Expose direct storage read so tests can inspect the raw stored
    /// balance (pre-rebase) without going through the `balanceOf` override.
    function rawStoredBalance(address account, uint256 id) external view returns (uint256) {
        return LibERC1155Storage.underlyingBalance(account, id);
    }

    /// Expose the cursor for assertions.
    function holderIdCursor(address account, uint256 id) external view returns (uint256) {
        return LibCorporateActionReceipt.getStorage().accountIdCursor[account][id];
    }
}

contract StoxReceiptRebaseIntegrationTest is Test {
    TestStoxReceipt internal receipt;
    MockVault internal vault;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);

    uint256 internal constant ID_A = 1;
    uint256 internal constant ID_B = 2;

    function setUp() public {
        vault = new MockVault();
        receipt = new TestStoxReceipt();
        receipt.testInit(address(vault));
    }

    function _splitParams(int256 multiplier) internal {
        vault.addSplit(LibDecimalFloat.packLossless(multiplier, 0));
    }

    function _fractionalParams(int256 num, int256 denom) internal {
        vault.addSplit(
            LibDecimalFloat.div(LibDecimalFloat.packLossless(num, 0), LibDecimalFloat.packLossless(denom, 0))
        );
    }

    // -----------------------------------------------------------------------
    // Storage-slot pin tests

    /// The hardcoded ERC-7201 slot constant for LibCorporateActionReceipt
    /// matches its documented derivation formula.
    function testReceiptCorporateActionSlotMatchesDerivation() external pure {
        bytes32 expected = keccak256(abi.encode(uint256(keccak256("rain.storage.corporate-action-receipt.1")) - 1))
            & ~bytes32(uint256(0xff));
        assertEq(
            CORPORATE_ACTION_RECEIPT_STORAGE_LOCATION,
            expected,
            "receipt corporate-action storage slot must match derivation"
        );
    }

    /// Layout pin: each field of `CorporateActionReceiptStorage` lives at
    /// its expected offset from the namespace base. Must be extended for
    /// every later PR that appends a new field. See the DO NOT REORDER
    /// comment on the struct.
    function testReceiptStorageLayoutPin() external {
        // accountIdCursor is at offset 0 within the struct. Poke a key via
        // the library accessor (indirectly by setting a cursor through a
        // full mint+split+touch path) and assert the entry lives at the
        // expected derived slot.
        bytes32 base = CORPORATE_ACTION_RECEIPT_STORAGE_LOCATION;

        // Use a sentinel holder + id.
        address holder = address(0xBEEF);
        uint256 id = 0xCAFE;

        // Write a sentinel directly to the outer mapping slot at offset 0,
        // then read through the library accessor to verify that offset 0
        // is the accountIdCursor mapping base.
        bytes32 outerSlot = keccak256(abi.encode(holder, base));
        bytes32 entrySlot = keccak256(abi.encode(id, outerSlot));
        vm.store(address(receipt), entrySlot, bytes32(uint256(0x12345)));

        assertEq(
            receipt.holderIdCursor(holder, id),
            0x12345,
            "accountIdCursor mapping must be at offset 0 in CorporateActionReceiptStorage"
        );
    }

    // -----------------------------------------------------------------------
    // Rebase integration — happy path

    /// Before any splits, balanceOf returns the raw stored balance.
    function testBalanceOfNoSplits() external {
        // Mint directly to Alice via vault-as-manager path.
        _mint(ALICE, ID_A, 100);
        assertEq(receipt.balanceOf(ALICE, ID_A), 100);
    }

    /// After a 2x split, balanceOf returns the rebased balance even before
    /// migration actually runs (view-only multiplier application).
    function testBalanceOfAfterSplitPreMigration() external {
        _mint(ALICE, ID_A, 100);
        _splitParams(2);
        assertEq(receipt.balanceOf(ALICE, ID_A), 200, "view-only rebase must reflect the split");
        // Stored balance hasn't actually changed yet (no touch).
        assertEq(receipt.rawStoredBalance(ALICE, ID_A), 100, "rasterize is lazy");
    }

    /// A touch via zero-value manager transfer migrates the stored balance.
    function testMigrationOnTransferRasterizesStoredBalance() external {
        _mint(ALICE, ID_A, 100);
        _splitParams(2);

        // Self-transfer of 0 — triggers _update on (Alice, ID_A) from both
        // sides and rasterizes Alice's stored balance.
        _transfer(ALICE, ALICE, ID_A, 0);

        assertEq(receipt.rawStoredBalance(ALICE, ID_A), 200, "stored balance rasterized");
        assertEq(receipt.balanceOf(ALICE, ID_A), 200);
        assertEq(receipt.holderIdCursor(ALICE, ID_A), 1, "cursor advanced to first split");
    }

    /// Mint to a fresh recipient after a completed split credits exactly
    /// the minted amount, not multiplied by the split. Without the
    /// zero-balance cursor-advancement guard, the recipient's freshly-
    /// written post-rebase balance would be re-multiplied on the next
    /// `balanceOf` read.
    function testMintToFreshRecipientAfterSplitDoesNotInflate() external {
        // Pre-existing supply so the split has something to rebase.
        _mint(BOB, ID_A, 1000);

        _splitParams(2);

        // Alice mints 100 AFTER the split. Should receive exactly 100.
        _mint(ALICE, ID_A, 100);
        assertEq(receipt.balanceOf(ALICE, ID_A), 100, "fresh recipient must not over-multiply on mint");
    }

    /// Transfer to a fresh recipient after a completed split: recipient
    /// receives the transferred amount exactly, not multiplied.
    function testTransferToFreshRecipientAfterSplitDoesNotInflate() external {
        _mint(BOB, ID_A, 50);
        _splitParams(2);

        // Bob's effective balance is now 100. Transfer all 100 to Alice.
        _transfer(BOB, ALICE, ID_A, 100);

        assertEq(receipt.balanceOf(ALICE, ID_A), 100, "recipient got exactly the transferred amount");
        assertEq(receipt.balanceOf(BOB, ID_A), 0, "Bob is now empty");
    }

    /// Per-(holder, id) cursor independence: Alice's cursor for ID_A
    /// advances without touching her cursor for ID_B or anyone else's.
    function testPerHolderIdCursorIndependence() external {
        _mint(ALICE, ID_A, 100);
        _mint(ALICE, ID_B, 200);
        _mint(BOB, ID_A, 300);

        _splitParams(2);

        // Touch only (Alice, ID_A) via a zero-value manager transfer for
        // that specific id.
        _transfer(ALICE, ALICE, ID_A, 0);

        // (Alice, ID_A) is at cursor 1 and rasterized.
        assertEq(receipt.holderIdCursor(ALICE, ID_A), 1);
        assertEq(receipt.rawStoredBalance(ALICE, ID_A), 200);

        // (Alice, ID_B) and (Bob, ID_A) are untouched — cursor 0, raw
        // balance unchanged, but view balanceOf still reflects the split.
        assertEq(receipt.holderIdCursor(ALICE, ID_B), 0);
        assertEq(receipt.rawStoredBalance(ALICE, ID_B), 200);
        assertEq(receipt.balanceOf(ALICE, ID_B), 400, "view override still applies the split");

        assertEq(receipt.holderIdCursor(BOB, ID_A), 0);
        assertEq(receipt.rawStoredBalance(BOB, ID_A), 300);
        assertEq(receipt.balanceOf(BOB, ID_A), 600);
    }

    /// Zero-balance cursor advancement — load-bearing regression, mirrors
    /// the share-side 2026-04-07-01 bug. A fresh recipient whose stored
    /// balance is 0 at the time of a split must still have their cursor
    /// advanced on first touch, so a subsequent mint doesn't re-apply the
    /// multiplier on top of an already-rebased raw balance.
    function testZeroBalanceCursorAdvancesOnFreshRecipient() external {
        _mint(BOB, ID_A, 1000);
        _splitParams(2);

        // Touch Alice (who has 0 balance) with a 0-value transfer.
        _transfer(ALICE, ALICE, ID_A, 0);

        // Alice's cursor must now point at the split, even though her raw
        // balance was never rewritten.
        assertEq(receipt.holderIdCursor(ALICE, ID_A), 1, "zero-balance cursor must advance");
        assertEq(receipt.rawStoredBalance(ALICE, ID_A), 0);

        // A subsequent mint lands at cursor 1 (post-split basis). The
        // stored balance write of 100 must NOT be re-multiplied by the
        // split on a later balanceOf read.
        _mint(ALICE, ID_A, 100);
        assertEq(receipt.balanceOf(ALICE, ID_A), 100, "post-touch mint must not re-inflate");
    }

    /// Sequential precision — receipt side must match share side exactly.
    /// 1/3 × 3 × 1/3 × 3 applied to 100 = 96.
    function testSequentialPrecisionMatchesShareSide() external {
        _mint(ALICE, ID_A, 100);

        _fractionalParams(1, 3);
        _splitParams(3);
        _fractionalParams(1, 3);
        _splitParams(3);

        // Touch to rasterize.
        _transfer(ALICE, ALICE, ID_A, 0);

        assertEq(receipt.balanceOf(ALICE, ID_A), 96, "receipt side must match share-side sequential precision");
        assertEq(receipt.rawStoredBalance(ALICE, ID_A), 96);
        assertEq(receipt.holderIdCursor(ALICE, ID_A), 4);
    }

    /// Batch update: a batch transfer touching multiple ids migrates all of
    /// them independently.
    function testBatchUpdateMigratesEachIdIndependently() external {
        _mint(ALICE, ID_A, 100);
        _mint(ALICE, ID_B, 200);
        _splitParams(2);

        uint256[] memory ids = new uint256[](2);
        ids[0] = ID_A;
        ids[1] = ID_B;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0; // zero-value batch transfer just to touch both ids
        amounts[1] = 0;

        // Alice calls safeBatchTransferFrom herself — sender == from so no
        // operator approval is required.
        vm.prank(ALICE);
        receipt.safeBatchTransferFrom(ALICE, ALICE, ids, amounts, "");

        // Both (Alice, ID_A) and (Alice, ID_B) must be at cursor 1 and
        // rasterized.
        assertEq(receipt.holderIdCursor(ALICE, ID_A), 1);
        assertEq(receipt.holderIdCursor(ALICE, ID_B), 1);
        assertEq(receipt.rawStoredBalance(ALICE, ID_A), 200);
        assertEq(receipt.rawStoredBalance(ALICE, ID_B), 400);
    }

    /// ReceiptAccountMigrated event is emitted for non-trivial migrations.
    function testReceiptAccountMigratedEventEmitted() external {
        _mint(ALICE, ID_A, 100);
        _splitParams(2);

        vm.expectEmit(true, true, false, true, address(receipt));
        emit StoxReceipt.ReceiptAccountMigrated(ALICE, ID_A, 0, 1, 100, 200);

        _transfer(ALICE, ALICE, ID_A, 0);
    }

    /// A dormant `(holder, id)` touched after multiple completed splits
    /// emits exactly one `ReceiptAccountMigrated` with aggregated fields:
    /// fromCursor is the pre-migration cursor, toCursor is the latest
    /// completed split, oldBalance is the raw stored value, newBalance is
    /// the fully-rasterized value after all multipliers have been applied.
    function testReceiptAccountMigratedAggregatesAcrossMultipleSplits() external {
        _mint(ALICE, ID_A, 100);
        _splitParams(2);
        _splitParams(3);

        vm.recordLogs();
        _transfer(ALICE, ALICE, ID_A, 0);

        bytes32 sig = StoxReceipt.ReceiptAccountMigrated.selector;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 count = 0;
        uint256 fromCursor;
        uint256 toCursor;
        uint256 oldBalance;
        uint256 newBalance;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == sig) {
                count++;
                assertEq(address(uint160(uint256(logs[i].topics[1]))), ALICE, "indexed account is ALICE");
                assertEq(uint256(logs[i].topics[2]), ID_A, "indexed id is ID_A");
                (fromCursor, toCursor, oldBalance, newBalance) =
                    abi.decode(logs[i].data, (uint256, uint256, uint256, uint256));
            }
        }
        assertEq(count, 1, "exactly one ReceiptAccountMigrated per multi-split migration");
        assertEq(fromCursor, 0, "fromCursor is pre-migration cursor");
        assertEq(toCursor, 2, "toCursor is latest completed split index");
        assertEq(oldBalance, 100, "oldBalance is pre-rasterization stored value");
        assertEq(newBalance, 600, "newBalance is fully rasterized (100 * 2 * 3)");
    }

    // -----------------------------------------------------------------------
    // balanceOfBatch consistency

    /// balanceOfBatch must return the same rebased values as calling
    /// balanceOf on each (account, id) individually. Without the override
    /// OZ's default balanceOfBatch reads _balances directly and bypasses
    /// the rebase.
    function testBalanceOfBatchRebaseConsistency() external {
        _mint(ALICE, ID_A, 100);
        _mint(BOB, ID_B, 200);
        _splitParams(2);

        // Neither account has touched since the split — raw stored balances
        // are stale, but balanceOf should return rebased values.
        address[] memory accounts = new address[](3);
        accounts[0] = ALICE;
        accounts[1] = BOB;
        accounts[2] = ALICE;
        uint256[] memory ids = new uint256[](3);
        ids[0] = ID_A;
        ids[1] = ID_B;
        ids[2] = ID_B; // Alice has 0 of ID_B

        uint256[] memory batch = receipt.balanceOfBatch(accounts, ids);

        assertEq(batch[0], receipt.balanceOf(ALICE, ID_A), "batch[0] must match balanceOf(ALICE, ID_A)");
        assertEq(batch[1], receipt.balanceOf(BOB, ID_B), "batch[1] must match balanceOf(BOB, ID_B)");
        assertEq(batch[2], receipt.balanceOf(ALICE, ID_B), "batch[2] must match balanceOf(ALICE, ID_B)");

        // Concrete values: 2× split on 100 and 200.
        assertEq(batch[0], 200);
        assertEq(batch[1], 400);
        assertEq(batch[2], 0);
    }

    /// balanceOfBatch with mismatched array lengths reverts.
    function testBalanceOfBatchMismatchedLengthsReverts() external {
        address[] memory accounts = new address[](2);
        uint256[] memory ids = new uint256[](1);
        vm.expectRevert();
        receipt.balanceOfBatch(accounts, ids);
    }

    /// By the time OZ's `_doSafeTransferAcceptanceCheck` fires
    /// `onERC1155Received` on a contract recipient, migration has
    /// completed and balances are rasterized. A receive hook that reads
    /// `balanceOf` observes the post-migration, post-transfer values.
    function testReceiveHookObservesPostMigrationState() external {
        _mint(ALICE, ID_A, 100);
        _splitParams(2);

        // Use a contract receiver that records the state observed during
        // the onERC1155Received callback.
        RecordingReceiver recv = new RecordingReceiver(receipt, ALICE);
        _transfer(ALICE, address(recv), ID_A, 50);

        // Inside the callback, alice's pre-transfer effective balance was
        // 200 (rebased from stored 100). The hook fires AFTER migration
        // (alice stored becomes 200) and AFTER the transfer (alice raw:
        // 200 - 50 = 150, recv raw: 0 + 50 = 50).
        assertEq(recv.observedAliceBalance(), 150, "hook must see post-transfer alice balance");
        assertEq(recv.observedRecvBalance(), 50, "hook must see post-transfer recv balance");
    }

    // -----------------------------------------------------------------------
    // Helpers

    function _mint(address to, uint256 id, uint256 amount) internal {
        vm.prank(address(vault));
        receipt.managerMint(address(vault), to, id, amount, "");
    }

    function _transfer(address from, address to, uint256 id, uint256 amount) internal {
        vm.prank(address(vault));
        receipt.managerTransferFrom(address(vault), from, to, id, amount, "");
    }
}

/// @dev Contract recipient that records the sender and receiver balances
/// observed during its `onERC1155Received` callback. Used to pin the
/// invariant that receive hooks fire post-migration, post-transfer.
contract RecordingReceiver {
    StoxReceipt public immutable RECEIPT;
    address public immutable ALICE;
    uint256 public observedAliceBalance;
    uint256 public observedRecvBalance;

    constructor(StoxReceipt receipt_, address alice_) {
        RECEIPT = receipt_;
        ALICE = alice_;
    }

    function onERC1155Received(address, address, uint256 id, uint256, bytes calldata) external returns (bytes4) {
        observedAliceBalance = RECEIPT.balanceOf(ALICE, id);
        observedRecvBalance = RECEIPT.balanceOf(address(this), id);
        return this.onERC1155Received.selector;
    }
}
