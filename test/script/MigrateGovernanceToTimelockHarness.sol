// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {MigrateGovernanceToTimelock} from "../../script/20260729-migrate-governance-to-timelock.s.sol";

/// @title MigrateGovernanceToTimelockHarness
/// @notice Overrides the script's timelock resolution so the full authoring
/// can be exercised on a fork BEFORE the production pins are hydrated: the
/// tests deploy the real timelock at its derived address via the deploy
/// script, then point the migration at it. Production dispatch always reads
/// the `LibTimelockInvariants` pin (the base contract's behaviour, covered
/// by `testRunRefusesUnpinnedTimelock`).
contract MigrateGovernanceToTimelockHarness is MigrateGovernanceToTimelock {
    address internal immutable I_TIMELOCK;

    constructor(address timelock) {
        I_TIMELOCK = timelock;
    }

    function activeChainTimelock() internal view override returns (address) {
        return I_TIMELOCK;
    }
}
