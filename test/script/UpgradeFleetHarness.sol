// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {UpgradeFleetTo0_1_30} from "../../script/20260825-upgrade-fleet-to-0-1-30.s.sol";
import {SafeTx} from "../../src/lib/LibSafeOps.sol";
import {TokenInstance} from "../../src/lib/LibTokenInvariants.sol";

/// @dev Exposes the script's internals so the guard tests can drive them
/// directly.
contract UpgradeFleetHarness is UpgradeFleetTo0_1_30 {
    /// @notice The script's `authorBundle()`, externally callable.
    function callAuthorBundle(address[3] memory beacons) external view returns (SafeTx[] memory) {
        return authorBundle(beacons);
    }

    /// @notice The script's `artifactPath()`, externally callable.
    function callArtifactPath() external view returns (string memory) {
        return artifactPath();
    }

    /// @notice The script's `snapshotTokenState()`, externally callable.
    function callSnapshotTokenState(TokenInstance[] memory tokens)
        external
        view
        returns (uint256[] memory, bytes32[] memory)
    {
        return snapshotTokenState(tokens);
    }

    /// @notice The script's `assertTokenStatePreserved()`, externally callable.
    function callAssertTokenStatePreserved(
        TokenInstance[] memory tokens,
        uint256[] memory supplies,
        bytes32[] memory metaHashes
    ) external view {
        assertTokenStatePreserved(tokens, supplies, metaHashes);
    }
}
