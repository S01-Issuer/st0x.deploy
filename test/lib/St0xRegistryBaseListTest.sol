// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {UrlFetchTest} from "./UrlFetchTest.sol";

/// The listing fields of one token in st0x.registry's `token-lists/base.json`.
struct RegistryToken {
    string symbol;
    string name;
    string isin;
    string tradingViewSymbol;
}

abstract contract St0xRegistryBaseListTest is UrlFetchTest {
    string internal constant REGISTRY_BASE_LIST =
        "https://raw.githubusercontent.com/ST0x-Technology/st0x.registry/e9e47a6e03e2dab0958ae57caa1dc746c46285a2/token-lists/base.json";

    uint256 internal constant NOT_IN_REGISTRY = type(uint256).max;

    function registryBaseTokens() internal returns (RegistryToken[] memory) {
        string memory json = fetch(REGISTRY_BASE_LIST);
        uint256 count = 0;
        while (vm.keyExistsJson(json, string.concat(".tokens[", vm.toString(count), "]"))) count++;
        assertGt(count, 0, REGISTRY_BASE_LIST);
        RegistryToken[] memory tokens = new RegistryToken[](count);
        for (uint256 i = 0; i < count; i++) {
            string memory path = string.concat(".tokens[", vm.toString(i), "]");
            tokens[i] = RegistryToken({
                symbol: vm.parseJsonString(json, string.concat(path, ".symbol")),
                name: vm.parseJsonString(json, string.concat(path, ".name")),
                isin: vm.parseJsonString(json, string.concat(path, ".extensions.isin")),
                tradingViewSymbol: vm.parseJsonString(json, string.concat(path, ".extensions.tradingViewSymbol"))
            });
        }
        return tokens;
    }

    /// The index of the list's wrapped token `wt<underlying>`, or `NOT_IN_REGISTRY`.
    function registryIndexOf(RegistryToken[] memory tokens, string memory underlying)
        internal
        pure
        returns (uint256)
    {
        bytes32 symbol = keccak256(bytes(string.concat("wt", underlying)));
        for (uint256 i = 0; i < tokens.length; i++) {
            if (keccak256(bytes(tokens[i].symbol)) == symbol) return i;
        }
        return NOT_IN_REGISTRY;
    }

    /// The ticker of `EXCHANGE:TICKER`.
    function registryTicker(RegistryToken memory token) internal pure returns (string memory) {
        string[] memory parts = vm.split(token.tradingViewSymbol, ":");
        assertEq(parts.length, 2, token.tradingViewSymbol);
        return parts[1];
    }
}
