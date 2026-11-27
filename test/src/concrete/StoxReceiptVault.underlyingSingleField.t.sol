// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.7.0/access/OwnableUpgradeable.sol";
import {IAuthorizeV1} from "rain-vats-0.2.25/src/interface/IAuthorizeV1.sol";
import {CloneFactory} from "rain-factory-deploy-0.2.14/src/concrete/CloneFactory.sol";
import {LibRainDeploy} from "rain-deploy-0.1.38/src/lib/LibRainDeploy.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {StoxCorporateActionsFacet} from "../../../src/concrete/StoxCorporateActionsFacet.sol";
import {IStoxUnderlyingV2} from "../../../src/interface/IStoxUnderlyingV2.sol";
import {IStoxAssetIdV1} from "../../../src/interface/IStoxAssetIdV1.sol";
import {
    MalformedUnderlyingSymbol,
    MalformedUnderlyingName,
    MalformedUnderlyingIsin
} from "../../../src/error/ErrUnderlying.sol";
import {LibSecurity, UNDERLYING_STORAGE_LOCATION} from "../../../src/lib/LibSecurity.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";
import {OwnedStoxReceiptVault} from "./OwnedStoxReceiptVault.sol";

/// `setUnderlyingSymbol`, `setUnderlyingName` and `setUnderlyingIsin` on
/// tokens built as in production, through the vault's fallback and the facet.
contract StoxReceiptVaultUnderlyingSingleFieldTest is Test {
    address internal constant AUTHORITY = address(uint160(uint256(keccak256("AUTHORITY"))));
    address internal constant OWNER = address(uint160(uint256(keccak256("OWNER"))));
    bytes32 internal constant RBAC_NAME = keccak256("st0x.rbac.test.v1");
    string internal constant NVDA_ISIN = "US67066G1040";
    string internal constant META_ISIN = "US30303M1027";
    string internal constant AAPL_ISIN = "US0378331005";

    uint256 internal constant SYMBOL = 0;
    uint256 internal constant NAME = 1;
    uint256 internal constant ISIN = 2;

    function setUp() external {
        LibTestDeploy.deployAll(vm);
        address facet = LibRainDeploy.deployZoltu(type(StoxCorporateActionsFacet).creationCode);
        require(facet == LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE, "facet address mismatch");
        StoxOffchainAssetReceiptVaultAuthorizerV1 impl = new StoxOffchainAssetReceiptVaultAuthorizerV1();
        IAuthorizeV1 authorizer = IAuthorizeV1(
            new CloneFactory()
                .cloneDeterministic(
                    address(impl), LibTestDeploy.authorizerData(vm, OWNER), bytes32(uint256(uint160(address(impl))))
                )
        );
        LibTestDeploy.bindRbac(vm, AUTHORITY, RBAC_NAME, OWNER, authorizer);
    }

    /// A token listing NVDA_ISIN as "NVDA" / "NVIDIA Corporation".
    function newToken() internal returns (StoxReceiptVault) {
        return LibTestDeploy.newVault(
            AUTHORITY, LibTestDeploy.vaultData(NVDA_ISIN, "NVDA", "NVIDIA Corporation", AUTHORITY, RBAC_NAME)
        );
    }

    function setField(StoxReceiptVault token, uint256 field, string memory value) internal {
        if (field == SYMBOL) {
            IStoxUnderlyingV2(address(token)).setUnderlyingSymbol(value);
        } else if (field == NAME) {
            IStoxUnderlyingV2(address(token)).setUnderlyingName(value);
        } else {
            IStoxUnderlyingV2(address(token)).setUnderlyingIsin(value);
        }
    }

    function current(StoxReceiptVault token) internal view returns (string[3] memory) {
        return [
            IStoxUnderlyingV2(address(token)).underlyingSymbol(),
            IStoxUnderlyingV2(address(token)).underlyingName(),
            IStoxAssetIdV1(address(token)).assetId()
        ];
    }

    function storedTimestamp(StoxReceiptVault token) internal view returns (uint256) {
        return uint256(vm.load(address(token), bytes32(uint256(UNDERLYING_STORAGE_LOCATION) + 3)));
    }

    function wellFormedTicker(bytes32 seed, uint256 length) internal pure returns (string memory) {
        bytes memory alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.";
        bytes memory ticker = new bytes(bound(length, 1, 16));
        for (uint256 byteIndex = 0; byteIndex < ticker.length; byteIndex++) {
            ticker[byteIndex] = alphabet[uint8(seed[byteIndex]) % alphabet.length];
        }
        return string(ticker);
    }

    function wellFormedName(bytes memory seed) internal pure returns (string memory) {
        bytes memory name = new bytes(seed.length);
        for (uint256 byteIndex = 0; byteIndex < name.length; byteIndex++) {
            bytes1 printable = bytes1(0x20 + uint8(seed[byteIndex]) % 0x5f);
            name[byteIndex] = printable == "\"" || printable == "\\" ? bytes1(0x20) : printable;
        }
        vm.assume(LibSecurity.nameWellFormed(name));
        return string(name);
    }

    function wellFormedIsin(uint256 index) internal pure returns (string memory) {
        string[3] memory isins = [NVDA_ISIN, META_ISIN, AAPL_ISIN];
        return isins[index % isins.length];
    }

    function newValues(bytes32 symbolSeed, uint256 symbolLength, bytes memory nameSeed, uint256 isinIndex)
        internal
        pure
        returns (string[3] memory)
    {
        return [wellFormedTicker(symbolSeed, symbolLength), wellFormedName(nameSeed), wellFormedIsin(isinIndex)];
    }

    function assertSetsOnlyField(StoxReceiptVault token, uint256 field, string memory value, uint256 timestamp)
        internal
    {
        string[3] memory before = current(token);
        string[3] memory expected = [before[SYMBOL], before[NAME], before[ISIN]];
        expected[field] = value;

        vm.warp(timestamp);
        vm.recordLogs();
        vm.prank(OWNER);
        setField(token, field, value);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        string[3] memory got = current(token);
        for (uint256 other = 0; other < 3; other++) {
            assertEq(got[other], expected[other]);
        }
        assertEq(token.symbol(), LibSecurity.vaultSymbol(expected[SYMBOL]));
        assertEq(token.name(), LibSecurity.vaultName(expected[NAME]));
        assertEq(storedTimestamp(token), timestamp);

        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(token));
        assertEq(logs[0].topics.length, 2);
        assertEq(logs[0].topics[0], IStoxUnderlyingV2.UnderlyingSet.selector);
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(OWNER))));
        assertEq(
            logs[0].data,
            abi.encode(before[SYMBOL], before[NAME], before[ISIN], expected[SYMBOL], expected[NAME], expected[ISIN])
        );
    }

    function testSingleFieldSetterOnAFreshToken(
        bytes32 symbolSeed,
        uint256 symbolLength,
        bytes memory nameSeed,
        uint256 isinIndex,
        uint32 timestamp
    ) external {
        string[3] memory values = newValues(symbolSeed, symbolLength, nameSeed, isinIndex);
        for (uint256 field = 0; field < 3; field++) {
            StoxReceiptVault token = newToken();
            string[3] memory listing = current(token);
            assertEq(listing[SYMBOL], "NVDA");
            assertEq(listing[NAME], "NVIDIA Corporation");
            assertEq(listing[ISIN], NVDA_ISIN);
            assertEq(storedTimestamp(token), 0);
            assertSetsOnlyField(token, field, values[field], timestamp);
        }
    }

    function testSingleFieldSetterAfterAnOverride(
        bytes32 symbolSeed,
        uint256 symbolLength,
        bytes memory nameSeed,
        uint256 isinIndex,
        uint32 overrideTimestamp,
        uint32 timestamp
    ) external {
        string[3] memory values = newValues(symbolSeed, symbolLength, nameSeed, isinIndex);
        vm.assume(overrideTimestamp != timestamp);
        for (uint256 field = 0; field < 3; field++) {
            StoxReceiptVault token = newToken();
            vm.warp(overrideTimestamp);
            vm.prank(OWNER);
            IStoxUnderlyingV2(address(token)).setUnderlying("FB", "Meta Platforms, Inc.", META_ISIN);
            assertEq(storedTimestamp(token), overrideTimestamp);
            string[3] memory overridden = current(token);
            assertEq(overridden[SYMBOL], "FB");
            assertEq(overridden[NAME], "Meta Platforms, Inc.");
            assertEq(overridden[ISIN], META_ISIN);
            assertSetsOnlyField(token, field, values[field], timestamp);
        }
    }

    function testSingleFieldSettersKeepEarlierSingleFieldSets() external {
        StoxReceiptVault token = newToken();
        assertSetsOnlyField(token, SYMBOL, "NVDX", 100);
        assertSetsOnlyField(token, NAME, "NVIDIA Holdings", 200);
        assertSetsOnlyField(token, ISIN, AAPL_ISIN, 300);
        assertSetsOnlyField(token, SYMBOL, "NVDQ", 400);

        string[3] memory got = current(token);
        assertEq(got[SYMBOL], "NVDQ");
        assertEq(got[NAME], "NVIDIA Holdings");
        assertEq(got[ISIN], AAPL_ISIN);
    }

    function testSingleFieldSetterNonOwnerReverts(address caller, uint256 field) external {
        vm.assume(caller != OWNER);
        field = bound(field, 0, 2);
        StoxReceiptVault token = newToken();
        string[3] memory before = current(token);
        string[3] memory values = ["NVDX", "NVIDIA Holdings", AAPL_ISIN];

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, caller));
        vm.prank(caller, OWNER);
        setField(token, field, values[field]);

        string[3] memory got = current(token);
        for (uint256 other = 0; other < 3; other++) {
            assertEq(got[other], before[other]);
        }
        assertEq(storedTimestamp(token), 0);
    }

    /// The owner check runs before the value checks.
    function testSingleFieldSetterNonOwnerMalformedRevertsUnauthorized() external {
        StoxReceiptVault token = newToken();
        for (uint256 field = 0; field < 3; field++) {
            vm.expectRevert(
                abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this))
            );
            setField(token, field, "");
        }
    }

    function assertRejected(StoxReceiptVault token, uint256 field, string memory value, bytes memory err) internal {
        string[3] memory before = current(token);
        vm.expectRevert(err);
        vm.prank(OWNER);
        setField(token, field, value);
        string[3] memory got = current(token);
        for (uint256 other = 0; other < 3; other++) {
            assertEq(got[other], before[other]);
        }
        assertEq(storedTimestamp(token), 0);
    }

    function testSetUnderlyingSymbolMalformedReverts(bytes memory symbol) external {
        vm.assume(!LibSecurity.tickerWellFormed(symbol));
        assertRejected(
            newToken(), SYMBOL, string(symbol), abi.encodeWithSelector(MalformedUnderlyingSymbol.selector, symbol)
        );
    }

    function testSetUnderlyingNameMalformedReverts(bytes memory name) external {
        vm.assume(!LibSecurity.nameWellFormed(name));
        assertRejected(newToken(), NAME, string(name), abi.encodeWithSelector(MalformedUnderlyingName.selector, name));
    }

    function testSetUnderlyingIsinMalformedReverts(string memory isin) external {
        vm.assume(!LibSecurity.isinWellFormed(isin));
        assertRejected(newToken(), ISIN, isin, abi.encodeWithSelector(MalformedUnderlyingIsin.selector, isin));
    }

    /// The values `StoxReceiptVaultUnderlyingTest` shows `setUnderlying` refusing.
    function testSingleFieldSettersRejectWhatSetUnderlyingRejects() external {
        StoxReceiptVault token = newToken();
        string[4] memory symbols = ["", "nvda", "NV DA", "AAAAAAAAAAAAAAAAA"];
        for (uint256 i = 0; i < symbols.length; i++) {
            assertRejected(
                token, SYMBOL, symbols[i], abi.encodeWithSelector(MalformedUnderlyingSymbol.selector, symbols[i])
            );
        }
        string[6] memory names = [
            "",
            "NVIDIA \"Corporation\"",
            "NVIDIA\\Corporation",
            "NVIDIA\nCorporation",
            "NVIDIA (ST0x)",
            "NVIDIA Corporation (ST0x)"
        ];
        for (uint256 i = 0; i < names.length; i++) {
            assertRejected(token, NAME, names[i], abi.encodeWithSelector(MalformedUnderlyingName.selector, names[i]));
        }
        string[3] memory isins = ["", "US67066G1041", "us67066g1040"];
        for (uint256 i = 0; i < isins.length; i++) {
            assertRejected(token, ISIN, isins[i], abi.encodeWithSelector(MalformedUnderlyingIsin.selector, isins[i]));
        }
    }

    function testSetUnderlyingSymbolTickerLengthBoundary() external {
        StoxReceiptVault token = newToken();
        assertRejected(
            token,
            SYMBOL,
            "ABCDEFGHIJKLMNOPQ",
            abi.encodeWithSelector(MalformedUnderlyingSymbol.selector, "ABCDEFGHIJKLMNOPQ")
        );
        assertSetsOnlyField(token, SYMBOL, "ABCDEFGHIJKLMNOP", 100);
        assertEq(token.symbol(), "tABCDEFGHIJKLMNOP");
    }

    /// The kept ISIN is checked like a new one, so a token whose `assetId()`
    /// is "" refuses a ticker or name set.
    function testSetUnderlyingSymbolAndNameWithEmptyAssetIdRevert() external {
        StoxReceiptVault token = new OwnedStoxReceiptVault(OWNER);
        vm.store(
            address(token),
            UNDERLYING_STORAGE_LOCATION,
            bytes32(0x4e56444100000000000000000000000000000000000000000000000000000008)
        );
        vm.store(
            address(token),
            bytes32(uint256(UNDERLYING_STORAGE_LOCATION) + 1),
            bytes32(0x4e5649444941000000000000000000000000000000000000000000000000000c)
        );
        string[3] memory before = current(token);
        assertEq(before[SYMBOL], "NVDA");
        assertEq(before[NAME], "NVIDIA");
        assertEq(before[ISIN], "");

        vm.expectRevert(abi.encodeWithSelector(MalformedUnderlyingIsin.selector, ""));
        vm.prank(OWNER);
        IStoxUnderlyingV2(address(token)).setUnderlyingSymbol("NVDX");

        vm.expectRevert(abi.encodeWithSelector(MalformedUnderlyingIsin.selector, ""));
        vm.prank(OWNER);
        IStoxUnderlyingV2(address(token)).setUnderlyingName("NVIDIA Holdings");

        string[3] memory got = current(token);
        for (uint256 other = 0; other < 3; other++) {
            assertEq(got[other], before[other]);
        }
        assertEq(storedTimestamp(token), 0);
    }
}
