// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibSafeOps, SafeTx} from "../../../src/lib/LibSafeOps.sol";

/// @notice External-call harness around `LibSafeOps.emitTxBuilderJson` so
/// `vm.expectRevert` can catch the typed error — library-internal reverts
/// inline, and `expectRevert` only sees reverts that bubble from a lower call
/// depth than the cheatcode itself.
contract EmitHarness {
    function callEmit(address safeAddr, uint256 chainId, string calldata name, SafeTx[] calldata txs)
        external
        view
        returns (string memory)
    {
        return LibSafeOps.emitTxBuilderJson(safeAddr, chainId, name, txs);
    }
}
