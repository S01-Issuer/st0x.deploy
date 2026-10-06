// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {OrchestratorAdminToTimelock} from "../../script/20261006-orchestrator-admin-to-timelock.s.sol";
import {SafeTx} from "../../src/lib/LibSafeOps.sol";

/// @dev Exposes the script's internals so the tests can drive them directly.
contract OrchestratorAdminToTimelockHarness is OrchestratorAdminToTimelock {
    function callPreflight() external view returns (address, address) {
        return preflight();
    }

    function callAuthorBundle(address safe, address timelock) external pure returns (SafeTx[] memory) {
        return authorBundle(safe, timelock);
    }

    function callArtifactPath() external view returns (string memory) {
        return artifactPath();
    }
}
