// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {StoxReceiptVaultUninitializedTest} from "../../abstract/StoxReceiptVaultUninitializedTest.sol";
import {StoxTokenConfigV1, STOX_TOKEN_CONFIG_V1_TAG} from "../../../src/interface/IStoxTokenConfigV1.sol";
import {NonCanonicalStoxTokenConfig} from "../../../src/error/ErrStoxTokenConfig.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";

contract StoxReceiptVaultNonCanonicalStoxTokenConfigTest is StoxReceiptVaultUninitializedTest {
    function canonical() internal pure returns (bytes memory) {
        return LibTestDeploy.vaultData("US0378331005", "AAPL", "Apple Inc.", address(0), bytes32(0));
    }

    function tail(bytes memory data, uint256 from) internal pure returns (bytes memory) {
        bytes memory out = new bytes(data.length - from);
        for (uint256 i = 0; i < out.length; i++) {
            out[i] = data[from + i];
        }
        return out;
    }

    /// `data` decodes to the canonical config, so only its encoding is refused.
    function assertInitializeRefuses(bytes memory data) internal {
        (bytes32 tag, StoxTokenConfigV1 memory config) = abi.decode(data, (bytes32, StoxTokenConfigV1));
        assertEq(abi.encode(tag, config), canonical(), "decodes to the canonical config");
        assertNotEq(data, canonical(), "encoding");

        StoxReceiptVault vault = uninitializedVault();
        vm.expectRevert(abi.encodeWithSelector(NonCanonicalStoxTokenConfig.selector));
        vault.initialize(data);
    }

    function withGap(bytes32 gap) internal pure returns (bytes memory) {
        return bytes.concat(STOX_TOKEN_CONFIG_V1_TAG, bytes32(uint256(0x60)), gap, tail(canonical(), 0x40));
    }

    function withDirtyTickerPadding(uint224 dirt) internal pure returns (bytes memory) {
        bytes memory data = canonical();
        assembly ("memory-safe") {
            let config := add(data, 0x60)
            let tickerContent := add(add(config, mload(add(config, 0x20))), 0x20)
            mstore(tickerContent, or(mload(tickerContent), dirt))
        }
        return data;
    }

    function testInitializeRefusesTrailingBytes() external {
        assertInitializeRefuses(bytes.concat(canonical(), hex"00"));
        assertInitializeRefuses(bytes.concat(canonical(), bytes32(0)));
    }

    function testFuzzInitializeRefusesTrailingBytes(bytes memory trailing) external {
        vm.assume(trailing.length > 0);
        assertInitializeRefuses(bytes.concat(canonical(), trailing));
    }

    function testInitializeRefusesANonCanonicalEncoding() external {
        assertInitializeRefuses(withGap(bytes32(0)));
        assertInitializeRefuses(withDirtyTickerPadding(1));
    }

    function testFuzzInitializeRefusesAGapBeforeTheConfig(bytes32 gap) external {
        assertInitializeRefuses(withGap(gap));
    }

    function testFuzzInitializeRefusesDirtyTickerPadding(uint224 dirt) external {
        vm.assume(dirt != 0);
        assertInitializeRefuses(withDirtyTickerPadding(dirt));
    }
}
