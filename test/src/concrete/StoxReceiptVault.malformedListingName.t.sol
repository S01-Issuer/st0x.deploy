// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {StoxReceiptVaultUninitializedTest} from "../../abstract/StoxReceiptVaultUninitializedTest.sol";
import {MalformedListingName} from "../../../src/error/ErrStoxTokenConfig.sol";
import {LibSecurity} from "../../../src/lib/LibSecurity.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";

contract StoxReceiptVaultMalformedListingNameTest is StoxReceiptVaultUninitializedTest {
    function assertInitializeRefuses(string memory listingName) internal {
        StoxReceiptVault vault = uninitializedVault();
        vm.expectRevert(abi.encodeWithSelector(MalformedListingName.selector, listingName));
        vault.initialize(LibTestDeploy.vaultData("US0378331005", "AAPL", listingName, address(0), bytes32(0)));
    }

    function testInitializeRefusesAMalformedListingNameCarryingIt() external {
        assertInitializeRefuses("");
        assertInitializeRefuses("Apple Inc. ST0x");
        assertInitializeRefuses("Apple Inc. (ST0x)");
        assertInitializeRefuses("ST0x");
        assertInitializeRefuses("Apple \"Inc.\"");
        assertInitializeRefuses("Apple\\Inc.");
        assertInitializeRefuses("Apple\nInc.");
        assertInitializeRefuses(string(hex"4170706c651f"));
        assertInitializeRefuses(string(hex"4170706c657f"));
    }

    function testFuzzInitializeRefusesAMalformedListingNameCarryingIt(string memory listingName) external {
        vm.assume(!LibSecurity.nameWellFormed(bytes(listingName)));
        assertInitializeRefuses(listingName);
    }
}
