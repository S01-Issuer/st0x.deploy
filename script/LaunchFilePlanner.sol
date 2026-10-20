// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibLaunchPlan, PlanContext, TokenPlan} from "../src/lib/LibLaunchPlan.sol";
import {LibLaunchInputs} from "./lib/LibLaunchInputs.sol";

/// @notice Plans one metadata file in an external call, so `planFiles` can
/// collect every file's refusal instead of stopping at the first. Forge
/// scripts may not call themselves through `this`.
contract LaunchFilePlanner {
    /// @notice Read and plan one metadata file.
    /// @param file The metadata file.
    /// @param ctx The ledger, allowlist, pins, owner and clock.
    /// @return skipped True when the symbol has already shipped or was retired.
    /// @return tokenPlan The derived launch arguments.
    function planFile(string memory file, PlanContext memory ctx)
        external
        view
        returns (bool skipped, TokenPlan memory tokenPlan)
    {
        return LibLaunchPlan.planOne(file, LibLaunchInputs.readMetadata(file), ctx);
    }
}
