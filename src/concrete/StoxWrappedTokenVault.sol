// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ERC4626Upgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {ICLONEABLE_V2_SUCCESS, ICloneableV2} from "rain.factory/interface/ICloneableV2.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

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
/// that make minimal assuptions/affordances beyond basic ERC20 functionality.
contract StoxWrappedTokenVault is ERC4626Upgradeable, ICloneableV2 {
    /// @dev Emitted when the StoxWrappedTokenVault is initialized.
    /// @param sender The address that initiated the initialization.
    /// @param asset The address of the underlying asset for the vault.
    event StoxWrappedTokenVaultInitialized(address indexed sender, address indexed asset);

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
    function initialize(bytes calldata data) external initializer returns (bytes32) {
        (address asset) = abi.decode(data, (address));
        __ERC4626_init(ERC20Upgradeable(asset));
        __ERC20_init("", "");

        emit StoxWrappedTokenVaultInitialized(_msgSender(), asset);

        return ICLONEABLE_V2_SUCCESS;
    }

    /// @inheritdoc ERC20Upgradeable
    function name() public view override(IERC20Metadata, ERC20Upgradeable) returns (string memory) {
        return string.concat("Wrapped ", IERC20Metadata(asset()).name());
    }

    /// @inheritdoc ERC20Upgradeable
    function symbol() public view override(IERC20Metadata, ERC20Upgradeable) returns (string memory) {
        return string.concat("w", IERC20Metadata(asset()).symbol());
    }
}
