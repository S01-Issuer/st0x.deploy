// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {LibProdDeployV1} from "../../../src/lib/LibProdDeployV1.sol";

/// @title LibProdDeployV1Test
/// @notice Verifies V1 creation bytecodes match compiled artifacts for
/// contracts that are still unchanged from V1. Both `StoxReceipt` and
/// `StoxReceiptVault` diverged from V1 when rebase logic was added — their
/// V1 bytecodes are no longer reproducible from the current source, so the
/// consistency checks were removed. The V1 constants remain in
/// `LibProdDeployV1` as an audit trail.
contract LibProdDeployV1Test is Test {}
