// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {HandSafeOwnedBaseVaultsToTimelockRootLineTest} from "./HandSafeOwnedBaseVaultsToTimelockRootLineTest.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";

/// @title HandSafeOwnedBaseVaultsToTimelockOffBaseRootLineTest
/// @notice Off Base, on Ethereum, the bundle is the record alone.
contract HandSafeOwnedBaseVaultsToTimelockOffBaseRootLineTest is HandSafeOwnedBaseVaultsToTimelockRootLineTest {
    function network() internal pure override returns (string memory) {
        return LibStoxDeployNetworks.ETHEREUM;
    }
}
