// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {StoxReceiptVaultUninitializedTest} from "../../abstract/StoxReceiptVaultUninitializedTest.sol";
import {MalformedListingTicker} from "../../../src/error/ErrStoxTokenConfig.sol";
import {LibSecurity} from "../../../src/lib/LibSecurity.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";

contract StoxReceiptVaultMalformedListingTickerTest is StoxReceiptVaultUninitializedTest {
    function assertInitializeRefuses(string memory listingTicker) internal {
        StoxReceiptVault vault = uninitializedVault();
        vm.expectRevert(abi.encodeWithSelector(MalformedListingTicker.selector, listingTicker));
        vault.initialize(LibTestDeploy.vaultData("US0378331005", listingTicker, "Apple Inc.", address(0), bytes32(0)));
    }

    function testInitializeRefusesAMalformedListingTickerCarryingIt() external {
        assertInitializeRefuses("");
        assertInitializeRefuses("ABCDEFGHIJKLMNOPQ");
        assertInitializeRefuses("aapl");
        assertInitializeRefuses("tAAPL");
        assertInitializeRefuses("AA PL");
        assertInitializeRefuses("AA\"PL");
        assertInitializeRefuses("AA\\PL");
        assertInitializeRefuses("AAPL\n");
        assertInitializeRefuses("BRK/B");
    }

    function testFuzzInitializeRefusesAMalformedListingTickerCarryingIt(string memory listingTicker) external {
        vm.assume(!LibSecurity.tickerWellFormed(bytes(listingTicker)));
        assertInitializeRefuses(listingTicker);
    }
}
