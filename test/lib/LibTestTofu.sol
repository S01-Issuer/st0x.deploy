// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std/Vm.sol";
import {LibRainDeploy} from "rain.deploy/lib/LibRainDeploy.sol";
import {LibTOFUTokenDecimals} from "rain.tofu.erc20-decimals/lib/LibTOFUTokenDecimals.sol";

/// @title LibTestTofu
/// @notice Test helpers for deploying the TOFU singleton in the local EVM.
library LibTestTofu {
    /// Etches the Zoltu factory and deploys the TOFU singleton so that
    /// `LibTOFUTokenDecimals.safeDecimalsForToken` resolves to the real
    /// singleton at the expected address.
    function deployTofu(Vm vm) internal {
        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(LibTOFUTokenDecimals.TOFU_DECIMALS_EXPECTED_CREATION_CODE);
    }
}
