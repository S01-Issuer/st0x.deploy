// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {console} from "forge-std-1.17.0/src/Test.sol";
import {LibProdTokenConfig, Region, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";
import {NasdaqSymbolDirectoryTest, SymbolDirectory} from "../../lib/NasdaqSymbolDirectoryTest.sol";

/// One symbol's row in Nasdaq's directories.
struct DirectoryListing {
    bool listed;
    bool nasdaqListed;
    bool etf;
    string securityName;
}

/// @title LibProdTokenConfigNasdaqListingTest
/// @notice Every US production row's listing ticker is a symbol in Nasdaq's directories, and its listing name is
/// that symbol's Security Name.
contract LibProdTokenConfigNasdaqListingTest is NasdaqSymbolDirectoryTest {
    function directoryListing(SymbolDirectory memory nasdaqListed, SymbolDirectory memory otherListed, string memory ticker)
        internal
        pure
        returns (DirectoryListing memory)
    {
        string[] memory fields = listing(nasdaqListed, "Symbol", ticker);
        if (fields.length > 0) {
            return DirectoryListing({
                listed: true,
                nasdaqListed: true,
                etf: keccak256(bytes(fields[column(nasdaqListed.header, "ETF")])) == keccak256("Y"),
                securityName: fields[column(nasdaqListed.header, "Security Name")]
            });
        }
        fields = listing(otherListed, "ACT Symbol", ticker);
        if (fields.length > 0) {
            return DirectoryListing({
                listed: true,
                nasdaqListed: false,
                etf: keccak256(bytes(fields[column(otherListed.header, "ETF")])) == keccak256("Y"),
                securityName: fields[column(otherListed.header, "Security Name")]
            });
        }
        return DirectoryListing({listed: false, nasdaqListed: false, etf: false, securityName: ""});
    }

    function nameMatches(DirectoryListing memory entry, string memory name) internal pure returns (bool) {
        if (entry.nasdaqListed) {
            // nasdaqlisted names every non-ETF "<issuer> - <class>"; an ETF's fund name can itself contain " - ".
            string memory issuer = entry.etf ? entry.securityName : vm.trim(vm.split(entry.securityName, " - ")[0]);
            return keccak256(bytes(issuer)) == keccak256(bytes(name));
        }
        // otherlisted appends the class after a space, with no delimiter.
        return keccak256(bytes(entry.securityName)) == keccak256(bytes(name))
            || vm.indexOf(entry.securityName, string.concat(name, " ")) == 0;
    }

    /// Logs every mismatch before failing so one run reports every row.
    function checkUsRows(bool checkName) internal {
        SymbolDirectory memory nasdaqListed = symbolDirectory(NASDAQ_LISTED);
        SymbolDirectory memory otherListed = symbolDirectory(OTHER_LISTED);
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        uint256 checked = 0;
        uint256 mismatches = 0;
        for (uint256 i = 0; i < configs.length; i++) {
            if (configs[i].region != Region.US) {
                console.log("not a US listing:", configs[i].underlying);
                continue;
            }
            checked++;
            DirectoryListing memory entry = directoryListing(nasdaqListed, otherListed, configs[i].listingTicker);
            if (!entry.listed) {
                console.log(string.concat(configs[i].underlying, ": '", configs[i].listingTicker, "' is not listed"));
                mismatches++;
            } else if (checkName && !nameMatches(entry, configs[i].listingName)) {
                console.log(
                    string.concat(
                        configs[i].underlying,
                        ": table '",
                        configs[i].listingName,
                        "', Nasdaq '",
                        entry.securityName,
                        "'"
                    )
                );
                mismatches++;
            }
        }
        console.log("US rows checked", checked);
        assertGt(checked, 0, "no US row");
        assertEq(mismatches, 0, checkName ? "listing name" : "listing ticker");
    }

    function testEveryUsRowListingTickerIsANasdaqDirectorySymbol() external {
        checkUsRows(false);
    }

    function testEveryUsRowListingNameIsItsNasdaqDirectorySecurityName() external {
        checkUsRows(true);
    }
}
