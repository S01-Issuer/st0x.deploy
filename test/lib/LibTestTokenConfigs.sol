// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {LibProdTokenConfig, TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";
import {LibStoxTestTokens} from "../../src/lib/LibStoxTestTokens.sol";

library LibTestTokenConfigs {
    /// The production tokens, then the test tokens.
    function productionAndTestTokenConfigs() internal pure returns (TokenConfig[] memory) {
        TokenConfig[] memory production = LibProdTokenConfig.productionTokenConfigs();
        TokenConfig[] memory test = LibStoxTestTokens.testTokenConfigs();
        TokenConfig[] memory configs = new TokenConfig[](production.length + test.length);
        for (uint256 i = 0; i < production.length; i++) {
            configs[i] = production[i];
        }
        for (uint256 i = 0; i < test.length; i++) {
            configs[production.length + i] = test[i];
        }
        return configs;
    }

    /// The production rows with an asset id, then the test tokens: every row
    /// that declares a token suite.
    function v6AndTestTokenConfigs() internal pure returns (TokenConfig[] memory) {
        return LibProdTokenConfig.withAssetId(productionAndTestTokenConfigs());
    }
}
