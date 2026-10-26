// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";

import {MigrateGovernanceToTimelock} from "../../script/20260729-migrate-governance-to-timelock.s.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";

/// @title MigrateGovernanceToTimelockHarness
/// @notice Overrides the script's timelock resolution so the full authoring
/// can be exercised on a fork BEFORE the production pins are hydrated: the
/// tests deploy the real timelock at its derived address via the deploy
/// script, then point the migration at it. Production dispatch always reads
/// the `LibTimelockInvariants` pin (the base contract's behaviour, covered
/// by `testRunRefusesUnpinnedTimelock`).
contract MigrateGovernanceToTimelockHarness is MigrateGovernanceToTimelock {
    address internal immutable I_TIMELOCK;
    string internal sArtifactTag;

    // A test double storing the collaborator it is handed. Rejecting zero here
    // would only stop the suite exercising the zero case.
    // forge-lint: disable-next-line(missing-zero-check)
    constructor(address timelock, string memory artifactTag) {
        I_TIMELOCK = timelock;
        sArtifactTag = artifactTag;
    }

    function artifactPath() internal view override returns (string memory) {
        return string.concat(
            "out/20260729-governance-timelock-migration-", vm.toString(block.chainid), "-", sArtifactTag, ".json"
        );
    }

    function callArtifactPath() external view returns (string memory) {
        return artifactPath();
    }

    function callAssertPostState() external view {
        _assertPostState(
            Safe(payable(LibSafeInvariants.safeForChainId(block.chainid))),
            activeChainTimelock(), activeChainAuthoriser(), tokensForActiveChain(), _beaconImplementations()
        );
    }

    function activeChainTimelock() internal view override returns (address) {
        return I_TIMELOCK;
    }
}
