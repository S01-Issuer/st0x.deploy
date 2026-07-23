// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployMissingTokensEthereum} from "../../script/20260722-deploy-missing-tokens-ethereum.s.sol";
import {TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";

/// @title DeployMissingTokensEthereumHarness
/// @notice Exposes the script's internal selection so the pure selection
/// logic can be driven directly. Its own file because Rain convention is one
/// contract per .sol and `rainix-sol-single-contract` enforces it — an inline
/// harness in the .t.sol is exactly the accumulation that gate exists to
/// stop. Mirrors `test/src/lib/LibBeaconInvariantsHarness.sol`.
contract DeployMissingTokensEthereumHarness is DeployMissingTokensEthereum {
    /// @notice The script's `_selectMissing()`, externally callable.
    /// @return The canonical config rows whose Ethereum table entry is unset.
    function selectMissing() external pure returns (TokenConfig[] memory) {
        return _selectMissing();
    }
}
