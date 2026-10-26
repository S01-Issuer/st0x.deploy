// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {SafeTx} from "rain-deploy-0.1.22/src/lib/LibSafeTx.sol";

import {GrantOrchestratorEmergency} from "../../script/20261006-grant-orchestrator-emergency.s.sol";

/// @dev Exposes the script's hooks so the tests can drive them directly.
contract GrantOrchestratorEmergencyHarness is GrantOrchestratorEmergency {
    function callPreflight() external view {
        preflight();
    }

    function callAuthorBundle() external view returns (SafeTx[] memory) {
        return authorBundle();
    }

    function callAssertPostState() external view {
        assertPostState();
    }
}
