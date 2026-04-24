// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @dev ERC-7201 namespaced storage location for receipt-side corporate
/// action state on `StoxReceipt`.
/// keccak256(abi.encode(uint256(keccak256("rain.storage.corporate-action-receipt.1")) - 1)) & ~bytes32(uint256(0xff))
bytes32 constant CORPORATE_ACTION_RECEIPT_STORAGE_LOCATION =
    0x44d8f0b6fcc32f3d967ed89d473dfc1155704245690f9cab9f363a65b73e3000;

/// @title LibCorporateActionReceipt
/// @notice Diamond-style storage for receipt-side rebase migration state,
/// isolated from both the vault's corporate-action storage and the
/// ethgild `Receipt7201Storage` by a dedicated ERC-7201 namespace.
///
/// Storage lives on the **receipt contract** (not the vault) because the
/// cursor describes each `(holder, id)` pair's migration progress — data
/// that belongs next to the receipt balances it describes. The multiplier
/// source (stock split linked list) still lives on the vault; the receipt
/// reads it through cross-contract view calls via `ICorporateActionsV1`.
///
/// ## Why the receipt cursor is not unified with the share-side cursor
///
/// The share-side `LibCorporateAction.accountMigrationCursor` is keyed by
/// `address` (one cursor per account, covering all that account's ERC-20
/// shares). The receipt-side cursor here is keyed by `(address, uint256)`
/// because receipts and shares are independently transferable ledgers:
///
///   - Alice deposits, receiving shares and receipt id 7.
///   - Alice transfers receipt id 7 to Bob. Bob now holds the receipt;
///     Alice still holds the shares.
///   - A stock split lands on the vault.
///   - Alice's **share** balance rebases when Alice next touches the ERC-20
///     contract.
///   - Bob's **receipt id 7** balance rebases when Bob next touches the
///     ERC-1155 contract — independently of anything Alice does.
///
/// A unified per-address cursor can't drive both sides because: (a) the
/// share-side `_update` doesn't know which receipt ids Bob holds and
/// ERC-1155 has no enumeration API; (b) Bob's receipts can't be migrated
/// from inside a call that Bob isn't participating in. Conversely, a
/// single per-account cursor on the receipt side would be wrong because
/// each `(holder, id)` pair migrates lazily on its own first-touch, and
/// different ids of the same holder can legitimately sit at different
/// cursor values between touches.
library LibCorporateActionReceipt {
    /// @custom:storage-location erc7201:rain.storage.corporate-action-receipt.1
    /// @dev **DO NOT REORDER — APPEND ONLY.** Lives at a fixed ERC-7201
    /// namespaced slot on an upgradeable beacon-proxy receipt. Reordering
    /// or inserting fields silently remaps live state on upgrade; the
    /// storage-layout pin test in `test/src/concrete/StoxReceipt.t.sol`
    /// (`testReceiptStorageLayoutPin`) must be extended in every later PR
    /// that appends a new field.
    struct CorporateActionReceiptStorage {
        /// Per-(holder, id) migration cursor — the 1-based index of the
        /// last stock split node this `(holder, id)` pair was migrated
        /// through, as seen on the vault's corporate-action linked list.
        /// 0 = never migrated.
        mapping(address holder => mapping(uint256 id => uint256 cursor)) accountIdCursor;
    }

    /// @dev Accessor for receipt-side corporate action storage at the
    /// ERC-7201 slot.
    function getStorage() internal pure returns (CorporateActionReceiptStorage storage s) {
        bytes32 position = CORPORATE_ACTION_RECEIPT_STORAGE_LOCATION;
        assembly ("memory-safe") {
            s.slot := position
        }
    }
}
