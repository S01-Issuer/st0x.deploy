// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibTimelockInvariants} from "../../../src/lib/LibTimelockInvariants.sol";

/// @notice External-call harness around `LibTimelockInvariants`'s internal
/// asserts so `vm.expectRevert` can catch their typed errors —
/// library-internal reverts inline, and `expectRevert` only sees reverts from
/// a lower call depth than the cheatcode itself.
contract LibTimelockInvariantsHarness {
    function callAssertTimelockState(address timelock, address proposerExecutorSafe) external view {
        LibTimelockInvariants.assertTimelockState(timelock, proposerExecutorSafe);
    }

    function callTimelockForChainId(uint256 chainId) external pure returns (address) {
        return LibTimelockInvariants.timelockForChainId(chainId);
    }
}
