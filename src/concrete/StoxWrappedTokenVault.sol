// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ERC4626Upgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {ICLONEABLE_V2_SUCCESS, ICloneableV2} from "rain.factory/interface/ICloneableV2.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

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

    function name() public view override(IERC20Metadata, ERC20Upgradeable) returns (string memory) {
        return string.concat("Wrapped ", IERC20Metadata(asset()).name());
    }

    function symbol() public view override(IERC20Metadata, ERC20Upgradeable) returns (string memory) {
        return string.concat("w", IERC20Metadata(asset()).symbol());
    }
}
