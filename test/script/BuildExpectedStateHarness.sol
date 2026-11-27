// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {BuildExpectedState} from "../../script/BuildExpectedState.sol";
import {TokenInstance} from "../../src/lib/LibTokenInvariants.sol";
import {LibProdTokenConfig} from "../../src/lib/LibProdTokenConfig.sol";

/// @title BuildExpectedStateHarness
/// @notice External shim so `vm.expectRevert` can intercept reverts from the script's internal emitters.
contract BuildExpectedStateHarness is BuildExpectedState {
    function callTokenMetadataJson(string memory row, TokenInstance memory token) external {
        tokenMetadataJson(row, token, LibProdTokenConfig.configOf(token.underlying));
    }

    /// @dev The metadata fields `tokenMetadataJson` writes for `token`, as a JSON object.
    function tokenMetadata(TokenInstance memory token) external returns (string memory) {
        string memory row = string.concat("metadata.", token.underlying);
        tokenMetadataJson(row, token, LibProdTokenConfig.configOf(token.underlying));
        return vm.serializeString(row, "underlying", token.underlying);
    }
}
