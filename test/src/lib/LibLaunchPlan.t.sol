// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibUtcDate} from "../../../src/lib/LibUtcDate.sol";
import {
    LibLaunchPlan,
    LaunchMetadata,
    PlanContext,
    TokenPlan,
    DedicatedPin,
    AssetType,
    MissingPrimaryTicker,
    InvalidTicker,
    UnsupportedAssetType,
    MissingName,
    NameIsTicker,
    UnicodeWhitespaceInName,
    InvalidCountryIso,
    InvalidIsin,
    InvalidCounterparties,
    OwnerNotAllowlisted,
    DedicatedPinWrongChain,
    DedicatedAuthoriserUnset,
    DedicatedAuthoriserIsShared,
    DedicatedMinterUnset,
    DedicatedDeployBlockUnset,
    DedicatedAuthoriserNotAllowlisted
} from "../../../src/lib/LibLaunchPlan.sol";
import {LibLaunchPlanHarness} from "../../concrete/LibLaunchPlanHarness.sol";

/// @title LibLaunchPlanTest
/// @notice Every case of sft-ops `tests/cd-plan.test.ts`, with the same inputs
/// and the same accept, skip or reject outcome.
contract LibLaunchPlanTest is Test {
    address constant OWNER_SAFE = 0xe70d821f3462a074e63b42d0AaC6523faAe1d611;
    address constant SHARED = 0x315b16faa6eE413faBCa877d3851B3818369f0cD;
    address constant DEDICATED = 0x1111111111111111111111111111111111111111;
    address constant MINTER = 0x0958d9E94D9D4139280947ACd86D4a50F13bfA8C;

    /// @dev `new Date('2026-08-19T12:00:00.000Z')`.
    uint256 constant NOW = 1787140800;

    LibLaunchPlanHarness internal harness;

    function setUp() external {
        harness = new LibLaunchPlanHarness();
    }

    function _usCounterparties() internal pure returns (string[] memory names) {
        names = new string[](2);
        names[0] = "AlpacaDB Inc";
        names[1] = "Clear Street LLC";
    }

    function _nonUsCounterparties() internal pure returns (string[] memory names) {
        names = new string[](3);
        names[0] = "AlpacaDB Inc";
        names[1] = "Clear Street LLC";
        names[2] = "Freedom Finance";
    }

    function _hood() internal pure returns (LaunchMetadata memory m) {
        m.primaryTicker = "HOOD";
        m.assetType = "Equity";
        m.name = "Robinhood Markets Inc";
        m.isin = "US7707001027";
        m.countryIso = "US";
        m.counterparties = _usCounterparties();
    }

    function _lvmh() internal pure returns (LaunchMetadata memory m) {
        m = _hood();
        m.primaryTicker = "MC";
        m.name = unicode"LVMH Moët Hennessy Louis Vuitton SE";
        m.isin = "FR0000121014";
        m.countryIso = "FR";
        m.counterparties = _nonUsCounterparties();
    }

    function _ctx() internal pure returns (PlanContext memory ctx) {
        ctx.allowlistedOwners = new address[](1);
        ctx.allowlistedOwners[0] = OWNER_SAFE;
        ctx.ownerSafe = OWNER_SAFE;
        ctx.sharedAuthoriser = SHARED;
        ctx.now = NOW;
    }

    function _pinned() internal pure returns (DedicatedPin memory pin) {
        pin.symbol = "tMC";
        pin.chainId = 8453;
        pin.authoriser = "0x1111111111111111111111111111111111111111";
        pin.minter = "0x0958d9E94D9D4139280947ACd86D4a50F13bfA8C";
        pin.deployBlock = 41_000_000;
    }

    function _lvmhCtx(DedicatedPin memory pin, bool allowlisted) internal pure returns (PlanContext memory ctx) {
        ctx = _ctx();
        ctx.pins = new DedicatedPin[](1);
        ctx.pins[0] = pin;
        ctx.allowlistedAuthorisers = new address[](allowlisted ? 1 : 0);
        if (allowlisted) ctx.allowlistedAuthorisers[0] = DEDICATED;
    }

    function _plan(LaunchMetadata memory m) internal view returns (TokenPlan memory p) {
        bool skipped;
        (skipped, p) = harness.planOne("launch/metadata/hood.json", m, _ctx());
        assertFalse(skipped);
    }

    function _shipped(string memory symbol) internal pure returns (PlanContext memory ctx) {
        ctx = _ctx();
        ctx.shippedSymbols = new string[](1);
        ctx.shippedSymbols[0] = symbol;
    }

    // cd-plan derivation

    function testDerivesEveryArgumentFromTheMetadataFile() external view {
        TokenPlan memory p = _plan(_hood());
        assertEq(p.metadataFile, "launch/metadata/hood.json");
        assertEq(p.symbol, "tHOOD");
        assertEq(p.name, "Robinhood Markets Inc ST0x");
        assertTrue(p.assetType == AssetType.Equity);
        assertEq(LibUtcDate.toIsoDate(p.certifyUntil), "2027-08-19");
        assertEq(p.certifyUntil % 86400, 0);
        assertEq(p.intendedOwner, OWNER_SAFE);
        assertEq(p.landingAuthoriser, SHARED);
        assertFalse(p.dedicated);
    }

    /// @notice PTY is a closed-end fund carrying asset_type "ETF" precisely so
    /// this holds.
    function testMapsEtfAssetTypeToTheEtfSchema() external view {
        LaunchMetadata memory m = _hood();
        m.primaryTicker = "PTY";
        m.assetType = " \x0bETF\x0c ";
        assertTrue(_plan(m).assetType == AssetType.Etf);
    }

    function testFoldsAdrParenthesisation() external view {
        LaunchMetadata memory m = _hood();
        m.primaryTicker = "TSM";
        m.name = "Taiwan Semiconductor Manufacturing Company Limited (ADR)";
        m.isin = "US8740391003";
        m.countryIso = "TW";
        assertEq(_plan(m).name, "Taiwan Semiconductor Manufacturing Company Limited ADR ST0x");
    }

    // cd-plan refusals

    function testSkipsATokenAlreadyInTheLedger() external view {
        (bool skipped,) = harness.planOne("launch/metadata/hood.json", _hood(), _shipped("thood"));
        assertTrue(skipped);
    }

    /// @notice The ledger symbols are lower-cased on load, so a ledger row
    /// `THOOD` skips `tHOOD`.
    function testSkipIsCaseInsensitive() external view {
        LaunchMetadata memory m = _hood();
        m.primaryTicker = "hood";
        (bool skipped,) = harness.planOne("launch/metadata/hood.json", m, _shipped("thood"));
        assertTrue(skipped);
    }

    function testRejectsAnUnknownAssetType() external {
        LaunchMetadata memory m = _hood();
        m.assetType = "Fund";
        vm.expectRevert(abi.encodeWithSelector(UnsupportedAssetType.selector, "Fund"));
        harness.planOne("f", m, _ctx());
    }

    function testRejectsAnEmptyCountryIso() external {
        LaunchMetadata memory m = _hood();
        m.countryIso = "";
        vm.expectRevert(abi.encodeWithSelector(InvalidCountryIso.selector, ""));
        harness.planOne("f", m, _ctx());
    }

    function testRejectsMalformedCountryIso() external {
        string[4] memory malformed = ["us", "USA", "U1", "1S"];
        for (uint256 i = 0; i < malformed.length; i++) {
            LaunchMetadata memory metadata = _hood();
            metadata.countryIso = malformed[i];
            vm.expectRevert(abi.encodeWithSelector(InvalidCountryIso.selector, malformed[i]));
            harness.planOne("f", metadata, _ctx());
        }
    }

    function testRejectsAMalformedIsin() external {
        string[8] memory malformed = [
            "US770700102",
            "US770700102X",
            "US77070010-7",
            "U17707001027",
            "1S7707001027",
            "US77070010270",
            "US-707001027",
            "US 707001027"
        ];
        for (uint256 i = 0; i < malformed.length; i++) {
            LaunchMetadata memory metadata = _hood();
            metadata.isin = malformed[i];
            vm.expectRevert(abi.encodeWithSelector(InvalidIsin.selector, malformed[i]));
            harness.planOne("f", metadata, _ctx());
        }
    }

    function testUpperCasesTheIsinBeforeChecking() external view {
        LaunchMetadata memory m = _hood();
        m.isin = " us7707001027 ";
        _plan(m);
    }

    function testRejectsTheRetiredCounterpartySet() external {
        LaunchMetadata memory m = _hood();
        m.counterparties = new string[](3);
        m.counterparties[0] = "AlpacaDB Inc";
        m.counterparties[1] = "Charles Schwab & Co., Inc.";
        m.counterparties[2] = "Freedom Finance";
        vm.expectRevert(InvalidCounterparties.selector);
        harness.planOne("f", m, _ctx());
    }

    function testAcceptsCounterpartiesInEitherOrder() external view {
        LaunchMetadata memory m = _hood();
        m.counterparties[0] = "Clear Street LLC";
        m.counterparties[1] = "AlpacaDB Inc";
        _plan(m);
    }

    function testAcceptsTheNonUsCounterpartySet() external view {
        LaunchMetadata memory m = _hood();
        m.counterparties = _nonUsCounterparties();
        _plan(m);
    }

    function testRejectsFreedomFinanceWithoutTheUsPair() external {
        LaunchMetadata memory m = _hood();
        m.counterparties[1] = "Freedom Finance";
        vm.expectRevert(InvalidCounterparties.selector);
        harness.planOne("f", m, _ctx());
    }

    function testRejectsAMissingPrimaryTicker() external {
        LaunchMetadata memory m = _hood();
        m.primaryTicker = "";
        vm.expectRevert(MissingPrimaryTicker.selector);
        harness.planOne("f", m, _ctx());
    }

    function testRejectsATickerThatIsNotAPlainSymbol() external {
        string[4] memory bad = ["A;B", "../X", "A B", "X$(Y)"];
        for (uint256 i = 0; i < bad.length; i++) {
            LaunchMetadata memory m = _hood();
            m.primaryTicker = bad[i];
            vm.expectRevert(abi.encodeWithSelector(InvalidTicker.selector, bad[i]));
            harness.planOne("f", m, _ctx());
        }
    }

    function testAcceptsDottedAndDashedTickers() external view {
        LaunchMetadata memory m = _hood();
        m.primaryTicker = "air.pa";
        m.countryIso = "FR";
        m.isin = "NL0000235190";
        assertEq(_plan(m).symbol, "tAIR.PA");
        m.primaryTicker = "BRK-B";
        assertEq(_plan(m).symbol, "tBRK-B");
        m.primaryTicker = "7203.T";
        assertEq(_plan(m).symbol, "t7203.T");
    }

    function testRejectsAMissingName() external {
        LaunchMetadata memory m = _hood();
        m.name = "  ";
        vm.expectRevert(MissingName.selector);
        harness.planOne("f", m, _ctx());
    }

    /// @notice The tQQQM/tVWO/tARKK redeploys.
    function testRefusesANameThatIsTheTokenSymbol() external {
        LaunchMetadata memory m = _hood();
        m.primaryTicker = "QQQM";
        m.name = "tQQQM";
        vm.expectRevert(abi.encodeWithSelector(NameIsTicker.selector, "tQQQM"));
        harness.planOne("f", m, _ctx());
    }

    function testRefusesANameThatIsTheBareTicker() external {
        LaunchMetadata memory m = _hood();
        m.primaryTicker = "QQQM";
        m.name = "QQQM";
        vm.expectRevert(abi.encodeWithSelector(NameIsTicker.selector, "QQQM"));
        harness.planOne("f", m, _ctx());
    }

    function testRefusesAnOwnerThatIsNotAllowlisted() external {
        PlanContext memory ctx = _ctx();
        ctx.allowlistedOwners = new address[](0);
        vm.expectRevert(abi.encodeWithSelector(OwnerNotAllowlisted.selector, OWNER_SAFE));
        harness.planOne("f", _hood(), ctx);
    }

    // cd-plan dedicated authorisers

    function testCarriesTheDedicatedAuthoriserAndMinterIntoThePlan() external view {
        (bool skipped, TokenPlan memory p) =
            harness.planOne("launch/metadata/mc.json", _lvmh(), _lvmhCtx(_pinned(), true));
        assertFalse(skipped);
        assertEq(p.symbol, "tMC");
        assertEq(p.name, unicode"LVMH Moët Hennessy Louis Vuitton SE ST0x");
        assertTrue(p.dedicated);
        assertEq(p.landingAuthoriser, DEDICATED);
        assertEq(p.dedicatedMinter, MINTER);
        assertEq(p.dedicatedDeployBlock, 41_000_000);
        assertFalse(p.dedicatedMinterGrantPending);
    }

    function testMatchesThePinCaseInsensitively() external view {
        DedicatedPin memory pin = _pinned();
        pin.symbol = "TMC";
        LaunchMetadata memory m = _lvmh();
        m.primaryTicker = "mc";
        (, TokenPlan memory p) = harness.planOne("f", m, _lvmhCtx(pin, true));
        assertEq(p.landingAuthoriser, DEDICATED);
    }

    function testLeavesUnpinnedTokensOnTheSharedAuthoriser() external view {
        TokenPlan memory p = _plan(_hood());
        assertFalse(p.dedicated);
        assertEq(p.landingAuthoriser, SHARED);
        assertEq(p.dedicatedMinter, address(0));
    }

    function testRefusesAZeroPlaceholderAuthoriser() external {
        DedicatedPin memory pin = _pinned();
        pin.authoriser = "0x0000000000000000000000000000000000000000";
        vm.expectRevert(abi.encodeWithSelector(DedicatedAuthoriserUnset.selector, "tMC", pin.authoriser));
        harness.planOne("f", _lvmh(), _lvmhCtx(pin, true));
    }

    function testRefusesAnUnsetOrMalformedAuthoriser() external {
        string[4] memory bad = [
            "",
            "0xnot-an-address",
            // Mixed case with a bad EIP-55 checksum.
            "0xA111111111111111111111111111111111111111",
            "0x11111111111111111111111111111111111111"
        ];
        for (uint256 i = 0; i < bad.length; i++) {
            DedicatedPin memory pin = _pinned();
            pin.authoriser = bad[i];
            vm.expectRevert(abi.encodeWithSelector(DedicatedAuthoriserUnset.selector, "tMC", bad[i]));
            harness.planOne("f", _lvmh(), _lvmhCtx(pin, true));
        }
    }

    function testAcceptsAnAllLowerCaseOrChecksummedAddress() external pure {
        (bool ok, address parsed) = LibLaunchPlan.parseSetAddress("0x0958d9e94d9d4139280947acd86d4a50f13bfa8c");
        assertTrue(ok);
        assertEq(parsed, MINTER);
        (ok, parsed) = LibLaunchPlan.parseSetAddress("0x0958d9E94D9D4139280947ACd86D4a50F13bfA8C");
        assertTrue(ok);
        assertEq(parsed, MINTER);
        (ok,) = LibLaunchPlan.parseSetAddress("0x0958D9E94D9D4139280947ACD86D4A50F13BFA8C");
        assertFalse(ok);
    }

    function testRefusesAPinThatPointsAtTheSharedAuthoriser() external {
        DedicatedPin memory pin = _pinned();
        pin.authoriser = "0x315b16faa6eE413faBCa877d3851B3818369f0cD";
        PlanContext memory ctx = _lvmhCtx(pin, true);
        ctx.allowlistedAuthorisers[0] = SHARED;
        vm.expectRevert(abi.encodeWithSelector(DedicatedAuthoriserIsShared.selector, "tMC"));
        harness.planOne("f", _lvmh(), ctx);
    }

    function testRefusesADedicatedAuthoriserThatIsNotAllowlisted() external {
        vm.expectRevert(abi.encodeWithSelector(DedicatedAuthoriserNotAllowlisted.selector, "tMC", DEDICATED));
        harness.planOne("f", _lvmh(), _lvmhCtx(_pinned(), false));
    }

    function testRefusesAnUnsetMinter() external {
        DedicatedPin memory pin = _pinned();
        pin.minter = "0x0000000000000000000000000000000000000000";
        vm.expectRevert(abi.encodeWithSelector(DedicatedMinterUnset.selector, "tMC", pin.minter));
        harness.planOne("f", _lvmh(), _lvmhCtx(pin, true));
    }

    function testRefusesAPinForAChainOtherThanBase() external {
        DedicatedPin memory pin = _pinned();
        pin.chainId = 1;
        vm.expectRevert(abi.encodeWithSelector(DedicatedPinWrongChain.selector, "tMC", 1));
        harness.planOne("f", _lvmh(), _lvmhCtx(pin, true));
    }

    function testStillSkipsAPinnedTokenThatHasAlreadyShipped() external view {
        DedicatedPin memory pin = _pinned();
        pin.authoriser = "0x0000000000000000000000000000000000000000";
        PlanContext memory ctx = _lvmhCtx(pin, true);
        ctx.shippedSymbols = new string[](1);
        ctx.shippedSymbols[0] = "tmc";
        (bool skipped,) = harness.planOne("f", _lvmh(), ctx);
        assertTrue(skipped);
    }

    function testPassesTheGrantPendingFlagOnlyWhenThePinSaysSo() external view {
        DedicatedPin memory pin = _pinned();
        pin.minterGrantPending = true;
        (, TokenPlan memory p) = harness.planOne("f", _lvmh(), _lvmhCtx(pin, true));
        assertTrue(p.dedicatedMinterGrantPending);
        (, p) = harness.planOne("f", _lvmh(), _lvmhCtx(_pinned(), true));
        assertFalse(p.dedicatedMinterGrantPending);
    }

    /// @notice The loader reads a missing, negative or fractional
    /// `deployBlock` as zero.
    function testRefusesAPinWithoutTheAuthoriserDeployBlock() external {
        DedicatedPin memory pin = _pinned();
        pin.deployBlock = 0;
        vm.expectRevert(abi.encodeWithSelector(DedicatedDeployBlockUnset.selector, "tMC"));
        harness.planOne("f", _lvmh(), _lvmhCtx(pin, true));
    }

    // normaliseAdrName

    function testNormaliseAdrNameLeavesAPlainNameUntouched() external pure {
        assertEq(LibLaunchPlan.normaliseAdrName("Apple Inc."), "Apple Inc.");
    }

    function testNormaliseAdrNameUnwrapsOnlyAdrAndAds() external pure {
        assertEq(LibLaunchPlan.normaliseAdrName("Foo (AXR)"), "Foo (AXR)");
        assertEq(LibLaunchPlan.normaliseAdrName("Foo (BDR)"), "Foo (BDR)");
        assertEq(LibLaunchPlan.normaliseAdrName("Foo (ADX)"), "Foo (ADX)");
    }

    function testIsTickerAcceptsExactlyTheAllowedBytes() external pure {
        for (uint256 i = 0; i < 256; i++) {
            // i stays in 0..255, so the narrowing cast loses no bits.
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes1 c = bytes1(uint8(i));
            bool allowed =
                (c >= "A" && c <= "Z") || (c >= "a" && c <= "z") || (c >= "0" && c <= "9") || c == "." || c == "-";
            assertEq(LibLaunchPlan.isTicker(string(abi.encodePacked("A", c))), allowed);
        }
    }

    function testIsIsinRejectsEveryNonAlphanumericByte() external pure {
        for (uint256 i = 0; i < 256; i++) {
            // i stays in 0..255, so the narrowing cast loses no bits.
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes1 c = bytes1(uint8(i));
            bool upper = c >= "A" && c <= "Z";
            bool digit = c >= "0" && c <= "9";
            assertEq(LibLaunchPlan.isIsin(string(abi.encodePacked("US77070010", c, "7"))), upper || digit);
            assertEq(LibLaunchPlan.isIsin(string(abi.encodePacked("US770700102", c))), digit);
        }
    }

    function testNormaliseAdrNameUnwrapsAdrAndAdsOnly() external pure {
        assertEq(LibLaunchPlan.normaliseAdrName("Foo (ADR)"), "Foo ADR");
        assertEq(LibLaunchPlan.normaliseAdrName("Foo (ADS)"), "Foo ADS");
        assertEq(LibLaunchPlan.normaliseAdrName("Foo (adr)"), "Foo adr");
        assertEq(LibLaunchPlan.normaliseAdrName("Foo (Holdings) Ltd"), "Foo (Holdings) Ltd");
        assertEq(LibLaunchPlan.normaliseAdrName("Foo (ADR Holdings) Ltd"), "Foo (ADR Holdings) Ltd");
        assertEq(LibLaunchPlan.normaliseAdrName("Foo (ADSX)"), "Foo (ADSX)");
        assertEq(LibLaunchPlan.normaliseAdrName("Foo (ADR)(ADS)"), "Foo ADRADS");
    }

    function testNormaliseAdrNameCollapsesWhitespaceRuns() external pure {
        assertEq(LibLaunchPlan.normaliseAdrName("  Foo \t  Bar (ADR) "), "Foo Bar ADR");
        assertEq(LibLaunchPlan.normaliseAdrName("Foo\tBar"), "Foo\tBar");
        assertEq(LibLaunchPlan.normaliseAdrName("Foo\n\nBar\r\rBaz"), "Foo Bar Baz");
        assertEq(LibLaunchPlan.normaliseAdrName("Foo\r\nBar"), "Foo Bar");
        assertEq(LibLaunchPlan.trim("\n\rFoo\r\n"), "Foo");
    }

    function testRejectsCounterpartySetsWithAnUnexpectedMember() external {
        string[3][4] memory invalidSets = [
            ["Apex Clearing", "Clear Street LLC", ""],
            ["AlpacaDB Inc", "Clear Street LLC", "Goldman Sachs"],
            ["Apex Clearing", "Clear Street LLC", "Freedom Finance"],
            ["AlpacaDB Inc", "AlpacaDB Inc", "Clear Street LLC"]
        ];
        for (uint256 i = 0; i < invalidSets.length; i++) {
            LaunchMetadata memory metadata = _hood();
            metadata.counterparties = new string[](bytes(invalidSets[i][2]).length == 0 ? 2 : 3);
            for (uint256 j = 0; j < metadata.counterparties.length; j++) {
                metadata.counterparties[j] = invalidSets[i][j];
            }
            vm.expectRevert(InvalidCounterparties.selector);
            harness.planOne("f", metadata, _ctx());
        }
    }

    function testParseSetAddressReturnsZeroForMissingPrefixAndBadChecksum() external pure {
        string[3] memory malformed = [
            "0958d9e94d9d4139280947acd86d4a50f13bfa8c",
            "0X0958d9e94d9d4139280947acd86d4a50f13bfa8c",
            "0xA111111111111111111111111111111111111111"
        ];
        for (uint256 i = 0; i < malformed.length; i++) {
            (bool valid, address parsed) = LibLaunchPlan.parseSetAddress(malformed[i]);
            assertFalse(valid, malformed[i]);
            assertEq(parsed, address(0), malformed[i]);
        }
    }

    function testNormaliseAdrNameHandlesTruncatedSuffixes() external pure {
        assertEq(LibLaunchPlan.normaliseAdrName("Foo (A"), "Foo (A");
        assertEq(LibLaunchPlan.normaliseAdrName("Foo (AD"), "Foo (AD");
        assertEq(LibLaunchPlan.normaliseAdrName("Foo (ADR"), "Foo (ADR");
        assertEq(LibLaunchPlan.normaliseAdrName("Foo\x0b\x0cBar\x0b"), "Foo Bar");
    }

    function testTrimsTheTickerAndCountryIso() external view {
        LaunchMetadata memory metadata = _hood();
        metadata.primaryTicker = " \tHOOD\n";
        metadata.countryIso = "\r US ";
        TokenPlan memory plan = _plan(metadata);
        assertEq(plan.symbol, "tHOOD");
        assertEq(plan.name, "Robinhood Markets Inc ST0x");
    }

    function testRejectsCounterpartyListsOfOtherSizes() external {
        uint256[3] memory sizes = [uint256(0), 1, 4];
        string[4] memory names = ["AlpacaDB Inc", "Clear Street LLC", "Freedom Finance", "Freedom Finance"];
        for (uint256 i = 0; i < sizes.length; i++) {
            LaunchMetadata memory metadata = _hood();
            metadata.counterparties = new string[](sizes[i]);
            for (uint256 j = 0; j < sizes[i]; j++) {
                metadata.counterparties[j] = names[j];
            }
            vm.expectRevert(InvalidCounterparties.selector);
            harness.planOne("f", metadata, _ctx());
        }
    }

    function testFindPinReturnsEveryFieldOfTheMatchingPin() external view {
        DedicatedPin memory other = DedicatedPin({
            symbol: "tSAP",
            chainId: 1,
            authoriser: "0x2222222222222222222222222222222222222222",
            minter: "0x3333333333333333333333333333333333333333",
            deployBlock: 7,
            minterGrantPending: true
        });
        PlanContext memory ctx = _lvmhCtx(_pinned(), true);
        ctx.pins = new DedicatedPin[](2);
        ctx.pins[0] = other;
        ctx.pins[1] = _pinned();
        (bool found, DedicatedPin memory pin) = LibLaunchPlan.findPin(ctx.pins, "TMC");
        assertTrue(found);
        assertEq(pin.symbol, "tMC");
        assertEq(pin.chainId, 8453);
        assertEq(pin.authoriser, "0x1111111111111111111111111111111111111111");
        assertEq(pin.minter, "0x0958d9E94D9D4139280947ACd86D4a50F13bfA8C");
        assertEq(pin.deployBlock, 41_000_000);
        assertFalse(pin.minterGrantPending);
        (, TokenPlan memory plan) = harness.planOne("f", _lvmh(), ctx);
        assertTrue(plan.dedicated);
        assertEq(plan.landingAuthoriser, DEDICATED);
        assertEq(plan.dedicatedMinter, MINTER);
        assertEq(plan.dedicatedDeployBlock, 41_000_000);
        assertFalse(plan.dedicatedMinterGrantPending);
        (found, pin) = LibLaunchPlan.findPin(ctx.pins, "TsAp");
        assertTrue(found);
        assertEq(pin.symbol, "tSAP");
        assertEq(pin.chainId, 1);
        assertEq(pin.authoriser, "0x2222222222222222222222222222222222222222");
        assertEq(pin.minter, "0x3333333333333333333333333333333333333333");
        assertEq(pin.deployBlock, 7);
        assertTrue(pin.minterGrantPending);
        (found,) = LibLaunchPlan.findPin(ctx.pins, "tNONE");
        assertFalse(found);
    }

    function testDedicatedAuthoriserMustBeOnTheAllowlist() external {
        DedicatedPin memory pin = _pinned();
        PlanContext memory ctx = _lvmhCtx(pin, true);
        ctx.allowlistedAuthorisers = new address[](1);
        ctx.allowlistedAuthorisers[0] = address(0xBEEF);
        vm.expectRevert(abi.encodeWithSelector(DedicatedAuthoriserNotAllowlisted.selector, "tMC", DEDICATED));
        harness.planOne("f", _lvmh(), ctx);
    }

    function testParseAssetTypeMatchesCdPlanCase() external {
        string[5] memory refused = ["etf", "Etf", "equity", "EQUITY", "E TF"];
        for (uint256 i = 0; i < refused.length; i++) {
            LaunchMetadata memory metadata = _hood();
            metadata.assetType = refused[i];
            vm.expectRevert(abi.encodeWithSelector(UnsupportedAssetType.selector, refused[i]));
            harness.planOne("f", metadata, _ctx());
        }
        LaunchMetadata memory etf = _hood();
        etf.assetType = "ETF";
        assertTrue(_plan(etf).assetType == AssetType.Etf);
    }

    function testRefusesAnOwnerMissingFromANonEmptyAllowlist() external {
        PlanContext memory ctx = _ctx();
        ctx.allowlistedOwners[0] = SHARED;
        vm.expectRevert(abi.encodeWithSelector(OwnerNotAllowlisted.selector, OWNER_SAFE));
        harness.planOne("f", _hood(), ctx);
    }

    function testContainsAddressIsExactMembership(address member, address other) external pure {
        vm.assume(member != other);
        address[] memory values = new address[](1);
        values[0] = member;
        assertTrue(LibLaunchPlan.containsAddress(values, member));
        assertFalse(LibLaunchPlan.containsAddress(values, other));
    }

    function testToUpperMapsExactlyTheLowerCaseLetters() external view {
        for (uint256 i = 0; i < 256; i++) {
            bytes1 char = bytes32(i)[31];
            bytes1 expected = (char >= "a" && char <= "z") ? bytes1(uint8(char) - 32) : char;
            assertEq(bytes(LibLaunchPlan.toUpper(string(abi.encodePacked(char))))[0], expected);
        }
        LaunchMetadata memory metadata = _hood();
        metadata.primaryTicker = "zm";
        assertEq(_plan(metadata).symbol, "tZM");
    }

    function testSortStringsPutsAPrefixFirstInEitherInputOrder() external pure {
        string[] memory values = new string[](2);
        values[0] = "AlpacaDB Inc X";
        values[1] = "AlpacaDB Inc";
        string[] memory sorted = LibLaunchPlan.sortStrings(values);
        assertEq(sorted[0], "AlpacaDB Inc");
        assertEq(sorted[1], "AlpacaDB Inc X");
        values[0] = "AlpacaDB Inc";
        values[1] = "AlpacaDB Inc X";
        sorted = LibLaunchPlan.sortStrings(values);
        assertEq(sorted[0], "AlpacaDB Inc");
        assertEq(sorted[1], "AlpacaDB Inc X");
    }

    function testRejectsACounterpartyThatExtendsAnAllowedName() external {
        LaunchMetadata memory metadata = _hood();
        metadata.counterparties[0] = "Clear Street LLC";
        metadata.counterparties[1] = "Clear Street LLC X";
        vm.expectRevert(InvalidCounterparties.selector);
        harness.planOne("f", metadata, _ctx());
    }

    function testRefusesUnicodeWhitespaceInTheName() external {
        bytes[17] memory spaces = [
            bytes(hex"c285"),
            hex"c2a0",
            hex"e19a80",
            hex"e28080",
            hex"e28081",
            hex"e28082",
            hex"e28083",
            hex"e28084",
            hex"e28085",
            hex"e28086",
            hex"e2808a",
            hex"e280a8",
            hex"e280a9",
            hex"e280af",
            hex"e2819f",
            hex"e38080",
            hex"efbbbf"
        ];
        for (uint256 i = 0; i < spaces.length; i++) {
            LaunchMetadata memory metadata = _hood();
            string memory name = string.concat("Robinhood", string(spaces[i]), "Markets Inc");
            metadata.name = string.concat(name, string(spaces[i]));
            vm.expectRevert(abi.encodeWithSelector(UnicodeWhitespaceInName.selector, metadata.name));
            harness.planOne("f", metadata, _ctx());
        }
        LaunchMetadata memory accented = _hood();
        accented.name = unicode"Moët Hennessy\u00e0 Louis Vuitton";
        assertEq(_plan(accented).name, unicode"Moët Hennessyà Louis Vuitton ST0x");
    }
}
