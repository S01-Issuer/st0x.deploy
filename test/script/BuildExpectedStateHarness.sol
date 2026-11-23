// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {BuildExpectedState} from "../../script/BuildExpectedState.sol";

/// @title BuildExpectedStateHarness
/// @notice External shim so `vm.expectRevert` can intercept reverts from the script's internal emitters, and so a
/// test can mark one chain's token table unhydrated.
contract BuildExpectedStateHarness is BuildExpectedState {
    uint256 internal sUnhydratedChainId;

    /// @dev Marks `chainId`'s token table unhydrated, so the render takes the skip path there.
    function markUnhydrated(uint256 chainId) external {
        sUnhydratedChainId = chainId;
    }

    /// @inheritdoc BuildExpectedState
    function tokenTableHydrated(uint256 chainId) internal view override returns (bool) {
        return chainId != sUnhydratedChainId && super.tokenTableHydrated(chainId);
    }

    function callTokenMetadataJson(uint256 chainId, string memory row, uint256 i, string memory underlying) external {
        tokenMetadataJson(chainId, row, i, underlying);
    }

    /// @dev The metadata fields `tokenMetadataJson` writes for row `i` on `chainId`, as a JSON object.
    function tokenMetadata(uint256 chainId, uint256 i, string memory underlying) external returns (string memory) {
        string memory row = string.concat("metadata.", vm.toString(chainId), ".", vm.toString(i));
        tokenMetadataJson(chainId, row, i, underlying);
        return vm.serializeString(row, "underlying", underlying);
    }
}
