// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployVerifySnapshotBase} from "rain-deploy-0.1.11/src/abstract/RainDeployVerifySnapshotBase.sol";
import {DeploySuite} from "rain-deploy-0.1.11/src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploySnapshot} from "rain-deploy-0.1.11/src/lib/LibRainDeploySnapshot.sol";
import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";

/// @title StoxDeploySnapshotTest
/// @notice The network-free half of `rain-deploy`'s verification, over the
/// declaration `script/Deploy.sol` broadcasts from: every suite is internally
/// consistent (which also refuses an invalid or duplicate key), every
/// candidate is a snapshot of the contract current source compiles, and every
/// file in the frozen record is declared by a released suite.
///
/// `RainDeployVerifySnapshot` is not bound whole because its
/// `testSupportedNetworksAreFullyConfigured` holds `foundry.toml` to
/// `LibRainDeploy.supportedNetworks()`, not to the networks this repo deploys
/// to.
contract StoxDeploySnapshotTest is StoxDeploySuites, RainDeployVerifySnapshotBase {
    /// STOPGAP for `rain-deploy` 0.1.11: `deriveDeployment` runs a suite's
    /// creation code with none of its `dependencies` on chain, and the beacon
    /// and beacon-set deployer constructors refuse an implementation with no
    /// code. Every declared suite's recorded runtime code is placed at its
    /// recorded address first, which is the precondition `dependencies` states
    /// for a broadcast. Etched rather than deployed, so no constructor runs and
    /// no beacon a set deployer creates is left occupying the address its own
    /// derivation creates it at again.
    function setUp() external {
        DeploySuite[] memory suites = allSuites();
        for (uint256 i = 0; i < suites.length; i++) {
            vm.etch(suites[i].storedDeployedAddress, suites[i].storedRuntimeCode);
        }
    }

    function testEveryFrozenSnapshotIsReleased() external view {
        checkFrozenSnapshotsReleased(LibRainDeploySnapshot.frozenSnapshotPaths(vm), releasedSuites());
    }
}
