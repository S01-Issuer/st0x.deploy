// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {LibSafe} from "rain-deploy-0.1.41/src/lib/LibSafe.sol";

import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";

/// @title LibSafeInvariantsZerogTest
/// @notice The live 0G Safe at its pin, read at its creation block.
contract LibSafeInvariantsZerogTest is Test {
    /// @notice The block of the 0G Safe's creation, tx
    /// 0x985b5995fb274742918b064dfc18795aa95a692cca6998368752d502c6ac1a1e.
    uint256 internal constant ZEROG_SAFE_CREATION_BLOCK = 50760244;

    /// @dev External so a test can expect the policy assertion to revert.
    function assertPolicy(Safe safe) external view {
        LibSafeInvariants.assertTokenOwnerSafePolicy(safe);
    }

    /// @notice The 0G pin holds the creation the pin derives: a locked-down
    /// v1.4.1 Safe on the L2 singleton with the compatibility fallback
    /// handler, Ethereum's six owners in its creation order, no transaction
    /// yet, and the creation threshold of 1. The policy wants 3, so every
    /// 0G pre-flight refuses this Safe until it raises its threshold.
    function testZerogSafeIsTheDerivedCreation() external {
        vm.createSelectFork(LibStoxDeployNetworks.ZEROG, ZEROG_SAFE_CREATION_BLOCK);
        Safe safe = Safe(payable(LibSafeInvariants.safeForChainId(LibSafeInvariants.ZEROG_CHAIN_ID)));

        LibSafe.assertLockedDown(safe);
        assertEq(LibSafe.readStorageAddress(safe, bytes32(0)), LibSafe.SAFE_V1_4_1_L2_SINGLETON, "L2 singleton");
        LibSafe.assertOwnersInOrder(safe, LibSafeInvariants.tokenOwnerSafeCreationOwners());
        LibSafe.assertThreshold(safe, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_CREATION_THRESHOLD);
        assertEq(safe.nonce(), 0, "no transaction yet");

        vm.expectRevert(
            abi.encodeWithSelector(
                LibSafe.SafeThresholdMismatch.selector,
                address(safe),
                LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD,
                LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_CREATION_THRESHOLD
            )
        );
        this.assertPolicy(safe);
    }
}
