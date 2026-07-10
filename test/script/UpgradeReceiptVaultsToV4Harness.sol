// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IGnosisSafe} from "../../src/interface/IGnosisSafe.sol";
import {UpgradeReceiptVaultsToV4} from "../../script/20260623-upgrade-receipt-vaults-to-v4.s.sol";

/// @title UpgradeReceiptVaultsToV4Harness
/// @notice Subclass of the upgrade script that exposes its `internal`
/// post-state assertion as `external` so `vm.expectRevert` can intercept the
/// typed `VaultAuthoriserMismatchPostUpgrade` it raises. The pre-flight guards
/// are exercised via `run()` directly in the tests (they revert before any
/// bundle is built); only the post-state — which `run()` reaches only after
/// the still-placeholder clone pin is hydrated — needs this seam to be driven
/// against a deliberately-malformed (un-swapped) state.
contract UpgradeReceiptVaultsToV4Harness is UpgradeReceiptVaultsToV4 {
    function callAssertPostState(IGnosisSafe safe, address[] memory vaults) external view {
        _assertPostState(safe, vaults);
    }
}
