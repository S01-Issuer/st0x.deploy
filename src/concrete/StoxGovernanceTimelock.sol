// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {LibStoxConfig} from "../lib/LibStoxConfig.sol";
import {LibTimelockInvariants} from "../lib/LibTimelockInvariants.sol";

/// @title StoxGovernanceTimelock
/// @notice The st0x governance `TimelockController`, Zoltu-deployed. Its
/// proposer and executor are the governance Safe bound in the
/// `ConfigRegistry`, so the creation code is chain-invariant; `admin` is zero
/// so it self-administers and the deploy key holds nothing.
contract StoxGovernanceTimelock is
    TimelockController(
        LibTimelockInvariants.TIMELOCK_MIN_DELAY,
        LibStoxGovernanceTimelockArgs.safeArray(),
        LibStoxGovernanceTimelockArgs.safeArray(),
        address(0)
    )
{}

library LibStoxGovernanceTimelockArgs {
    function safeArray() internal view returns (address[] memory) {
        address[] memory safes = new address[](1);
        safes[0] = LibStoxConfig.governanceSafe();
        return safes;
    }
}
