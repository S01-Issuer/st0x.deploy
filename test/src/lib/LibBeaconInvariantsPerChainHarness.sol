// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {LibBeaconInvariants} from "../../../src/lib/LibBeaconInvariants.sol";

contract LibBeaconInvariantsPerChainHarness {
    function runsBaseBeaconSet(uint256 chainId) external pure returns (bool) {
        return LibBeaconInvariants.runsBaseBeaconSet(chainId);
    }

    function prodExpectedImplementationsForChainId(uint256 chainId) external pure returns (address[4] memory) {
        return LibBeaconInvariants.prodExpectedImplementationsForChainId(chainId);
    }
}
