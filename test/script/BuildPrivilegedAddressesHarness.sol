// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {BuildPrivilegedAddresses} from "../../script/BuildPrivilegedAddresses.sol";

/// @title BuildPrivilegedAddressesHarness
/// @notice Marks one chain's token table unhydrated, so a test can drive the render's skip path.
contract BuildPrivilegedAddressesHarness is BuildPrivilegedAddresses {
    uint256 internal sUnhydratedChainId;

    /// @dev Marks `chainId`'s token table unhydrated.
    function markUnhydrated(uint256 chainId) external {
        sUnhydratedChainId = chainId;
    }

    /// @inheritdoc BuildPrivilegedAddresses
    function tokenTableHydrated(uint256 chainId) internal view override returns (bool) {
        return chainId != sUnhydratedChainId && super.tokenTableHydrated(chainId);
    }
}
