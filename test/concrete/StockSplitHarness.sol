// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibCorporateAction} from "../../src/lib/LibCorporateAction.sol";
import {CorporateActionNode, CompletionFilter, LibCorporateActionNode} from "../../src/lib/LibCorporateActionNode.sol";
import {DecimalsMock} from "./DecimalsMock.sol";

/// @title StockSplitHarness
/// @notice Test harness exposing `LibCorporateAction` and
/// `LibCorporateActionNode` internals as external functions. Implements
/// `decimals()` so the TOFU singleton has something to read when
/// `validateParameters` is called on the harness's own context.
contract StockSplitHarness is DecimalsMock {
    constructor(uint8 decimals_) DecimalsMock(decimals_) {}

    function resolveAndSchedule(bytes32 typeHash, uint64 effectiveTime, bytes calldata parameters)
        external
        returns (uint256)
    {
        uint256 actionType = LibCorporateAction.resolveActionType(typeHash, parameters);
        return LibCorporateAction.schedule(actionType, effectiveTime, parameters);
    }

    function resolveActionType(bytes32 typeHash, bytes calldata parameters) external returns (uint256) {
        return LibCorporateAction.resolveActionType(typeHash, parameters);
    }

    function nextOfType(uint256 cursor, uint256 mask, CompletionFilter filter) external view returns (uint256) {
        return LibCorporateActionNode.nextOfType(cursor, mask, filter);
    }

    function countCompleted() external view returns (uint256) {
        return LibCorporateAction.countCompleted();
    }

    function getNode(uint256 actionIndex) external view returns (CorporateActionNode memory) {
        return LibCorporateAction.getStorage().nodes[actionIndex];
    }
}
