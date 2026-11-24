// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {LibProdTokenConfig, TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";

/// @title LibTestTokenRows
/// @notice Every token row the declaration gives a token suite and a wrapper suite: the production rows, then the
/// test rows.
library LibTestTokenRows {
    function allRows() internal pure returns (TokenConfig[] memory) {
        TokenConfig[] memory production = LibProdTokenConfig.productionTokenConfigs();
        TokenConfig[] memory test = LibProdTokenConfig.testTokenConfigs();
        TokenConfig[] memory rows = new TokenConfig[](production.length + test.length);
        for (uint256 i = 0; i < production.length; i++) {
            rows[i] = production[i];
        }
        for (uint256 i = 0; i < test.length; i++) {
            rows[production.length + i] = test[i];
        }
        return rows;
    }
}
