// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";

import {UnderlyingNamingReleaseNotFrozen} from "../src/lib/LibUnderlyingNamingRollout.sol";
import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";

/// @title DeployUnderlyingNamingImplementations
/// @notice Step 1 of the underlying-naming rollout (`docs/TIMELOCK.md`):
/// Zoltu-deploy the corporate-actions facet, the receipt-vault implementation
/// and the wrapped-token-vault implementation that the beacon batch points the
/// chain's beacons at.
///
/// Only audited, frozen release snapshots are deployed. The implementations
/// `LibUnderlyingNamingRollout` names are current-source candidate pins, not a
/// release, so `run()` refuses unconditionally. It becomes a deploy suite of
/// the release's stored creation code, asserted against that release's
/// address and codehash pins, once the release is frozen and audited.
contract DeployUnderlyingNamingImplementations is Script, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration() external pure returns (ScriptDeclaration memory) {
        return LibStoxMigrations.notAMigration();
    }

    /// @notice Refuses: no frozen, audited release carries these
    /// implementations yet.
    function run() external pure {
        revert UnderlyingNamingReleaseNotFrozen();
    }
}
