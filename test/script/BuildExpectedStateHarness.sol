// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {BuildExpectedState} from "../../script/BuildExpectedState.sol";
import {TokenInstance} from "../../src/lib/LibTokenInvariants.sol";

/// @title BuildExpectedStateHarness
/// @notice External shim so `vm.expectRevert` can intercept reverts from the script's internal emitters.
contract BuildExpectedStateHarness is BuildExpectedState {
    function callTokenMetadataJson(uint256 chainId, string memory row, uint256 i, TokenInstance memory token)
        external
    {
        tokenMetadataJson(chainId, row, i, token);
    }

    /// @dev The metadata fields `tokenMetadataJson` writes for row `i` on `chainId`, as a JSON object.
    function tokenMetadata(uint256 chainId, uint256 i, TokenInstance memory token) external returns (string memory) {
        string memory row = string.concat("metadata.", vm.toString(chainId), ".", vm.toString(i));
        tokenMetadataJson(chainId, row, i, token);
        return vm.serializeString(row, "underlying", token.underlying);
    }
}
