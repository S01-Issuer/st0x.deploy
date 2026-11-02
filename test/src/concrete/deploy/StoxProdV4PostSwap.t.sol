// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibAuthoriserInvariants} from "../../../../src/lib/LibAuthoriserInvariants.sol";
import {LibTokenInvariants} from "../../../../src/lib/LibTokenInvariants.sol";
import {LibRainDeploy} from "rain-deploy-0.1.29/src/lib/LibRainDeploy.sol";

/// @title StoxProdV4PostSwapTest
/// @notice Post-swap authoriser pin for V4 on-chain state on Base: every
/// production receipt vault reports the V4 authoriser clone
/// (`LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE`), which
/// `LibAuthoriserInvariants.STOX_PROD_AUTHORISER` aliases, and the clone
/// itself validates via the shared invariant. Base-only: every other
/// chain's vaults are asserted against that chain's own clone by
/// `StoxCrossChainParityTest`.
///
/// The V4 bytecode at its Zoltu addresses is asserted on every network in
/// `LibStoxDeployNetworks.deploymentNetworks()` by `StoxProdV4Test`.
contract StoxProdV4PostSwapTest is Test {
    /// @notice Every prod receipt vault on Base reports the current
    /// production authoriser (`LibAuthoriserInvariants.STOX_PROD_AUTHORISER` —
    /// the V4 clone), and the clone validates via the shared invariant
    /// (codehash bound to the audited 0.1.1 impl + the master
    /// `expectedGrants()` map).
    function testBasePostSwapAuthoriserState() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        LibTokenInvariants.assertUniformAuthoriser(LibAuthoriserInvariants.STOX_PROD_AUTHORISER);
        LibAuthoriserInvariants.assertAll();
    }
}
