// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {SafeTx} from "rain-deploy-0.1.38/src/lib/LibSafeTx.sol";

import {HandSafeOwnedBaseVaultsToTimelock} from "../../script/20261103-hand-safe-owned-base-vaults-to-timelock.s.sol";
import {TokenInstance} from "../../src/lib/LibTokenInvariants.sol";

/// @dev Per-instance artifact path because tests run in parallel.
contract HandSafeOwnedBaseVaultsToTimelockHarness is HandSafeOwnedBaseVaultsToTimelock {
    string internal sArtifactTag;
    TokenInstance[] internal sRows;
    bool internal sRowsSet;

    constructor(string memory artifactTag) {
        sArtifactTag = artifactTag;
    }

    /// @dev Stands `rows` in for the chain's token table, as 0G's will hold the tokens its creation made.
    function setOwnershipRows(TokenInstance[] memory rows) external {
        delete sRows;
        for (uint256 i = 0; i < rows.length; i++) {
            sRows.push(rows[i]);
        }
        sRowsSet = true;
    }

    /// @inheritdoc HandSafeOwnedBaseVaultsToTimelock
    function ownershipRows() internal view override returns (TokenInstance[] memory) {
        return sRowsSet ? sRows : super.ownershipRows();
    }

    /// @inheritdoc HandSafeOwnedBaseVaultsToTimelock
    function artifactPath() internal view override returns (string memory) {
        return string.concat(
            "out/20261103-hand-safe-owned-base-vaults-to-timelock-",
            vm.toString(block.chainid),
            "-",
            sArtifactTag,
            ".json"
        );
    }

    function callPreflight() external view {
        preflight();
    }

    function callAuthorBundle() external view returns (SafeTx[] memory) {
        return authorBundle();
    }

    /// The production artifact path, which every test otherwise overrides.
    function callProductionArtifactPath() external view returns (string memory) {
        return super.artifactPath();
    }

    function callArtifactPath() external view returns (string memory) {
        return artifactPath();
    }

    function callHandoverVaults() external view returns (address[] memory) {
        return handoverVaults();
    }

    function callAssertPostState() external view {
        assertPostState();
    }

    function callProveGovernance() external {
        proveGovernance();
    }

    function callAssertReversible() external {
        assertReversible();
    }

    function callBundleName() external pure returns (string memory) {
        return bundleName();
    }

    function callBeaconOf(address proxy) external view returns (address) {
        return beaconOf(proxy);
    }
}
