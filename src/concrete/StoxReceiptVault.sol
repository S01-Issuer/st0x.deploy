// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {OffchainAssetReceiptVault} from "ethgild/concrete/vault/OffchainAssetReceiptVault.sol";
import {IAuthorizeV1} from "ethgild/interface/IAuthorizeV1.sol";
import {UPDATE_NAME_SYMBOL, IStoxReceiptVaultV2} from "./CorporateActionRegistry.sol";

/// @dev keccak256(abi.encode(uint256(keccak256("rain.storage.stox-receipt-vault.1")) - 1)) & ~bytes32(uint256(0xff))
bytes32 constant STOX_RECEIPT_VAULT_STORAGE_LOCATION =
    0x22c5cc939d9f27711bdc59dfc0a1eb69f2883546f3d77dffbc2f034444f6e000;

/// Thrown when an empty name is provided to updateNameSymbol.
error EmptyName();

/// Thrown when an empty symbol is provided to updateNameSymbol.
error EmptySymbol();

/// @title StoxReceiptVault
/// @notice An OffchainAssetReceiptVault specialized for st0x. Extends the base
/// vault with corporate action support, starting with name/symbol updates.
///
/// Name and symbol overrides allow corporate actions (e.g. ticker changes after
/// a rebrand or symbol standardization) to propagate onchain. The overrides are
/// stored in ERC-7201 namespaced storage so they don't collide with the base
/// vault's storage layout.
///
/// The StoxWrappedTokenVault (ERC-4626 wrapper) automatically reflects
/// name/symbol changes because its name() returns "Wrapped " + asset.name().
contract StoxReceiptVault is OffchainAssetReceiptVault, IStoxReceiptVaultV2 {
    /// Emitted when the vault's name and symbol are updated via a corporate
    /// action.
    /// @param sender The address that triggered the update (the registry).
    /// @param newName The new token name.
    /// @param newSymbol The new token symbol.
    event NameSymbolUpdated(address indexed sender, string newName, string newSymbol);

    /// @param nameOverride If non-empty, returned by name() instead of the
    /// base vault's name. Empty means "use the base name".
    /// @param symbolOverride If non-empty, returned by symbol() instead of the
    /// base vault's symbol. Empty means "use the base symbol".
    /// @custom:storage-location erc7201:rain.storage.stox-receipt-vault.1
    struct StoxReceiptVault7201Storage {
        string nameOverride;
        string symbolOverride;
    }

    /// @dev Accessor for StoxReceiptVault namespaced storage.
    function _getStorageStoxReceiptVault() private pure returns (StoxReceiptVault7201Storage storage s) {
        assembly ("memory-safe") {
            s.slot := STOX_RECEIPT_VAULT_STORAGE_LOCATION
        }
    }

    /// @notice Returns the token name. If a name override has been set via a
    /// corporate action, returns the override. Otherwise falls through to the
    /// base vault's name.
    function name() public view virtual override returns (string memory) {
        StoxReceiptVault7201Storage storage s = _getStorageStoxReceiptVault();
        if (bytes(s.nameOverride).length > 0) {
            return s.nameOverride;
        }
        return super.name();
    }

    /// @notice Returns the token symbol. If a symbol override has been set via
    /// a corporate action, returns the override. Otherwise falls through to the
    /// base vault's symbol.
    function symbol() public view virtual override returns (string memory) {
        StoxReceiptVault7201Storage storage s = _getStorageStoxReceiptVault();
        if (bytes(s.symbolOverride).length > 0) {
            return s.symbolOverride;
        }
        return super.symbol();
    }

    /// @notice Update the vault's name and symbol. Called by the
    /// CorporateActionRegistry during corporate action execution.
    ///
    /// The caller (msg.sender) is expected to be the registry contract. The
    /// authorizer checks that the caller holds UPDATE_NAME_SYMBOL permission.
    ///
    /// Note: name/symbol changes are cosmetic — they do not affect balances or
    /// pricing. CAID (Corporate Action ID) tracking is intentionally NOT
    /// included here. CAID will be added with economically meaningful actions
    /// (rebasing/splits) where stale-state protection matters.
    ///
    /// @param newName The new token name. Must not be empty.
    /// @param newSymbol The new token symbol. Must not be empty.
    function updateNameSymbol(bytes32, uint256, string memory newName, string memory newSymbol) external {
        if (bytes(newName).length == 0) {
            revert EmptyName();
        }
        if (bytes(newSymbol).length == 0) {
            revert EmptySymbol();
        }

        StoxReceiptVault7201Storage storage s = _getStorageStoxReceiptVault();

        s.nameOverride = newName;
        s.symbolOverride = newSymbol;

        // Authorization check AFTER state change, matching the ethgild pattern.
        IAuthorizeV1 auth = this.authorizer();
        auth.authorize(msg.sender, UPDATE_NAME_SYMBOL, abi.encode(newName, newSymbol));

        emit NameSymbolUpdated(msg.sender, newName, newSymbol);
    }
}
