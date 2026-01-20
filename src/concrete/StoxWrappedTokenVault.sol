// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ERC4626Upgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {ICLONEABLE_V2_SUCCESS} from "rain.factory/interface/ICloneableV2.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract StoxWrappedTokenVault is ERC4626Upgradeable {
    event StoxWrappedTokenVaultInitialized(address indexed sender, address indexed asset);

    constructor() {
        _disableInitializers();
    }

    function initialize(address asset) external initializer returns (bytes32) {
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
