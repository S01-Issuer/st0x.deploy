// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {console} from "forge-std-1.17.0/src/Test.sol";
import {LibProdTokenConfig, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";
import {St0xRegistryBaseListTest, RegistryToken} from "../../lib/St0xRegistryBaseListTest.sol";

/// @title LibProdTokenConfigRegistryBaseListTest
/// @notice Every production row in st0x.registry's Base token list carries the list's ISIN, ticker and name.
contract LibProdTokenConfigRegistryBaseListTest is St0xRegistryBaseListTest {
    /// Logs every mismatch before failing so one run reports every row.
    function checkRowsTheListCovers(
        string memory field,
        function(TokenConfig memory, RegistryToken memory) internal pure returns (string memory, string memory) values
    ) internal {
        RegistryToken[] memory tokens = registryBaseTokens();
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        uint256 covered = 0;
        uint256 mismatches = 0;
        for (uint256 i = 0; i < configs.length; i++) {
            uint256 index = registryIndexOf(tokens, configs[i].underlying);
            if (index == NOT_IN_REGISTRY) {
                console.log("not in the registry Base list:", configs[i].underlying);
                continue;
            }
            covered++;
            (string memory table, string memory list) = values(configs[i], tokens[index]);
            if (keccak256(bytes(table)) != keccak256(bytes(list))) {
                console.log(
                    string.concat(configs[i].underlying, " ", field, ": table '", table, "', list '", list, "'")
                );
                mismatches++;
            }
        }
        console.log(field, "rows checked", covered);
        assertGt(covered, 0, "no row in the list");
        assertEq(mismatches, 0, field);
    }

    function isins(TokenConfig memory config, RegistryToken memory token)
        internal
        pure
        returns (string memory, string memory)
    {
        return (config.assetId, token.isin);
    }

    function tickers(TokenConfig memory config, RegistryToken memory token)
        internal
        pure
        returns (string memory, string memory)
    {
        return (config.listingTicker, registryTicker(token));
    }

    /// The list names the wrapped token, which wraps the listing name.
    function names(TokenConfig memory config, RegistryToken memory token)
        internal
        pure
        returns (string memory, string memory)
    {
        return (string.concat("Wrapped ", config.listingName, " ST0x"), token.name);
    }

    function testRowsInTheRegistryBaseListCarryItsIsin() external {
        checkRowsTheListCovers("isin", isins);
    }

    function testRowsInTheRegistryBaseListCarryItsTradingViewTicker() external {
        checkRowsTheListCovers("ticker", tickers);
    }

    function testRowsInTheRegistryBaseListCarryItsWrappedTokenName() external {
        checkRowsTheListCovers("name", names);
    }
}
