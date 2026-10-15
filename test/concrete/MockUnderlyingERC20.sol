// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {MockERC20} from "./MockERC20.sol";

/// @dev ERC20 asset exposing settable `underlyingSymbol()` / `underlyingName()`
/// getters, standing in for a `StoxReceiptVault`.
contract MockUnderlyingERC20 is MockERC20 {
    string internal sUnderlyingSymbol;
    string internal sUnderlyingName;

    function setUnderlyingValues(string memory newSymbol, string memory newName) external {
        sUnderlyingSymbol = newSymbol;
        sUnderlyingName = newName;
    }

    function underlyingSymbol() external view returns (string memory) {
        return sUnderlyingSymbol;
    }

    function underlyingName() external view returns (string memory) {
        return sUnderlyingName;
    }
}

/// @dev ERC20 asset whose underlying getters revert with data.
contract RevertingUnderlyingERC20 is MockERC20 {
    error NoUnderlying();

    function underlyingSymbol() external pure returns (string memory) {
        revert NoUnderlying();
    }

    function underlyingName() external pure returns (string memory) {
        revert NoUnderlying();
    }
}

/// @dev ERC20 asset whose fallback answers any unknown selector with the
/// configured raw bytes, either returned or reverted with, so the wrapper sees
/// whatever the test chooses (none, too short, a malformed string, or a
/// well-formed string carried by a revert).
contract RawReturnERC20 is MockERC20 {
    bytes internal sRaw;
    bool internal sRevert;

    function setRaw(bytes memory raw) external {
        sRaw = raw;
    }

    function setRevert(bool shouldRevert) external {
        sRevert = shouldRevert;
    }

    fallback() external {
        bytes memory raw = sRaw;
        bool shouldRevert = sRevert;
        assembly ("memory-safe") {
            if shouldRevert { revert(add(raw, 0x20), mload(raw)) }
            return(add(raw, 0x20), mload(raw))
        }
    }
}
