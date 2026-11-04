// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {MockERC20} from "./MockERC20.sol";

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
