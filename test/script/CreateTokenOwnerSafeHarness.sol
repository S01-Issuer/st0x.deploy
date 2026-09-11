// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {CreateTokenOwnerSafe} from "../../script/20260910-create-token-owner-safe.s.sol";

/// @dev Exposes the script's address derivation so the tests can pin it
/// against the live Safes without broadcasting.
contract CreateTokenOwnerSafeHarness is CreateTokenOwnerSafe {
    /// @notice The script's `derivedSafeAddress()`, externally callable.
    function callDerivedSafeAddress() external pure returns (address) {
        return derivedSafeAddress();
    }
}
