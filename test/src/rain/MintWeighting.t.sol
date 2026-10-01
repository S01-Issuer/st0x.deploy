// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Strings} from "@openzeppelin-contracts-5.6.1/utils/Strings.sol";
import {stdError} from "forge-std-1.16.2/src/StdError.sol";
import {Float, LibDecimalFloat} from "rain-math-float-0.2.4/src/lib/LibDecimalFloat.sol";
import {SignedContextV1} from "rainlang-interface-0.2.9/src/interface/IInterpreterCallerV4.sol";

import {LibTestDotrain, DotrainBinding} from "test/lib/LibTestDotrain.sol";
import {ST0xOrchestratorMintWeightingFixture} from "test/src/concrete/ST0xOrchestratorMintWeightingFixture.sol";

/// @title MintWeightingTest
/// @notice `src/rain/mint-weighting.rain`, the example mint weighting,
/// composed from the file, parsed, installed on a real orchestrator and run
/// by `mint`. Each check in the expression is shown refusing what it is there
/// to refuse, with nothing charged, and the mint it lets through is charged
/// `mint-amount * lead-price`.
///
/// The token is `tMSTR` and the attestations carry `MSTR`: the vault's symbol
/// is the feed's ticker behind a `t`, and the expression drops the `t`. One
/// composition is installed in `setUp` and every vault here mints through it,
/// `tAAPL` with `AAPL` attestations alongside `tMSTR` with `MSTR`. The pool
/// is six operators and the mint collects two, as the expression is written;
/// the lead is `LEAD_KEY` and operator `i` of the pool is `OPERATOR_KEY_0 +
/// i`.
contract MintWeightingTest is ST0xOrchestratorMintWeightingFixture {
    using Strings for address;
    using LibDecimalFloat for Float;

    /// One attestation before it is signed.
    struct Attestation {
        uint256 key;
        string ticker;
        Float price;
        Float time;
    }

    string internal constant SOURCE = "src/rain/mint-weighting.rain";
    string internal constant ENTRYPOINT = "weighting";

    /// The vault most tests mint, and the ticker its feed carries. Neither
    /// is in the file: the expression derives the second from the first.
    string internal constant VAULT_SYMBOL = "tMSTR";
    string internal constant TICKER = "MSTR";

    /// Another vault, minted through the same composition with its own
    /// ticker's attestations.
    address internal constant OTHER_TOKEN = address(0xA22E);
    string internal constant OTHER_VAULT_SYMBOL = "tAAPL";
    string internal constant OTHER_TICKER = "AAPL";

    /// A vault mocked by the test that needs it, with whatever symbol that
    /// test is about.
    address internal constant ANY_TOKEN = address(0xA33E);

    /// The values bound to the file's elided bindings.
    uint256 internal constant POOL_SIZE = 6;
    string internal constant MAX_DEVIATION = "0.01";
    int256 internal constant MAX_TIME_SPREAD = 600;
    int256 internal constant MIN_PRICE = 100;
    int256 internal constant MAX_PRICE = 1000;

    /// An operator outside the pool.
    uint256 internal constant UNLISTED_KEY = OPERATOR_KEY_0 + POOL_SIZE;

    /// The chain clock. Somewhere realistic, so a stale time is not negative.
    int256 internal constant NOW = 1_760_000_000;

    /// The composed Rainlang, for the tests to read.
    string internal rainlang;

    /// Mints so far, so a test minting the same thing twice has a fresh
    /// nonce each time.
    uint256 internal mints;

    /// @inheritdoc ST0xOrchestratorMintWeightingFixture
    function tokenSymbol() internal pure override returns (string memory) {
        return VAULT_SYMBOL;
    }

    function setUp() public override {
        super.setUp();
        // NOW is a positive literal, held as int256 for the attested times.
        // forge-lint: disable-next-line(unsafe-typecast)
        vm.warp(uint256(NOW));
        rainlang = LibTestDotrain.compose(vm.readFile(SOURCE), ENTRYPOINT, _bindings());
        _install(_evaluable(rainlang));
        _setLimits(CAPACITY, CAPACITY);
        _mockToken(OTHER_TOKEN, OTHER_VAULT_SYMBOL);
    }

    // ------------------------------------------------------------------ //
    //                              Helpers                               //
    // ------------------------------------------------------------------ //

    /// Every elided binding in the file, bound to this test's values.
    function _bindings() internal view returns (DotrainBinding[] memory bindings) {
        bindings = new DotrainBinding[](6 + POOL_SIZE);
        bindings[0] = DotrainBinding("st0x-attest-subparser", address(I_SUB_PARSER).toHexString());
        bindings[1] = DotrainBinding("lead-signer", vm.addr(LEAD_KEY).toHexString());
        for (uint256 i = 0; i < POOL_SIZE; i++) {
            bindings[2 + i] = DotrainBinding(string.concat("operator-", vm.toString(i + 1)), _operator(i).toHexString());
        }
        bindings[2 + POOL_SIZE] = DotrainBinding("max-deviation", MAX_DEVIATION);
        bindings[3 + POOL_SIZE] = DotrainBinding("max-time-spread", vm.toString(MAX_TIME_SPREAD));
        bindings[4 + POOL_SIZE] = DotrainBinding("min-price", vm.toString(MIN_PRICE));
        bindings[5 + POOL_SIZE] = DotrainBinding("max-price", vm.toString(MAX_PRICE));
    }

    /// Pool operator `i`'s address.
    function _operator(uint256 i) internal pure returns (address) {
        return vm.addr(OPERATOR_KEY_0 + i);
    }

    function _now() internal view returns (Float) {
        return _f(int256(block.timestamp), 0);
    }

    /// An attestation of `[TICKER, price, now]` by `key`.
    function _attestation(uint256 key, Float price) internal view returns (Attestation memory) {
        return Attestation({key: key, ticker: TICKER, price: price, time: _now()});
    }

    /// The lead and pool operators 0 and 1, all attesting `[TICKER, PRICE,
    /// now]`: the attestations the expression accepts for `TOKEN`.
    function _quorum() internal view returns (Attestation[] memory) {
        return _quorumFor(TICKER);
    }

    /// `_quorum` attesting `ticker` instead.
    function _quorumFor(string memory ticker) internal view returns (Attestation[] memory attestations) {
        attestations = new Attestation[](3);
        attestations[0] = _attestation(LEAD_KEY, _f(PRICE, 0));
        attestations[1] = _attestation(OPERATOR_KEY_0, _f(PRICE, 0));
        attestations[2] = _attestation(OPERATOR_KEY_0 + 1, _f(PRICE, 0));
        for (uint256 i = 0; i < attestations.length; i++) {
            attestations[i].ticker = ticker;
        }
    }

    /// `_quorum` at one price for all three.
    function _quorumAt(Float price) internal view returns (Attestation[] memory attestations) {
        attestations = _quorum();
        for (uint256 i = 0; i < attestations.length; i++) {
            attestations[i].price = price;
        }
    }

    /// Sign `attestations` in order.
    function _sign(Attestation[] memory attestations) internal pure returns (SignedContextV1[] memory signed) {
        signed = new SignedContextV1[](attestations.length);
        for (uint256 i = 0; i < attestations.length; i++) {
            signed[i] = attest(
                attestations[i].key,
                symbol(attestations[i].ticker),
                Float.unwrap(attestations[i].price),
                Float.unwrap(attestations[i].time)
            );
        }
    }

    /// A mint of `AMOUNT` with `attestations` is refused with `err`, and
    /// nothing is charged.
    function _refused(Attestation[] memory attestations, bytes memory err) internal {
        _refused(TOKEN, attestations, err);
    }

    function _refused(address token, Attestation[] memory attestations, bytes memory err) internal {
        _refused(token, _sign(attestations), err);
    }

    function _refused(address token, SignedContextV1[] memory signed, bytes memory err) internal {
        Float before = _headroom();
        bytes memory reason = _mintReverts(token, AMOUNT, keccak256(abi.encode(err, signed)), signed);
        assertEq(reason, err, "reason");
        _assertFloatEq(_headroom(), before, "nothing was charged");
    }

    /// A refusal by one of the expression's `ensure`s: an `Error(string)`.
    function _ensure(string memory reason) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("Error(string)", reason);
    }

    /// A mint of `AMOUNT` with `attestations` goes through and is charged
    /// `charge`.
    function _accepted(Attestation[] memory attestations, Float charge) internal {
        _accepted(TOKEN, attestations, charge);
    }

    function _accepted(address token, Attestation[] memory attestations, Float charge) internal {
        Float before = _headroom();
        _mint(token, AMOUNT, keccak256(abi.encode("accepted", mints++)), _sign(attestations));
        _assertFloatEq(_headroom(), before.sub(charge), "charged");
    }

    // ------------------------------------------------------------------ //
    //                            The happy path                          //
    // ------------------------------------------------------------------ //

    /// The lead and two pool operators attesting the ticker at one price
    /// mint, and the charge is `amount * price`: two whole tokens at 150 is
    /// 300.
    function testQuorumMintsAndIsChargedAmountTimesPrice() external {
        _accepted(_quorum(), _f(VALUE, 0));
    }

    /// The charge is the LEAD's price when the three differ within
    /// tolerance: the pool's prices are 1 above and 0.5 below, the spread of
    /// 1.5 is within 1% of 151, and the charge is `2 * 150`.
    function testChargeIsTheLeadsPrice() external {
        Attestation[] memory attestations = _quorum();
        attestations[1].price = _f(151, 0);
        attestations[2].price = _f(1495, -1);
        _accepted(attestations, _f(VALUE, 0));
    }

    /// Any two of the pool will do, in either order, and a third pool
    /// attestation is ignored rather than refused.
    function testAnyTwoOfThePoolMint() external {
        Attestation[] memory attestations = _quorum();
        attestations[1].key = OPERATOR_KEY_0 + 5;
        attestations[2].key = OPERATOR_KEY_0 + 3;
        _accepted(attestations, _f(VALUE, 0));

        Attestation[] memory four = new Attestation[](4);
        four[0] = _attestation(LEAD_KEY, _f(PRICE, 0));
        four[1] = _attestation(OPERATOR_KEY_0 + 4, _f(PRICE, 0));
        four[2] = _attestation(OPERATOR_KEY_0 + 2, _f(PRICE, 0));
        four[3] = _attestation(UNLISTED_KEY, _f(PRICE, 0));
        _accepted(four, _f(VALUE, 0));
    }

    /// The bounds are inclusive, and the charge follows the price.
    function testPriceAtTheBoundsMints() external {
        _accepted(_quorumAt(_f(MIN_PRICE, 0)), _f(2 * MIN_PRICE, 0));
        // Two mints at the ceiling would not fit the capacity of 1000, so
        // the second is charged 2 * 1000 against what is left.
        _setLimits(UNBOUNDED_CAPACITY, UNBOUNDED_CAPACITY);
        _accepted(_quorumAt(_f(MAX_PRICE, 0)), _f(2 * MAX_PRICE, 0));
    }

    /// Times up to `max-time-spread` from the chain clock, either side, are
    /// accepted.
    function testTimesWithinTheSpreadMint() external {
        Attestation[] memory attestations = _quorum();
        attestations[0].time = _f(NOW - MAX_TIME_SPREAD, 0);
        attestations[1].time = _f(NOW, 0);
        attestations[2].time = _f(NOW, 0);
        _accepted(attestations, _f(VALUE, 0));

        attestations = _quorum();
        attestations[2].time = _f(NOW + MAX_TIME_SPREAD, 0);
        _accepted(attestations, _f(VALUE, 0));
    }

    // ------------------------------------------------------------------ //
    //                        SPEC.md item 24: the lead                   //
    // ------------------------------------------------------------------ //

    /// Three pool operators and no lead: the first attestation is not the
    /// lead's.
    function testNoLeadIsRefused() external {
        Attestation[] memory attestations = _quorum();
        attestations[0].key = OPERATOR_KEY_0 + 2;
        _refused(attestations, _ensure("Lead attestation missing"));
    }

    /// The lead signs first. The lead's attestation anywhere else is not the
    /// lead's attestation.
    function testLeadNotFirstIsRefused() external {
        Attestation[] memory attestations = _quorum();
        attestations[0].key = OPERATOR_KEY_0;
        attestations[1].key = LEAD_KEY;
        _refused(attestations, _ensure("Lead attestation missing"));
    }

    /// No attestations at all: there is no lead to read, and the expression
    /// reverts reading past the grid before its first check.
    function testNoAttestationsIsRefused() external {
        _refused(TOKEN, new SignedContextV1[](0), stdError.indexOOBError);
    }

    // ------------------------------------------------------------------ //
    //                       SPEC.md item 23: the pool                    //
    // ------------------------------------------------------------------ //

    /// Fewer than two pool attestations: the second seat is read past the
    /// grid, which is a revert rather than a zero.
    function testFewerThanThresholdIsRefused() external {
        Attestation[] memory two = new Attestation[](2);
        two[0] = _attestation(LEAD_KEY, _f(PRICE, 0));
        two[1] = _attestation(OPERATOR_KEY_0, _f(PRICE, 0));
        _refused(two, stdError.indexOOBError);

        Attestation[] memory one = new Attestation[](1);
        one[0] = _attestation(LEAD_KEY, _f(PRICE, 0));
        _refused(one, stdError.indexOOBError);
    }

    /// An operator outside the allowlist in either seat.
    function testUnlistedOperatorIsRefused() external {
        Attestation[] memory attestations = _quorum();
        attestations[2].key = UNLISTED_KEY;
        _refused(attestations, _ensure("Attestor not allowlisted"));

        attestations = _quorum();
        attestations[1].key = UNLISTED_KEY;
        _refused(attestations, _ensure("Attestor not allowlisted"));
    }

    /// The lead is not a pool operator: a second lead attestation does not
    /// fill a pool seat.
    function testLeadInAPoolSeatIsRefused() external {
        Attestation[] memory attestations = _quorum();
        attestations[2].key = LEAD_KEY;
        _refused(attestations, _ensure("Attestor not allowlisted"));
    }

    /// One operator in both seats.
    function testSameOperatorTwiceIsRefused() external {
        Attestation[] memory attestations = _quorum();
        attestations[2].key = OPERATOR_KEY_0;
        _refused(attestations, _ensure("Same operator twice"));
    }

    // ------------------------------------------------------------------ //
    //                      SPEC.md item 15: the symbol                   //
    // ------------------------------------------------------------------ //

    /// The one composition installed in `setUp` serves every vault: `tAAPL`
    /// mints with `AAPL` attestations, and `tMSTR` with `MSTR`, each charged
    /// `amount * price`, with nothing recomposed or reinstalled between them.
    function testEveryVaultMintsThroughTheSameExpression() external {
        _accepted(OTHER_TOKEN, _quorumFor(OTHER_TICKER), _f(VALUE, 0));
        _accepted(TOKEN, _quorum(), _f(VALUE, 0));
        _accepted(OTHER_TOKEN, _quorumFor(OTHER_TICKER), _f(VALUE, 0));
    }

    /// The ticker is derived by arithmetic on the symbol's length, so a
    /// ticker of every length in production is minted, two, three and five
    /// characters around the four of `MSTR` and `AAPL`, and one of thirty,
    /// whose symbol is the 31 bytes an IntOrAString holds: every bit of the
    /// length is read, not only the low four.
    function testATickerOfAnyLengthMints() external {
        _setLimits(UNBOUNDED_CAPACITY, UNBOUNDED_CAPACITY);
        string[4] memory tickers = ["MU", "TSM", "GOOGL", "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123"];
        for (uint256 i = 0; i < tickers.length; i++) {
            _mockToken(ANY_TOKEN, string.concat("t", tickers[i]));
            _accepted(ANY_TOKEN, _quorumFor(tickers[i]), _f(VALUE, 0));
        }
    }

    /// A full quorum for one vault's ticker does not mint another vault:
    /// `AAPL` attestations are refused for `tMSTR`, and `MSTR` attestations
    /// for `tAAPL`.
    function testAnotherVaultsAttestationsAreRefused() external {
        _refused(TOKEN, _quorumFor(OTHER_TICKER), _ensure("Attestation for another token"));
        _refused(OTHER_TOKEN, _quorum(), _ensure("Attestation for another token"));
    }

    /// The prefix dropped is `t` and only `t`. A vault whose symbol does not
    /// start with it is refused whatever is attested, the ticker itself
    /// included; so is a vault with no symbol, which has nothing to drop.
    function testAVaultWithoutThePrefixIsRefused() external {
        string[4] memory symbols = ["MSTR", "xMSTR", "TMSTR", ""];
        string[4] memory tickers = ["STR", "MSTR", "MSTR", ""];
        for (uint256 i = 0; i < symbols.length; i++) {
            _mockToken(ANY_TOKEN, symbols[i]);
            _refused(ANY_TOKEN, _quorumFor(tickers[i]), _ensure("Vault symbol has no t prefix"));
        }
    }

    /// Attestations for the vault's own symbol are not attestations for the
    /// ticker: the `t` is dropped, not optional.
    function testAttestingTheVaultSymbolIsRefused() external {
        Attestation[] memory attestations = _quorum();
        for (uint256 i = 0; i < attestations.length; i++) {
            attestations[i].ticker = VAULT_SYMBOL;
        }
        _refused(attestations, _ensure("Attestation for another token"));
    }

    /// One attestation for another ticker, in any seat.
    function testOneAttestationForAnotherTickerIsRefused() external {
        for (uint256 i = 0; i < 3; i++) {
            Attestation[] memory attestations = _quorum();
            attestations[i].ticker = OTHER_TICKER;
            _refused(attestations, _ensure("Attestation for another token"));
        }
    }

    // ------------------------------------------------------------------ //
    //                     SPEC.md item 13: agreement                     //
    // ------------------------------------------------------------------ //

    /// A pool price further from the others than 1% of the largest.
    function testDisagreeingPriceIsRefused() external {
        Attestation[] memory attestations = _quorum();
        // 152 against 150: a spread of 2, over 1% of 152.
        attestations[1].price = _f(152, 0);
        _refused(attestations, _ensure("Attestors disagree"));

        attestations = _quorum();
        // 148 against 150: a spread of 2, over 1% of 150.
        attestations[2].price = _f(148, 0);
        _refused(attestations, _ensure("Attestors disagree"));
    }

    /// The lead's price against the pool's.
    function testDisagreeingLeadIsRefused() external {
        Attestation[] memory attestations = _quorum();
        attestations[0].price = _f(160, 0);
        _refused(attestations, _ensure("Attestors disagree"));
    }

    /// A time further than `max-time-spread` from the chain clock, in either
    /// direction, in any seat.
    function testStaleAttestationIsRefused() external {
        for (uint256 i = 0; i < 3; i++) {
            Attestation[] memory attestations = _quorum();
            attestations[i].time = _f(NOW - MAX_TIME_SPREAD - 1, 0);
            _refused(attestations, _ensure("Times disagree"));

            attestations = _quorum();
            attestations[i].time = _f(NOW + MAX_TIME_SPREAD + 1, 0);
            _refused(attestations, _ensure("Times disagree"));
        }
    }

    // ------------------------------------------------------------------ //
    //                       SPEC.md item 17: bounds                      //
    // ------------------------------------------------------------------ //

    /// All three agreeing on a price below the floor or above the ceiling.
    function testPriceOutsideTheBoundsIsRefused() external {
        _refused(_quorumAt(_f(MIN_PRICE - 1, 0)), _ensure("Price outside bounds"));
        _refused(_quorumAt(_f(MAX_PRICE + 1, 0)), _ensure("Price outside bounds"));
        _refused(_quorumAt(_f(999999, -4)), _ensure("Price outside bounds"));
    }

    /// The bounds are on the lead's price, which is the one used: the pool
    /// within tolerance of a lead over the ceiling does not bring it back.
    function testLeadOverTheCeilingIsRefused() external {
        Attestation[] memory attestations = _quorum();
        attestations[0].price = _f(MAX_PRICE + 1, 0);
        attestations[1].price = _f(MAX_PRICE, 0);
        attestations[2].price = _f(MAX_PRICE, 0);
        _refused(attestations, _ensure("Price outside bounds"));
    }
}
