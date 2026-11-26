// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {
    OffchainAssetReceiptVaultConfigV3,
    OFFCHAIN_ASSET_RECEIPT_VAULT_CONFIG_V3_TAG
} from "rain-vats-0.2.25/src/interface/IOffchainAssetReceiptVaultV1.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {StoxReceiptVaultUninitializedTest} from "../../abstract/StoxReceiptVaultUninitializedTest.sol";
import {STOX_TOKEN_CONFIG_V1_TAG} from "../../../src/interface/IStoxTokenConfigV1.sol";
import {InvalidStoxTokenConfigTag} from "../../../src/error/ErrStoxTokenConfig.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";

contract StoxReceiptVaultInvalidStoxTokenConfigTagTest is StoxReceiptVaultUninitializedTest {
    function assertInitializeRefuses(bytes memory data, bytes32 tag) internal {
        StoxReceiptVault vault = uninitializedVault();
        vm.expectRevert(abi.encodeWithSelector(InvalidStoxTokenConfigTag.selector, tag));
        vault.initialize(data);
    }

    function validData() internal pure returns (bytes memory) {
        return LibTestDeploy.vaultData("US0378331005", "AAPL", "Apple Inc.", address(0), bytes32(0));
    }

    function retagged(bytes32 tag) internal pure returns (bytes memory) {
        bytes memory data = validData();
        assembly ("memory-safe") {
            mstore(add(data, 0x20), tag)
        }
        return data;
    }

    function truncated(bytes32 seed, uint256 length) internal pure returns (bytes memory) {
        bytes memory data = abi.encodePacked(seed);
        assembly ("memory-safe") {
            mstore(data, length)
        }
        return data;
    }

    function testInitializeRefusesDataShorterThanATagCarryingTheZeroTag() external {
        assertInitializeRefuses("", bytes32(0));
        assertInitializeRefuses(hex"01", bytes32(0));
        assertInitializeRefuses(truncated(STOX_TOKEN_CONFIG_V1_TAG, 31), bytes32(0));
        assertInitializeRefuses(truncated(bytes32(type(uint256).max), 31), bytes32(0));
    }

    function testFuzzInitializeRefusesDataShorterThanATagCarryingTheZeroTag(bytes32 seed, uint256 length) external {
        assertInitializeRefuses(truncated(seed, bound(length, 0, 31)), bytes32(0));
    }

    function testInitializeRefusesAnotherTagCarryingIt() external {
        assertInitializeRefuses(abi.encode(bytes32(0)), bytes32(0));
        assertInitializeRefuses(retagged(bytes32(0)), bytes32(0));
        assertInitializeRefuses(
            retagged(STOX_TOKEN_CONFIG_V1_TAG ^ bytes32(uint256(1))), STOX_TOKEN_CONFIG_V1_TAG ^ bytes32(uint256(1))
        );
        assertInitializeRefuses(
            abi.encode(
                OFFCHAIN_ASSET_RECEIPT_VAULT_CONFIG_V3_TAG,
                OffchainAssetReceiptVaultConfigV3({
                    name: "Apple Inc. ST0x",
                    symbol: "tAAPL",
                    authority: address(0),
                    rbacName: bytes32(0),
                    receiptBeaconName: bytes32(0),
                    metadata: ""
                })
            ),
            OFFCHAIN_ASSET_RECEIPT_VAULT_CONFIG_V3_TAG
        );
    }

    function testFuzzInitializeRefusesAnotherTagCarryingIt(bytes32 tag, bytes memory body) external {
        vm.assume(tag != STOX_TOKEN_CONFIG_V1_TAG);
        assertInitializeRefuses(bytes.concat(tag, body), tag);
    }

    function testFuzzInitializeRefusesAV1ConfigUnderAnotherTagCarryingIt(bytes32 tag) external {
        vm.assume(tag != STOX_TOKEN_CONFIG_V1_TAG);
        assertInitializeRefuses(retagged(tag), tag);
    }
}
