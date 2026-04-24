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
