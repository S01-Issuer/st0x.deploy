// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    ERC4626Upgradeable
} from "@openzeppelin-contracts-upgradeable-5.7.0/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin-contracts-upgradeable-5.7.0/token/ERC20/ERC20Upgradeable.sol";
import {ICLONEABLE_V2_SUCCESS, ICloneableV2} from "rain-factory-0.2.7/src/interface/ICloneableV2.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.7.0/token/ERC20/extensions/IERC20Metadata.sol";
import {IStoxUnderlyingV1} from "../interface/IStoxUnderlyingV1.sol";

/// @dev Error raised when a zero address is provided for the vault asset.
error ZeroAsset();

/// @title StoxWrappedTokenVault
/// @notice An ERC-4626 compliant vault that wraps an underlying token, intended
/// to be a StoxReceiptVault as the asset.
/// This allows for defi compatible tokens that have a claim on any underlying
/// revaluations of the base assets that are 1:1 with the offchain bridge. For
/// example, dividends and stock splits both revalue the underlying asset, either
/// indirectly as yield or directly as a rebase of the total supply.
/// The wrapper token as a vault never produces yield or rebases due to offchain
/// events, therefore it captures the value in its price onchain rather than
/// in its supply or an external token.
/// The downside is that the wrapper token will trade at a premium or discount
/// relative to the offchain asset that is ostensibly being tokenized, but the
/// benefit is that the wrapper token can easily integrate with defi protocols
/// that make minimal assumptions/affordances beyond basic ERC20 functionality.
/// The wrapper's ERC-20 name and symbol are read from the asset on every call,
/// each field on its own. `symbol()` is the asset's
/// `IStoxUnderlyingV1.underlyingSymbol()` + "s" when that is non-empty (e.g.
/// "NVDAs"), else "w" + the asset's symbol (e.g. "wtNVDA"). `name()` is the
/// asset's own name when its `underlyingName()` is non-empty (e.g.
/// "NVIDIA Corporation (ST0x)"), else "Wrapped " + that name. Any ERC-20
/// asset can be wrapped.
contract StoxWrappedTokenVault is ERC4626Upgradeable, ICloneableV2 {
    /// @dev Emitted when the StoxWrappedTokenVault is initialized.
    /// @param sender The address that initiated the initialization.
    /// @param asset The address of the underlying asset for the vault.
    event StoxWrappedTokenVaultInitialized(address indexed sender, address indexed asset);

    /// @dev Locks the implementation contract against direct initialization.
    constructor() {
        _disableInitializers();
    }

    /// As per ICloneableV2, this overload MUST always revert. Documents the
    /// signature of the initialize function.
    /// @param asset The address of the underlying asset for the vault.
    function initialize(address asset) external pure returns (bytes32) {
        (asset);
        revert InitializeSignatureFn();
    }

    /// @inheritdoc ICloneableV2
    /// @dev data is `abi.encode(address asset)` where asset is the underlying
    /// ERC20 token (typically a StoxReceiptVault) to wrap in this ERC4626 vault.
    function initialize(bytes calldata data) external initializer returns (bytes32) {
        (address asset) = abi.decode(data, (address));
        if (asset == address(0)) revert ZeroAsset();
        __ERC4626_init(ERC20Upgradeable(asset));
        __ERC20_init("", "");

        emit StoxWrappedTokenVaultInitialized(_msgSender(), asset);

        return ICLONEABLE_V2_SUCCESS;
    }

    /// The asset's own ERC-20 name once the asset reports a non-empty
    /// `IStoxUnderlyingV1.underlyingName()`: for a `StoxReceiptVault` that is
    /// the name built from the underlying, e.g. "NVIDIA Corporation (ST0x)",
    /// so the name format lives in one place. When the asset does not
    /// implement the getter, reverts, returns malformed data or returns an
    /// empty name, falls back to "Wrapped " + the asset's ERC-20 name.
    /// @return The wrapped token name.
    function name() public view override(IERC20Metadata, ERC20Upgradeable) returns (string memory) {
        string memory assetName = IERC20Metadata(asset()).name();
        if (bytes(tryAssetString(IStoxUnderlyingV1.underlyingName.selector)).length > 0) return assetName;
        return string.concat("Wrapped ", assetName);
    }

    /// The asset's `IStoxUnderlyingV1.underlyingSymbol()` + "s", e.g.
    /// "NVDAs". When the asset does not implement it, reverts, returns
    /// malformed data or returns an empty ticker, falls back to "w" + the
    /// asset's ERC-20 symbol.
    /// @return The wrapped token symbol.
    function symbol() public view override(IERC20Metadata, ERC20Upgradeable) returns (string memory) {
        string memory underlying = tryAssetString(IStoxUnderlyingV1.underlyingSymbol.selector);
        if (bytes(underlying).length > 0) return string.concat(underlying, "s");
        return string.concat("w", IERC20Metadata(asset()).symbol());
    }

    /// @dev Calls a zero-argument `string`-returning getter on the asset and
    /// returns the result, or the empty string if the call fails or its
    /// return data is not a well-formed ABI-encoded `string`. Never reverts
    /// on the asset's behalf, so any ERC-20 asset keeps a readable
    /// name/symbol.
    /// @param selector The getter's function selector.
    /// @return value The decoded string, or "" on any failure.
    function tryAssetString(bytes4 selector) internal view returns (string memory value) {
        // Low-level so a missing selector, a revert or malformed return data
        // all land in the checks below instead of reverting this call.
        // slither-disable-next-line low-level-calls
        (bool success, bytes memory data) = asset().staticcall(abi.encodeWithSelector(selector));
        if (!success || data.length < 0x40) return "";
        uint256 offset;
        uint256 length;
        assembly ("memory-safe") {
            offset := mload(add(data, 0x20))
            length := mload(add(data, 0x40))
        }
        if (offset != 0x20 || length > data.length - 0x40) return "";
        value = abi.decode(data, (string));
    }
}
