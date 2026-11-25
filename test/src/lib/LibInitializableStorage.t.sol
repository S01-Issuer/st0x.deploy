// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibInitializableStorage, INITIALIZABLE_STORAGE_LOCATION} from "../../../src/lib/LibInitializableStorage.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";

contract LibInitializableStorageTest is Test {
    /// The vault keeps its `Initializable` state at the slot the facet reads:
    /// the implementation's disabled initializers sit there.
    function testTheVaultsInitializableStateIsAtTheSlot() external {
        StoxReceiptVault implementation = new StoxReceiptVault();
        assertEq(uint256(vm.load(address(implementation), INITIALIZABLE_STORAGE_LOCATION)), type(uint64).max);
    }

    function testIsInitializedOnAnyNonZeroSlot(uint256 value) external {
        vm.store(address(this), INITIALIZABLE_STORAGE_LOCATION, bytes32(value));
        assertEq(LibInitializableStorage.isInitialized(), value != 0);
    }

    function testIsInitializedWhileOnlyInitializing() external {
        vm.store(address(this), INITIALIZABLE_STORAGE_LOCATION, bytes32(uint256(1) << 64));
        assertTrue(LibInitializableStorage.isInitialized());
    }
}
