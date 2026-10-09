// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {GrantOrchestratorEmergency} from "../../script/20261006-grant-orchestrator-emergency.s.sol";
import {SafeTx} from "../../src/lib/LibSafeOps.sol";

/// @dev Exposes the script's internals so the tests can drive them directly.
contract GrantOrchestratorEmergencyHarness is GrantOrchestratorEmergency {
    function callPreflight() external view returns (address) {
        return preflight();
    }

    function callAuthorBundle(address safe) external view returns (SafeTx[] memory) {
        return authorBundle(safe);
    }

    function callArtifactPath() external view returns (string memory) {
        return artifactPath();
    }
}
