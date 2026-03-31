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
contract StoxCorporateActionsFacet {
    /// @notice Returns the current global corporate action ID (CAID).
    /// Incremented each time any corporate action executes. External contracts
    /// can use this to detect whether new corporate actions have occurred since
    /// they last checked.
    function globalCAID() external view returns (uint256) {
        return LibCorporateAction.getStorage().globalCAID;
    }
}
