// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {StoxReceiptVaultUninitializedTest} from "../../abstract/StoxReceiptVaultUninitializedTest.sol";
import {MalformedAssetId} from "../../../src/error/ErrStoxTokenConfig.sol";
import {LibSecurity} from "../../../src/lib/LibSecurity.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";

contract StoxReceiptVaultMalformedAssetIdTest is StoxReceiptVaultUninitializedTest {
    function assertInitializeRefuses(string memory assetId) internal {
        StoxReceiptVault vault = uninitializedVault();
        vm.expectRevert(abi.encodeWithSelector(MalformedAssetId.selector, assetId));
        vault.initialize(LibTestDeploy.vaultData(assetId, "AAPL", "Apple Inc.", address(0), bytes32(0)));
    }

    function testInitializeRefusesAMalformedAssetIdCarryingIt() external {
        assertInitializeRefuses("");
        assertInitializeRefuses("ST0XTESTUS");
        assertInitializeRefuses("US0378331006");
        assertInitializeRefuses("us0378331005");
        assertInitializeRefuses("US03783310051");
    }

    function testFuzzInitializeRefusesAMalformedAssetIdCarryingIt(string memory assetId) external {
        vm.assume(!LibSecurity.isinWellFormed(assetId));
        assertInitializeRefuses(assetId);
    }
}
