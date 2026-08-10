// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployMissingTokensHyperEvm} from "../../script/20260722-deploy-missing-tokens-hyperevm.s.sol";
import {TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";

/// @title DeployMissingTokensHyperEvmHarness
/// @notice Exposes the deploy script's internal selection so the pure
/// selection test can drive it directly. Split into its own file to satisfy
/// the Rain one-contract-per-file convention, matching the existing
/// `DeployMissingTokensEthereumHarness` pattern.
contract DeployMissingTokensHyperEvmHarness is DeployMissingTokensHyperEvm {
    function selectMissing() external pure returns (TokenConfig[] memory) {
        return _selectMissing();
    }
}
