// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeployDeclaration} from "rain-deploy-0.1.30/src/abstract/RainDeploySuitesBase.sol";
import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";
import {LibProdTokenConfig, Region, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibTestTokenConfigs} from "../../lib/LibTestTokenConfigs.sol";
import {LibStoxTestTokens} from "../../../src/lib/LibStoxTestTokens.sol";

/// A released token suite key, pinned to the (asset id, region) of the row it deploys.
struct PinnedTokenSuiteKey {
    string assetId;
    Region region;
    string key;
}

/// The count of pinned keys is not the count of V6 rows.
error PinnedKeyCountMismatch(uint256 pinned, uint256 rows);

/// A pinned key does not match exactly one V6 row by asset id and region.
error PinnedKeyRowCount(string key, uint256 rows);

/// A pinned row no longer derives its pinned key.
error PinnedKeyMoved(string key, string derived);

/// @title LibProdTokenConfigAssetIdTest
/// @notice The asset id rules of the token table: which rows get a V6 suite, the asset id format and uniqueness, and
/// the frozen suite keys of released rows.
contract LibProdTokenConfigAssetIdTest is Test, StoxDeploySuites {
    /// The pinned V6 token suite keys. A key is frozen once released: a released row's `symbol` never changes in the
    /// table (renames are on-chain only). Add each V6 row here in the same change that gives it an asset id; its key
    /// is frozen from then on. No production row has an asset id yet, so there is none.
    function releasedTokenSuiteKeys() internal pure returns (PinnedTokenSuiteKey[] memory) {
        return new PinnedTokenSuiteKey[](0);
    }

    /// The key `StoxDeploySuites.tokenSuites` gives `config`.
    function suiteKey(TokenConfig memory config) internal pure returns (string memory) {
        return string.concat(TOKEN_PREFIX, lowercase(config.symbol));
    }

    /// Every V6 row has a pinned key, every pinned key belongs to exactly one row of `configs` by asset id and region,
    /// and that row still derives the pinned key.
    function checkPinnedKeys(TokenConfig[] memory configs, PinnedTokenSuiteKey[] memory pinned) internal pure {
        TokenConfig[] memory v6 = LibProdTokenConfig.withAssetId(configs);
        if (pinned.length != v6.length) revert PinnedKeyCountMismatch(pinned.length, v6.length);
        for (uint256 p = 0; p < pinned.length; p++) {
            uint256 matches = 0;
            for (uint256 i = 0; i < v6.length; i++) {
                if (
                    keccak256(bytes(v6[i].assetId)) == keccak256(bytes(pinned[p].assetId))
                        && v6[i].region == pinned[p].region
                ) {
                    matches++;
                    string memory derived = suiteKey(v6[i]);
                    if (keccak256(bytes(derived)) != keccak256(bytes(pinned[p].key))) {
                        revert PinnedKeyMoved(pinned[p].key, derived);
                    }
                }
            }
            if (matches != 1) revert PinnedKeyRowCount(pinned[p].key, matches);
        }
    }

    function externalCheckPinnedKeys(TokenConfig[] memory configs, PinnedTokenSuiteKey[] memory pinned) external pure {
        checkPinnedKeys(configs, pinned);
    }

    function pinnedTestTokenKeys() internal pure returns (PinnedTokenSuiteKey[] memory) {
        PinnedTokenSuiteKey[] memory pins = new PinnedTokenSuiteKey[](2);
        pins[0] = PinnedTokenSuiteKey({assetId: "ST0XTESTUS", region: Region.US, key: "stox-token-tustest"});
        pins[1] = PinnedTokenSuiteKey({assetId: "ST0XTESTEU", region: Region.EU, key: "stox-token-teutest"});
        return pins;
    }

    /// The production V6 keys are pinned, and each pinned key is a token suite the production declaration declares.
    function testReleasedTokenSuiteKeysArePinned() external view {
        PinnedTokenSuiteKey[] memory pinned = releasedTokenSuiteKeys();
        checkPinnedKeys(LibProdTokenConfig.productionTokenConfigs(), pinned);
        DeployDeclaration memory declared = declaration();
        for (uint256 p = 0; p < pinned.length; p++) {
            (, bool found) = candidateOf(declared, pinned[p].key);
            assertTrue(found, pinned[p].key);
        }
    }

    /// The pin check holds for the test-token rows with their keys pinned.
    function testPinnedKeysHoldForTheTestTokenRows() external pure {
        checkPinnedKeys(LibStoxTestTokens.testTokenConfigs(), pinnedTestTokenKeys());
    }

    /// A changed symbol on a pinned row moves its key, which the pin check refuses.
    function testPinnedKeysRefuseAChangedSymbol() external {
        TokenConfig[] memory configs = LibStoxTestTokens.testTokenConfigs();
        configs[0].symbol = "tUSTEST2";
        vm.expectRevert(abi.encodeWithSelector(PinnedKeyMoved.selector, "stox-token-tustest", "stox-token-tustest2"));
        this.externalCheckPinnedKeys(configs, pinnedTestTokenKeys());
    }

    /// A row whose asset id changed no longer matches its pinned key, which the pin check refuses.
    function testPinnedKeysRefuseAChangedAssetId() external {
        TokenConfig[] memory configs = LibStoxTestTokens.testTokenConfigs();
        configs[0].assetId = "ST0XTESTUS2";
        vm.expectRevert(abi.encodeWithSelector(PinnedKeyRowCount.selector, "stox-token-tustest", 0));
        this.externalCheckPinnedKeys(configs, pinnedTestTokenKeys());
    }

    /// A V6 row with no pinned key is refused.
    function testPinnedKeysRefuseAnUnpinnedV6Row() external {
        vm.expectRevert(abi.encodeWithSelector(PinnedKeyCountMismatch.selector, 0, 2));
        this.externalCheckPinnedKeys(LibStoxTestTokens.testTokenConfigs(), new PinnedTokenSuiteKey[](0));
    }

    /// `v6TokenConfigs` is the production rows with an asset id, in table order.
    function testV6TokenConfigsAreTheProductionRowsWithAnAssetId() external pure {
        assertEq(
            abi.encode(LibProdTokenConfig.v6TokenConfigs()),
            abi.encode(LibProdTokenConfig.withAssetId(LibProdTokenConfig.productionTokenConfigs()))
        );
    }

    /// `withAssetId` keeps exactly the rows with a non-empty asset id, in order.
    function testWithAssetIdDropsEveryRowWithoutAnAssetId(bool[8] memory hasId) external pure {
        TokenConfig[] memory configs = new TokenConfig[](hasId.length);
        uint256 expected = 0;
        for (uint256 i = 0; i < hasId.length; i++) {
            configs[i].underlying = vm.toString(i);
            if (hasId[i]) {
                configs[i].assetId = string.concat("ID", vm.toString(i));
                expected++;
            }
        }
        TokenConfig[] memory filtered = LibProdTokenConfig.withAssetId(configs);
        assertEq(filtered.length, expected, "count");
        uint256 next = 0;
        for (uint256 i = 0; i < hasId.length; i++) {
            if (hasId[i]) {
                assertEq(filtered[next++].underlying, configs[i].underlying, "order");
            }
        }
    }

    /// Every asset id is 1 to 32 characters of A-Z and 0-9, and an ISIN-shaped one carries a valid check digit.
    function testAssetIdsAreWellFormed() external pure {
        TokenConfig[] memory configs =
            LibProdTokenConfig.withAssetId(LibTestTokenConfigs.productionAndTestTokenConfigs());
        assertGt(configs.length, 0, "rows");
        for (uint256 i = 0; i < configs.length; i++) {
            bytes memory id = bytes(configs[i].assetId);
            assertGt(id.length, 0, configs[i].underlying);
            assertLe(id.length, 32, configs[i].underlying);
            for (uint256 c = 0; c < id.length; c++) {
                assertTrue(isUpperAlnum(id[c]), configs[i].underlying);
            }
            if (isIsinShaped(id)) {
                assertTrue(isinCheckDigitHolds(id), configs[i].underlying);
            }
        }
    }

    /// No (asset id, region) pair repeats. Rows without an asset id are not V6 rows and are left out.
    function testAssetIdAndRegionAreUnique() external pure {
        TokenConfig[] memory configs =
            LibProdTokenConfig.withAssetId(LibTestTokenConfigs.productionAndTestTokenConfigs());
        for (uint256 i = 0; i < configs.length; i++) {
            for (uint256 j = i + 1; j < configs.length; j++) {
                assertFalse(
                    keccak256(bytes(configs[i].assetId)) == keccak256(bytes(configs[j].assetId))
                        && configs[i].region == configs[j].region,
                    configs[i].assetId
                );
            }
        }
    }

    /// The ISIN check digit rule, on known ISINs.
    function testIsinCheckDigit() external pure {
        assertTrue(isIsinShaped(bytes("US67066G1040")));
        assertTrue(isinCheckDigitHolds(bytes("US67066G1040")), "NVIDIA");
        assertTrue(isinCheckDigitHolds(bytes("US0378331005")), "Apple");
        assertTrue(isinCheckDigitHolds(bytes("FR0000121014")), "LVMH");
        assertFalse(isinCheckDigitHolds(bytes("US67066G1041")), "bad check digit");
        assertFalse(isIsinShaped(bytes("ST0XTESTUS")), "synthetic id");
    }

    function isUpperAlnum(bytes1 c) internal pure returns (bool) {
        return (c >= "A" && c <= "Z") || (c >= "0" && c <= "9");
    }

    /// `^[A-Z]{2}[A-Z0-9]{9}[0-9]$`.
    function isIsinShaped(bytes memory id) internal pure returns (bool) {
        if (id.length != 12) return false;
        for (uint256 c = 0; c < 12; c++) {
            bool letter = id[c] >= "A" && id[c] <= "Z";
            bool digit = id[c] >= "0" && id[c] <= "9";
            if (c < 2 && !letter) return false;
            if (c == 11 && !digit) return false;
            if (!letter && !digit) return false;
        }
        return true;
    }

    /// Letters become 10 to 35, then the Luhn sum over the digits, check digit included, is a multiple of 10.
    function isinCheckDigitHolds(bytes memory id) internal pure returns (bool) {
        uint8[] memory digits = new uint8[](id.length * 2);
        uint256 count = 0;
        for (uint256 c = 0; c < id.length; c++) {
            uint8 character = uint8(id[c]);
            if (character >= 0x41) {
                uint8 letterValue = character - 0x41 + 10;
                digits[count++] = letterValue / 10;
                digits[count++] = letterValue % 10;
            } else {
                digits[count++] = character - 0x30;
            }
        }
        uint256 sum = 0;
        for (uint256 k = 0; k < count; k++) {
            uint256 digit = digits[count - 1 - k];
            if (k % 2 == 1) {
                digit *= 2;
                if (digit > 9) digit -= 9;
            }
            sum += digit;
        }
        return sum % 10 == 0;
    }
}
