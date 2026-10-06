// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployEuAuthoriser} from "../../script/20261006-deploy-eu-authoriser.s.sol";
import {LibEuAuthoriserInvariants} from "../../src/lib/LibEuAuthoriserInvariants.sol";

contract UnpinnedDeployEuAuthoriserHarness is DeployEuAuthoriser {
    function pinnedAuthoriser() internal view override returns (address) {
        LibEuAuthoriserInvariants.euAuthoriserForChainId(block.chainid);
        return address(0);
    }
}
