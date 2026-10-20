// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibLaunchPlan, LaunchMetadata, PlanContext, TokenPlan} from "../../../src/lib/LibLaunchPlan.sol";

/// @notice Exposes `LibLaunchPlan.planOne` as an external call so its reverts
/// can be expected.
contract LibLaunchPlanHarness {
    function planOne(string memory metadataFile, LaunchMetadata memory metadata, PlanContext memory ctx)
        external
        pure
        returns (bool skipped, TokenPlan memory plan)
    {
        return LibLaunchPlan.planOne(metadataFile, metadata, ctx);
    }
}
