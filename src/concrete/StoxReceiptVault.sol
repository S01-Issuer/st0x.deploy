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
/// Each corporate action that modifies this vault produces a Corporate Action ID
/// (CAID) that is stored locally. The CAID is derived from `msg.sender` (the
/// registry dispatching the action), the action type, and the action number.
/// This means:
/// - The vault controls how the CAID is derived — no trust in the registry
///   to hash correctly.
/// - If the registry is ever replaced (via the authorizer), old IDs from a
///   previous registry can't collide (different msg.sender).
/// - The vault doesn't hardcode a single registry — it trusts whoever the
///   authorizer says can call its corporate action functions.
///
/// The StoxWrappedTokenVault (ERC-4626 wrapper) automatically reflects
/// name/symbol changes because its name() returns "Wrapped " + asset.name().
contract StoxReceiptVault is OffchainAssetReceiptVault, IStoxReceiptVaultV2 {
    /// Emitted when the vault's name and symbol are updated via a corporate
    /// action.
    /// @param sender The address that triggered the update (the registry).
    /// @param newName The new token name.
    /// @param newSymbol The new token symbol.
    /// @param caid The Corporate Action ID produced by this update.
    event NameSymbolUpdated(address indexed sender, string newName, string newSymbol, bytes32 indexed caid);

    /// @param nameOverride If non-empty, returned by name() instead of the
    /// base vault's name. Empty means "use the base name".
    /// @param symbolOverride If non-empty, returned by symbol() instead of the
    /// base vault's symbol. Empty means "use the base symbol".
    /// @param currentCAID The most recent Corporate Action ID applied to this
    /// vault. Downstream consumers can read this to verify they are operating
    /// under the expected corporate action state.
    /// @custom:storage-location erc7201:rain.storage.stox-receipt-vault.1
    struct StoxReceiptVault7201Storage {
        string nameOverride;
        string symbolOverride;
        bytes32 currentCAID;
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

    /// @notice Returns the current Corporate Action ID. Downstream protocols
    /// can use this to verify they are operating under the expected state.
    /// Returns bytes32(0) if no corporate action has been applied.
    function currentCAID() external view returns (bytes32) {
        StoxReceiptVault7201Storage storage s = _getStorageStoxReceiptVault();
        return s.currentCAID;
    }

    /// @notice Update the vault's name and symbol. Called by the
    /// CorporateActionRegistry during corporate action execution.
    ///
    /// The caller (msg.sender) is expected to be the registry contract. The
    /// authorizer checks that the caller holds UPDATE_NAME_SYMBOL permission.
    /// The CAID is derived from msg.sender so that different registries produce
    /// different CAIDs for the same action type/number, preventing collisions
    /// if the registry is ever replaced.
    ///
    /// @param actionType The corporate action type (for CAID computation).
    /// @param number The action number (for CAID computation).
    /// @param newName The new token name. Must not be empty.
    /// @param newSymbol The new token symbol. Must not be empty.
    function updateNameSymbol(bytes32 actionType, uint256 number, string memory newName, string memory newSymbol)
        external
    {
        if (bytes(newName).length == 0) {
            revert EmptyName();
        }
        if (bytes(newSymbol).length == 0) {
            revert EmptySymbol();
        }

        StoxReceiptVault7201Storage storage s = _getStorageStoxReceiptVault();

        s.nameOverride = newName;
        s.symbolOverride = newSymbol;
        s.currentCAID = _computeCAID(actionType, number);

        // Authorization check AFTER state change, matching the ethgild pattern.
        // The authorizer can inspect the new state if needed.
        // Uses this.authorizer() because the base vault's storage accessor is
        // private, but authorizer() is a public external view.
        IAuthorizeV1 auth = this.authorizer();
        auth.authorize(msg.sender, UPDATE_NAME_SYMBOL, abi.encode(newName, newSymbol));

        emit NameSymbolUpdated(msg.sender, newName, newSymbol, s.currentCAID);
    }

    /// @dev Compute the Corporate Action ID from the caller (registry),
    /// action type, and action number. The inclusion of msg.sender means
    /// different registries produce different CAIDs, which prevents collisions
    /// if the registry is ever replaced via the authorizer.
    /// @param actionType The action type.
    /// @param number The action number.
    /// @return The CAID.
    function _computeCAID(bytes32 actionType, uint256 number) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(msg.sender, actionType, number));
    }
}
