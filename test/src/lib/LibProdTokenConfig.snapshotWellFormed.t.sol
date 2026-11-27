// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibProdTokenConfig, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibSecurity} from "../../../src/lib/LibSecurity.sol";

/// @notice Every row the underlying snapshot is built from has a well-formed
/// ticker, name and ISIN under `LibSecurity`.
contract LibProdTokenConfigSnapshotWellFormedTest is Test {
    function testEverySnapshotRowIsWellFormed() external pure {
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        assertGt(configs.length, 0, "rows");
        for (uint256 i = 0; i < configs.length; i++) {
            assertTrue(
                LibSecurity.tickerWellFormed(bytes(configs[i].ticker)), string.concat(configs[i].ticker, " ticker")
            );
            assertTrue(
                LibSecurity.nameWellFormed(bytes(configs[i].underlyingName)),
                string.concat(configs[i].ticker, " underlyingName")
            );
            assertTrue(LibSecurity.isinWellFormed(configs[i].isin), string.concat(configs[i].ticker, " isin"));
        }
    }
}
