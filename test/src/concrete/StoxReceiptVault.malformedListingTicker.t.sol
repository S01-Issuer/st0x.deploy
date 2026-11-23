// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin-contracts-5.7.0/proxy/beacon/BeaconProxy.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {MalformedListingTicker} from "../../../src/error/ErrStoxTokenConfig.sol";
import {LibSecurity} from "../../../src/lib/LibSecurity.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";

contract StoxReceiptVaultMalformedListingTickerTest is Test {
    UpgradeableBeacon internal beacon;

    function setUp() external {
        deployCodeTo(
            "src/concrete/StoxCorporateActionsFacet.sol:StoxCorporateActionsFacet",
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE
        );
        beacon = new UpgradeableBeacon(address(new StoxReceiptVault()), address(this));
    }

    function assertInitializeRefuses(string memory listingTicker) internal {
        StoxReceiptVault vault = StoxReceiptVault(payable(address(new BeaconProxy(address(beacon), ""))));
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
