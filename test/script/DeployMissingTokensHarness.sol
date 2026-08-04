// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployMissingTokens} from "../../script/20260807-deploy-missing-tokens.s.sol";
import {TokenInstance} from "../../src/lib/LibTokenInvariants.sol";
import {TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";

/// @dev Exposes the script's internals for the pure selection tests.
contract DeployMissingTokensHarness is DeployMissingTokens {
    /// @notice The script's `_selectMissing()`, externally callable.
    /// @param targetTokens The target chain's existing token table.
    /// @return The Base tokens absent from `targetTokens`.
    function selectMissing(TokenInstance[] memory targetTokens) external pure returns (TokenConfig[] memory) {
        return _selectMissing(targetTokens);
    }

    /// @notice The script's `_targetTokens()`, externally callable.
    /// @return The active chain's token table.
    function targetTokens() external view returns (TokenInstance[] memory) {
        return _targetTokens();
    }
}
