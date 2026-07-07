// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IERC1271} from "@openzeppelin-contracts-5.6.1/interfaces/IERC1271.sol";

/// @dev EIP-1271 recipient mock. Returns the magic value when `accept`.
contract Mock1271 is IERC1271 {
    bool internal immutable ACCEPT;

    constructor(bool accept) {
        ACCEPT = accept;
    }

    function isValidSignature(bytes32, bytes memory) external view returns (bytes4) {
        return ACCEPT ? IERC1271.isValidSignature.selector : bytes4(0xffffffff);
    }
}
