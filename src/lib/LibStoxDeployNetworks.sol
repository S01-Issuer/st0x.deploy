// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

/// @title LibStoxDeployNetworks
/// @notice Single source of truth for the networks the ST0x production deploy
/// broadcasts to. `script/Deploy.sol` reads this instead of hardcoding the list
/// inline, so the supported-network set lives in one place. ST0x deploys to
/// Base only.
library LibStoxDeployNetworks {
    /// @notice The networks each suite in `script/Deploy.sol` is broadcast to.
    /// @return networks The list of network names (Base only).
    function supportedNetworks() internal pure returns (string[] memory networks) {
        networks = new string[](1);
        networks[0] = LibRainDeploy.BASE;
    }
}
