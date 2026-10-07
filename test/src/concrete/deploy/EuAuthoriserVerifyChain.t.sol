// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployVerifyChain} from "rain-deploy-0.1.15/src/abstract/RainDeployVerifyChain.sol";

import {EuAuthoriserDeploySuites} from "../../../../src/abstract/EuAuthoriserDeploySuites.sol";

/// @title EuAuthoriserVerifyChainTest
/// @notice The EU assets authoriser against live chain state, through the
/// package's own matrix rather than a hand-rolled fork loop.
///
/// Inheriting `RainDeployVerifyChain` over the same declaration the deploy
/// script uses is the whole point: `testSuitesLiveOnEverySupportedNetwork`
/// and `testSupportedNetworkChainIdsAreBound` come from the package, and they
/// read the suite the broadcast reads. A second declaration here could drift
/// from the one that deploys; there is only one.
///
/// Until the clone is broadcast these go red by design — the declaration
/// names an address that is not on chain yet, which is exactly what the
/// matrix is for.
contract EuAuthoriserVerifyChainTest is EuAuthoriserDeploySuites, RainDeployVerifyChain {}
