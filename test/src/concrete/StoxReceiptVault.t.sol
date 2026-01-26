// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {StoxReceiptVault} from "src/concrete/StoxReceiptVault.sol";
import {OffchainAssetReceiptVault} from "ethgild/concrete/vault/OffchainAssetReceiptVault.sol";
import {Test} from "forge-std/Test.sol";

contract StoxReceiptVaultTest is Test {
    /// We can check the StoxReceiptVault is just a vanilla
    /// OffchainAssetReceiptVault.
    function testStoxReceiptVaultImplementation() external {
        StoxReceiptVault stoxReceiptVault = new StoxReceiptVault();
        OffchainAssetReceiptVault offchainAssetReceiptVault = new OffchainAssetReceiptVault();
        assertEq(address(stoxReceiptVault).codehash, address(offchainAssetReceiptVault).codehash);
    }
}
