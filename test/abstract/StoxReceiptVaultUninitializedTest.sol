// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin-contracts-5.7.0/proxy/beacon/BeaconProxy.sol";
import {StoxReceiptVault} from "../../src/concrete/StoxReceiptVault.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";

/// @notice The facet at its pinned address and the vault behind a beacon, for tests of what `initialize` refuses.
abstract contract StoxReceiptVaultUninitializedTest is Test {
    UpgradeableBeacon internal sBeacon;

    function setUp() public virtual {
        deployCodeTo(
            "src/concrete/StoxCorporateActionsFacet.sol:StoxCorporateActionsFacet",
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE
        );
        sBeacon = new UpgradeableBeacon(address(new StoxReceiptVault()), address(this));
    }

    function uninitializedVault() internal returns (StoxReceiptVault) {
        return StoxReceiptVault(payable(address(new BeaconProxy(address(sBeacon), ""))));
    }
}
