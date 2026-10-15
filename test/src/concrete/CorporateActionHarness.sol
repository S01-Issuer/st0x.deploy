// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibCorporateAction} from "../../../src/lib/LibCorporateAction.sol";
import {
    CorporateActionNode,
    CompletionFilter,
    LibCorporateActionNode
} from "../../../src/lib/LibCorporateActionNode.sol";
import {LibTestCorporateAction} from "../../lib/LibTestCorporateAction.sol";

/// @dev Harness to test library functions directly.
contract CorporateActionHarness {
    uint8 public constant decimals = 18;

    function resolveActionType(bytes32 typeHash, bytes calldata parameters) external returns (uint256) {
        return LibCorporateAction.resolveActionType(typeHash, parameters);
    }

    function schedule(uint256 actionType, uint64 effectiveTime, bytes memory parameters) external returns (uint256) {
        return LibCorporateAction.schedule(actionType, effectiveTime, parameters);
    }

    function cancel(uint256 actionIndex) external {
        LibCorporateAction.cancel(actionIndex);
    }

    function countCompleted() external view returns (uint256) {
        return LibCorporateAction.countCompleted();
    }

    function nextOfType(uint256 cursor, uint256 mask, CompletionFilter filter) external view returns (uint256) {
        return LibCorporateActionNode.nextOfType(cursor, mask, filter);
    }

    function prevOfType(uint256 cursor, uint256 mask, CompletionFilter filter) external view returns (uint256) {
        return LibCorporateActionNode.prevOfType(cursor, mask, filter);
    }

    function getNode(uint256 actionIndex) external view returns (CorporateActionNode memory) {
        return LibCorporateAction.getStorage().nodes[actionIndex];
    }

    function head() external view returns (uint256) {
        return LibTestCorporateAction.head();
    }

    function tail() external view returns (uint256) {
        return LibTestCorporateAction.tail();
    }

    /// Library-path readers — all go through `LibCorporateAction.getStorage()`,
    /// so `testStorageLayoutPin` can prove a value written at a specific slot
    /// is actually the slot the library reads from.
    function accountMigrationCursor(address account) external view returns (uint256) {
        return LibCorporateAction.getStorage().accountMigrationCursor[account];
    }

    function unmigrated(uint256 cursor) external view returns (uint256) {
        return LibCorporateAction.getStorage().unmigrated[cursor];
    }

    function totalSupplyLatestCursor() external view returns (uint256) {
        return LibCorporateAction.getStorage().totalSupplyLatestCursor;
    }

    /// Direct call to `ensureBootstrap` so tests can observe the
    /// post-bootstrap pre-user-action state (`bootstrap.prev` /
    /// `bootstrap.next` both `NODE_NONE`). The production `schedule` call
    /// fires `ensureBootstrap` and then immediately splices in the user
    /// action, mutating `bootstrap.next` away from `NODE_NONE` — so the
    /// only way to pin the in-between state is to invoke
    /// `ensureBootstrap` standalone.
    function ensureBootstrap() external {
        LibCorporateAction.ensureBootstrap(LibCorporateAction.getStorage());
    }
}
