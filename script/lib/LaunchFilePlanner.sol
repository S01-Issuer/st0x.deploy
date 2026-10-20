// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibLaunchPlan, PlanContext, TokenPlan} from "../../src/lib/LibLaunchPlan.sol";
import {LibLaunchInputs} from "./LibLaunchInputs.sol";

/// @notice Plans one metadata file in an external call, so `planFiles` can
/// collect every file's refusal instead of stopping at the first. Forge
/// scripts may not call themselves through `this`.
contract LaunchFilePlanner {
    function planFile(string memory file, PlanContext memory ctx)
        external
        view
        returns (bool skipped, TokenPlan memory tokenPlan)
    {
        return LibLaunchPlan.planOne(file, LibLaunchInputs.readMetadata(file), ctx);
    }
}
