// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibCorporateAction} from "../lib/LibCorporateAction.sol";
import {IAuthorizeV1, Unauthorized} from "ethgild/interface/IAuthorizeV1.sol";

/// @dev Permission for scheduling corporate actions. Separate from execution
/// so that scheduling can be restricted to governance while execution can be
/// delegated to operator hot wallets.
bytes32 constant CORPORATE_ACTION_SCHEDULE = keccak256("CORPORATE_ACTION_SCHEDULE");

/// @dev Permission for executing scheduled corporate actions.
bytes32 constant CORPORATE_ACTION_EXECUTE = keccak256("CORPORATE_ACTION_EXECUTE");

/// @title StoxCorporateActionsFacet
/// @notice Diamond facet for corporate actions on the vault. This facet shares
/// the vault's storage space via ERC-7201 namespaced storage, so it can be
/// delegatecalled from the vault's fallback without storage collisions.
///
/// PR 1 scope: prove that the diamond facet architecture works by reading and
/// writing to namespaced storage through the vault's address. Authorization
/// wiring distinguishes scheduling from execution permissions. Everything else
/// is a stub for future PRs.
contract StoxCorporateActionsFacet {
    /// Emitted when the global corporate action version changes.
    /// @param sender The address that triggered the version change.
    /// @param oldVersion The version before the change.
    /// @param newVersion The version after the change.
    event CorporateActionVersionChanged(address indexed sender, uint256 oldVersion, uint256 newVersion);

    /// @notice Returns the current global corporate action version.
    /// External contracts can use this to detect whether any new corporate
    /// actions have been executed since they last checked.
    function corporateActionGlobalVersion() external view returns (uint256) {
        return LibCorporateAction.getStorage().globalVersion;
    }
}
