// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibCorporateAction} from "src/lib/LibCorporateAction.sol";
import {CompletionFilter, CorporateActionNode, LibCorporateActionNode} from "src/lib/LibCorporateActionNode.sol";

/// @dev Thin harness: exposes the four tuple-returning traversal getters via
/// external calls so the library functions can be exercised directly (not
/// through the facet). Also schedules actions into the harness's own storage
/// namespace so there is no ambient state between tests.
contract TraversalHarness {
    function schedule(uint256 actionType, uint64 effectiveTime, bytes memory parameters) external returns (uint256) {
        return LibCorporateAction.schedule(actionType, effectiveTime, parameters);
    }

    function cancel(uint256 actionIndex) external {
        LibCorporateAction.cancel(actionIndex);
    }

    function latest(uint256 mask, CompletionFilter filter) external view returns (uint256, uint256, uint64) {
        return LibCorporateActionNode.latestActionOfType(mask, filter);
    }

    function earliest(uint256 mask, CompletionFilter filter) external view returns (uint256, uint256, uint64) {
        return LibCorporateActionNode.earliestActionOfType(mask, filter);
    }

    function nextOf(uint256 cursor, uint256 mask, CompletionFilter filter)
        external
        view
        returns (uint256, uint256, uint64)
    {
        return LibCorporateActionNode.nextActionOfType(cursor, mask, filter);
    }

    function prevOf(uint256 cursor, uint256 mask, CompletionFilter filter)
        external
        view
        returns (uint256, uint256, uint64)
    {
        return LibCorporateActionNode.prevActionOfType(cursor, mask, filter);
    }

    function nodeAt(uint256 index) external view returns (uint256, uint64) {
        CorporateActionNode storage node = LibCorporateAction.getStorage().nodes[index];
        return (node.actionType, node.effectiveTime);
    }
}
