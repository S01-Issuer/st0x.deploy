// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployEuAuthoriser} from "../../script/20261006-deploy-eu-authoriser.s.sol";

contract PinnedDeployEuAuthoriserHarness is DeployEuAuthoriser {
    address internal constant PIN = address(0xE0A0);

    function pinnedAuthoriser() internal pure override returns (address) {
        return PIN;
    }
}
