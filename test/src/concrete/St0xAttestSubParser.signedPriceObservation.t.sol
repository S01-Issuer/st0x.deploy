// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Strings} from "@openzeppelin-contracts-5.7.0/utils/Strings.sol";
import {ECDSA} from "@openzeppelin-contracts-5.7.0/utils/cryptography/ECDSA.sol";
import {SignedContextV2} from "rainlang-0.2.32/src/interface/IInterpreterCallerV5.sol";
import {InvalidSignature} from "rainlang-0.2.32/src/lib/caller/LibContext.sol";
import {LibDecimalFloat, Float} from "rain-math-float-0.3.11/src/lib/LibDecimalFloat.sol";
import {LibIntOrAString, IntOrAString} from "rain-intorastring-0.1.4/src/lib/LibIntOrAString.sol";

import {St0xAttestSubParserTest} from "test/src/concrete/St0xAttestSubParserTest.sol";
import {LibSt0xAttestContext, CONTEXT_LEAD_COLUMN, CONTEXT_ATTESTOR_0_COLUMN} from "src/lib/LibSt0xAttestContext.sol";

/// @dev Signer of both observations.
address constant OBSERVATION_SIGNER = 0xC2163A2289a988ae9dF2eAd74F69a10941AA4f2b;
/// @dev Domain separator both observations are signed under.
bytes32 constant OBSERVATION_DOMAIN = 0x7fcea108f1d99ecebbc296ddbd0cb92b55c1f11c5124d455748e1d8a4345a5b3;
/// @dev Row 0, the symbol "AAPL" as an IntOrAString.
bytes32 constant OBSERVATION_SYMBOL = 0x0000000000000000000000000000000000000000000000000000004141504ce4;
/// @dev Row 1, the price as a Rain Float.
bytes32 constant OBSERVATION_PRICE = 0xfffffffe0000000000000000000000000000000000000000000000000000869f;
/// @dev Row 2, the time.
bytes32 constant OBSERVATION_TIME = 0x000000000000000000000000000000000000000000000000000000006ae3de00;
/// @dev Row 3 of the alpaca observation, its source as an IntOrAString.
bytes32 constant ALPACA_SOURCE = 0x00000000000000000000000000000000000000000000000000616c70616361e6;
/// @dev Row 3 of the yahoo observation, its source as an IntOrAString.
bytes32 constant YAHOO_SOURCE = 0x00000000000000000000000000000000000000000000000000007961686f6fe5;
/// @dev Row 4, the currency as an IntOrAString.
bytes32 constant OBSERVATION_CURRENCY = 0x00000000000000000000000000000000000000000000000000000000555344e3;
/// @dev Rows in an observation's context.
uint256 constant OBSERVATION_ROWS = 5;
/// @dev The alpaca observation's signature.
bytes constant ALPACA_SIGNATURE =
    hex"58352b32393cd5a39ff2b610552cd268e09be9699afa27ee9b5ae452335f7b2765b280e463bedad681f90af1b73e9f3a1edbcd3c5558743a23f214cad28442a31c";
/// @dev The yahoo observation's signature.
bytes constant YAHOO_SIGNATURE =
    hex"6373f5109611983aa5ebaa3893020214e3abd67baeb27d0ed0c563e1352004631b3e190a622a87104fdecafbcb27fd7e72a04e0114bf0b5a1e701f37459bc5141c";

/// @title St0xAttestSubParserSignedPriceObservationTest
/// @notice The two signed AAPL observations `GET
/// https://proof-of-reserves.org/v1/prices/AAPL` returned on 2026-11-01, byte
/// for byte, with alpaca as the lead and yahoo as attestor 0.
contract St0xAttestSubParserSignedPriceObservationTest is St0xAttestSubParserTest {
    using Strings for address;

    function observationContext(bytes32 source) internal pure returns (bytes32[] memory) {
        bytes32[] memory context = new bytes32[](OBSERVATION_ROWS);
        context[0] = OBSERVATION_SYMBOL;
        context[1] = OBSERVATION_PRICE;
        context[2] = OBSERVATION_TIME;
        context[3] = source;
        context[4] = OBSERVATION_CURRENCY;
        return context;
    }

    function observations() internal pure returns (SignedContextV2[] memory) {
        SignedContextV2[] memory attestations = new SignedContextV2[](2);
        attestations[0] = SignedContextV2({
            signer: OBSERVATION_SIGNER,
            domainSeparator: OBSERVATION_DOMAIN,
            context: observationContext(ALPACA_SOURCE),
            signature: ALPACA_SIGNATURE
        });
        attestations[1] = SignedContextV2({
            signer: OBSERVATION_SIGNER,
            domainSeparator: OBSERVATION_DOMAIN,
            context: observationContext(YAHOO_SOURCE),
            signature: YAHOO_SIGNATURE
        });
        return attestations;
    }

    function buildExternal(SignedContextV2[] memory attestations) external view returns (bytes32[][] memory) {
        return LibSt0xAttestContext.build(symbol("tAAPL"), float(1), attestations);
    }

    function toString(bytes32 value) internal pure returns (string memory) {
        return LibIntOrAString.toStringV3(IntOrAString.wrap(uint256(value)));
    }

    /// Each signature recovers the signer from the EIP-712 digest under the
    /// observation's own domain separator, independently of `LibContext`.
    function testObservationSignaturesRecoverTheSigner() external pure {
        SignedContextV2[] memory attestations = observations();
        for (uint256 i = 0; i < attestations.length; i++) {
            assertEq(
                ECDSA.recover(
                    digest(OBSERVATION_DOMAIN, OBSERVATION_SIGNER, attestations[i].context), attestations[i].signature
                ),
                OBSERVATION_SIGNER
            );
        }
    }

    /// The observations verify in `LibContext.buildV2`, and every word reads
    /// the signed value back: the signer, the domain, "AAPL", 344.63,
    /// 1793318400, "alpaca" for the lead and "yahoo" for attestor 0, and
    /// "USD".
    function testObservationsVerifyAndReadThroughTheWords() external view {
        bytes32[][] memory context = LibSt0xAttestContext.build(symbol("tAAPL"), float(1), observations());

        checkWord("lead()", context, signer(OBSERVATION_SIGNER));
        checkWord("attestor<0>()", context, signer(OBSERVATION_SIGNER));
        checkWord("lead-domain()", context, OBSERVATION_DOMAIN);
        checkWord("attestor-domain<0>()", context, OBSERVATION_DOMAIN);

        bytes32 leadSource = evalWord("lead-source()", context);
        assertEq(leadSource, ALPACA_SOURCE, "lead-source");
        assertEq(leadSource, symbol("alpaca"), "lead-source");
        assertEq(toString(leadSource), "alpaca", "lead-source");

        bytes32 attestedSource = evalWord("attested-source<0>()", context);
        assertEq(attestedSource, YAHOO_SOURCE, "attested-source");
        assertEq(attestedSource, symbol("yahoo"), "attested-source");
        assertEq(toString(attestedSource), "yahoo", "attested-source");

        string[2] memory currencyWords = [string("lead-currency()"), "attested-currency<0>()"];
        for (uint256 i = 0; i < 2; i++) {
            bytes32 currency = evalWord(currencyWords[i], context);
            assertEq(currency, OBSERVATION_CURRENCY, currencyWords[i]);
            assertEq(currency, symbol("USD"), currencyWords[i]);
            assertEq(toString(currency), "USD", currencyWords[i]);
        }

        string[2] memory symbolWords = [string("lead-symbol()"), "attested-symbol<0>()"];
        string[2] memory priceWords = [string("lead-price()"), "attested-price<0>()"];
        string[2] memory timeWords = [string("lead-time()"), "attested-time<0>()"];
        for (uint256 i = 0; i < 2; i++) {
            bytes32 attestedSymbol = evalWord(symbolWords[i], context);
            assertEq(attestedSymbol, symbol("AAPL"), symbolWords[i]);
            assertEq(toString(attestedSymbol), "AAPL", symbolWords[i]);

            Float price = Float.wrap(evalWord(priceWords[i], context));
            (int256 coefficient, int256 exponent) = LibDecimalFloat.unpack(price);
            assertEq(coefficient, 34463, priceWords[i]);
            assertEq(exponent, -2, priceWords[i]);
            assertTrue(LibDecimalFloat.eq(price, LibDecimalFloat.packLossless(34463, -2)), priceWords[i]);

            Float time = Float.wrap(evalWord(timeWords[i], context));
            assertTrue(LibDecimalFloat.eq(time, LibDecimalFloat.packLossless(1793318400, 0)), timeWords[i]);
            assertEq(LibDecimalFloat.toFixedDecimalLossless(time, 0), 1793318400, timeWords[i]);
        }

        parseAndEval(
            bytes(
                string.concat(
                    usingWords(),
                    ":ensure(binary-equal-to(lead() ",
                    OBSERVATION_SIGNER.toHexString(),
                    ") \"lead\"),\n",
                    ":ensure(binary-equal-to(attestor<0>() ",
                    OBSERVATION_SIGNER.toHexString(),
                    ") \"attestor\"),\n",
                    ":ensure(binary-equal-to(lead-symbol() \"AAPL\") \"lead-symbol\"),\n",
                    ":ensure(binary-equal-to(attested-symbol<0>() \"AAPL\") \"attested-symbol\"),\n",
                    ":ensure(equal-to(lead-price() 344.63) \"lead-price\"),\n",
                    ":ensure(equal-to(attested-price<0>() 344.63) \"attested-price\"),\n",
                    ":ensure(equal-to(lead-time() 1793318400) \"lead-time\"),\n",
                    ":ensure(equal-to(attested-time<0>() 1793318400) \"attested-time\"),\n",
                    ":ensure(binary-equal-to(lead-source() \"alpaca\") \"lead-source\"),\n",
                    ":ensure(binary-equal-to(attested-source<0>() \"yahoo\") \"attested-source\"),\n",
                    ":ensure(binary-equal-to(lead-currency() \"USD\") \"lead-currency\"),\n",
                    ":ensure(binary-equal-to(attested-currency<0>() \"USD\") \"attested-currency\");"
                )
            ),
            context
        );
    }

    /// The grid carries each observation whole, and the two observations,
    /// which differ only at the source, are told apart by the source words
    /// alone.
    function testObservationsDifferOnlyAtTheSource() external view {
        bytes32[][] memory context = LibSt0xAttestContext.build(symbol("tAAPL"), float(1), observations());

        assertEq(context[CONTEXT_LEAD_COLUMN], observationContext(ALPACA_SOURCE));
        assertEq(context[CONTEXT_ATTESTOR_0_COLUMN], observationContext(YAHOO_SOURCE));

        assertTrue(evalWord("lead-source()", context) != evalWord("attested-source<0>()", context));
        assertEq(evalWord("lead-symbol()", context), evalWord("attested-symbol<0>()", context));
        assertEq(evalWord("lead-price()", context), evalWord("attested-price<0>()", context));
        assertEq(evalWord("lead-time()", context), evalWord("attested-time<0>()", context));
        assertEq(evalWord("lead-currency()", context), evalWord("attested-currency<0>()", context));
    }

    /// An observation of AAPL at 344.63 that names another source and
    /// currency reads them back, and the symbol, price and time beside them
    /// are undisturbed.
    function testObservationSourceAndCurrencyReadBack(bytes32 source, bytes32 currency) external view {
        bytes32[] memory values = observationContext(source);
        values[4] = currency;
        SignedContextV2[] memory attestations = new SignedContextV2[](2);
        attestations[0] = sign(LEAD_KEY, values);
        attestations[1] = sign(OPERATOR_KEY_0, values);
        bytes32[][] memory context = LibSt0xAttestContext.build(symbol("tAAPL"), float(1), attestations);

        checkWord("lead-symbol()", context, OBSERVATION_SYMBOL);
        checkWord("lead-price()", context, OBSERVATION_PRICE);
        checkWord("lead-time()", context, OBSERVATION_TIME);
        checkWord("lead-source()", context, source);
        checkWord("lead-currency()", context, currency);
        checkWord("attested-symbol<0>()", context, OBSERVATION_SYMBOL);
        checkWord("attested-price<0>()", context, OBSERVATION_PRICE);
        checkWord("attested-time<0>()", context, OBSERVATION_TIME);
        checkWord("attested-source<0>()", context, source);
        checkWord("attested-currency<0>()", context, currency);
    }

    function tamperContext(uint256 index, uint256 row, uint256 byteIndex, uint8 mask)
        internal
        pure
        returns (SignedContextV2[] memory)
    {
        SignedContextV2[] memory attestations = observations();
        attestations[index].context[row] ^= bytes32(uint256(mask) << (8 * (31 - byteIndex)));
        return attestations;
    }

    function tamperDomain(uint256 index, uint256 byteIndex, uint8 mask)
        internal
        pure
        returns (SignedContextV2[] memory)
    {
        SignedContextV2[] memory attestations = observations();
        attestations[index].domainSeparator ^= bytes32(uint256(mask) << (8 * (31 - byteIndex)));
        return attestations;
    }

    /// Flipping any bit of any byte of any row of either observation fails its
    /// signature, naming the observation.
    function testObservationEveryTamperedContextByteReverts() external {
        for (uint256 index = 0; index < 2; index++) {
            for (uint256 row = 0; row < OBSERVATION_ROWS; row++) {
                for (uint256 byteIndex = 0; byteIndex < 32; byteIndex++) {
                    SignedContextV2[] memory attestations = tamperContext(index, row, byteIndex, 0x01);
                    vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector, index));
                    this.buildExternal(attestations);
                }
            }
        }
    }

    /// Flipping the low bit of any byte of either observation's domain
    /// separator fails its signature, naming the observation.
    function testObservationEveryTamperedDomainByteReverts() external {
        for (uint256 index = 0; index < 2; index++) {
            for (uint256 byteIndex = 0; byteIndex < 32; byteIndex++) {
                SignedContextV2[] memory attestations = tamperDomain(index, byteIndex, 0x01);
                vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector, index));
                this.buildExternal(attestations);
            }
        }
    }

    /// Any change to any byte of any row fails the signature.
    function testObservationTamperedContextByteRevertsFuzz(uint8 index, uint8 row, uint8 byteIndex, uint8 mask)
        external
    {
        index = uint8(bound(index, 0, 1));
        row = uint8(bound(row, 0, OBSERVATION_ROWS - 1));
        byteIndex = uint8(bound(byteIndex, 0, 31));
        mask = uint8(bound(mask, 1, type(uint8).max));
        SignedContextV2[] memory attestations = tamperContext(index, row, byteIndex, mask);
        vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector, index));
        this.buildExternal(attestations);
    }

    /// Any change to any byte of the domain separator fails the signature.
    function testObservationTamperedDomainByteRevertsFuzz(uint8 index, uint8 byteIndex, uint8 mask) external {
        index = uint8(bound(index, 0, 1));
        byteIndex = uint8(bound(byteIndex, 0, 31));
        mask = uint8(bound(mask, 1, type(uint8).max));
        SignedContextV2[] memory attestations = tamperDomain(index, byteIndex, mask);
        vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector, index));
        this.buildExternal(attestations);
    }
}
