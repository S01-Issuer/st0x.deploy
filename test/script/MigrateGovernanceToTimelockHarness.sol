// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {MigrateGovernanceToTimelock} from "../../script/20260729-migrate-governance-to-timelock.s.sol";

/// @title MigrateGovernanceToTimelockHarness
/// @notice Overrides the script's timelock resolution so a test chooses the
/// timelock the authoring targets. Production dispatch always reads the
/// `LibTimelockInvariants` pin.
contract MigrateGovernanceToTimelockHarness is MigrateGovernanceToTimelock {
    address internal immutable I_TIMELOCK;

    // A test double storing the collaborator it is handed. Rejecting zero here
    // would only stop the suite exercising the zero case.
    // forge-lint: disable-next-line(missing-zero-check)
    constructor(address timelock) {
        I_TIMELOCK = timelock;
    }

    function activeChainTimelock() internal view override returns (address) {
        return I_TIMELOCK;
    }

    function loopProofSalt() external pure returns (bytes32) {
        return LOOP_PROOF_SALT;
    }
}
