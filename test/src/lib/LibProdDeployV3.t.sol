// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibProdDeployV3} from "../../../src/lib/LibProdDeployV3.sol";

/// @title LibProdDeployV3Test
/// @notice The `LibProdDeployV3` address and codehash constants are a frozen
/// audit trail of the V3 deployment — a record of what was built, independent
/// of what the current source compiles to. Checking that the current source
/// still reproduces a pin set is the latest version's responsibility
/// (`LibProdDeployV4.t.sol`); doing it against a legacy version would couple
/// that version to the live compiler and optimizer settings, which shift over
/// time. This contract therefore holds no recompile checks — the same shape as
/// `LibProdDeployV1Test` — and the V3 constants remain purely as the historical
/// record.
contract LibProdDeployV3Test is Test {}
