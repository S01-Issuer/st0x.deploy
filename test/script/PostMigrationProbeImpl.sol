// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @title PostMigrationProbeImpl
/// @notice An upgrade destination with no behaviour of its own.
/// `UpgradeableBeacon` requires only that the new implementation is a
/// contract, and `PostMigrationGovernanceTest` needs an address that is
/// provably NOT the one the beacon already points at — upgrading to the
/// incumbent leaves the final assertion holding whether the operation executed
/// or did nothing at all. What the implementation does is irrelevant to
/// proving the loop ran.
contract PostMigrationProbeImpl {}
