// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployVerifySnapshot} from "rain-deploy-0.1.29/src/abstract/RainDeployVerifySnapshot.sol";
import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";

contract StoxDeploySnapshotTest is StoxDeploySuites, RainDeployVerifySnapshot {
    /// The orchestrator beacon-set deployer's constructor seats the active
    /// chain's timelock and reverts on a chain without one; its bytecode is
    /// chain-invariant, as in `script/BuildPointers.sol`.
    function setUp() external {
        vm.chainId(LibSafeInvariants.BASE_CHAIN_ID);
    }
}
