// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployV4AuthoriserClone} from "../../script/20260619-deploy-v4-authoriser-clone.s.sol";

/// @title DeployV4AuthoriserCloneHarness
/// @notice Subclass of the deploy script that exposes its `internal`
/// post-state assertion as `external` so `vm.expectRevert` can intercept
/// the typed errors it raises. Mirrors the `MigrateBeaconOwnersHarness`
/// pattern — the state-changing sequence in `run()` is exercised via
/// `vm.prank(deployer)` inline in the tests (`vm.startBroadcast` is
/// mutually exclusive with `vm.prank` in `forge test`, so tests can't call
/// `run()` directly through a prank).
contract DeployV4AuthoriserCloneHarness is DeployV4AuthoriserClone {
    function callAssertPostState(address clone, address deployer, address v4Impl) external view {
        _assertPostState(clone, deployer, v4Impl);
    }
}
