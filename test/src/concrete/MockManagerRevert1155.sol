// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

/// @dev Malicious ERC-1155 stand-in whose `manager()` probe REVERTS with
/// exactly 32 bytes of returndata that abi-decode to a vault address. A raw
/// staticcall surfaces that revert payload in its `ret` bytes, so only the
/// `!ok` guard in the orchestrator's `_maybeLowerBurnIndex` stands between
/// this payload and it being misread as a successful `manager()` answer.
contract MockManagerRevert1155 {
    address internal immutable VAULT;

    constructor(address vault) {
        VAULT = vault;
    }

    function manager() external view returns (address) {
        address vault = VAULT;
        // Revert with exactly 32 bytes: the ABI encoding of `vault`.
        assembly ("memory-safe") {
            mstore(0, vault)
            revert(0, 32)
        }
    }
}
