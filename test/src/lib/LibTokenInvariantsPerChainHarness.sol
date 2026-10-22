// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {LibTokenInvariants, TokenInstance} from "../../../src/lib/LibTokenInvariants.sol";

contract LibTokenInvariantsPerChainHarness {
    function productionTokensForChainId(uint256 chainId) external pure returns (TokenInstance[] memory) {
        return LibTokenInvariants.productionTokensForChainId(chainId);
    }
}
