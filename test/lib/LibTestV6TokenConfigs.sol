// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {LibProdTokenConfig, Region, TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";

/// @title LibTestV6TokenConfigs
/// @notice V6 token rows for tests. No production row has an asset id yet, so
/// the production V6 set is empty; these fixture rows, one per region, keep the
/// nameless V6 deploy path covered until it is not. Delete this library and
/// the `tokenConfigs()` test overrides once test-token rows with asset ids, or
/// production V6 rows, exist. Test-token rows with these tickers would declare
/// the same suite keys.
library LibTestV6TokenConfigs {
    /// One fixture row per region, each with a synthetic asset id that cannot
    /// collide with an ISIN.
    function fixtureTokenConfigs() internal pure returns (TokenConfig[] memory) {
        TokenConfig[] memory configs = new TokenConfig[](2);
        configs[0] = TokenConfig({
            underlying: "USTEST",
            name: "US Test ST0x",
            symbol: "tUSTEST",
            region: Region.US,
            underlyingName: "US Test",
            assetId: "ST0XTESTUS"
        });
        configs[1] = TokenConfig({
            underlying: "EUTEST",
            name: "EU Test ST0x",
            symbol: "tEUTEST",
            region: Region.EU,
            underlyingName: "EU Test",
            assetId: "ST0XTESTEU"
        });
        return configs;
    }

    /// The production V6 rows, then the fixture rows.
    function v6AndFixtureTokenConfigs() internal pure returns (TokenConfig[] memory) {
        return concat(LibProdTokenConfig.v6TokenConfigs(), fixtureTokenConfigs());
    }

    /// Every production row, then the fixture rows.
    function productionAndFixtureTokenConfigs() internal pure returns (TokenConfig[] memory) {
        return concat(LibProdTokenConfig.productionTokenConfigs(), fixtureTokenConfigs());
    }

    function concat(TokenConfig[] memory first, TokenConfig[] memory second)
        internal
        pure
        returns (TokenConfig[] memory)
    {
        TokenConfig[] memory configs = new TokenConfig[](first.length + second.length);
        for (uint256 i = 0; i < first.length; i++) {
            configs[i] = first[i];
        }
        for (uint256 i = 0; i < second.length; i++) {
            configs[first.length + i] = second[i];
        }
        return configs;
    }
}
