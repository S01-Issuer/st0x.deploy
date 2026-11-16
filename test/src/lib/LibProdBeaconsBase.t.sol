// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibProdBeaconsBase} from "../../../src/lib/LibProdBeaconsBase.sol";

/// @title LibProdBeaconsBaseTest
contract LibProdBeaconsBaseTest is Test {
    /// @notice The three beacons are distinct. Index-aligned lists invite a
    /// copy-paste that repeats one entry, and a repeated beacon would still
    /// pass every ownership check while quietly asserting nothing about the
    /// slot it displaced.
    function testTheThreeBeaconsAreDistinct() external pure {
        address[4] memory beacons = LibProdBeaconsBase.beacons();
        assertTrue(beacons[0] != beacons[1], "receipt == receipt vault");
        assertTrue(beacons[1] != beacons[2], "receipt vault == wrapped vault");
        assertTrue(beacons[0] != beacons[2], "receipt == wrapped vault");
    }
}
