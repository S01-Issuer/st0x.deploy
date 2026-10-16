// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {OwnedStoxReceiptVault} from "./OwnedStoxReceiptVault.sol";

/// Reads `name()` / `symbol()` from inside the vault and then allocates and
/// fills fresh memory, so a returned string left in unallocated memory would
/// be overwritten before it is returned.
contract MetadataMemoryStoxReceiptVault is OwnedStoxReceiptVault {
    constructor(address owner) OwnedStoxReceiptVault(owner) {}

    function nameThenAllocate() external view returns (string memory value) {
        value = name();
        clobber(bytes(value).length);
    }

    function symbolThenAllocate() external view returns (string memory value) {
        value = symbol();
        clobber(bytes(value).length);
    }

    function clobber(uint256 length) internal pure {
        bytes memory fill = new bytes(length + 0x40);
        for (uint256 i = 0; i < fill.length; i++) {
            fill[i] = 0xff;
        }
    }
}
