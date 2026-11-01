// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Strings} from "@openzeppelin-contracts-5.7.0/utils/Strings.sol";
import {stdError} from "forge-std-1.17.0/src/StdError.sol";
import {Float, LibDecimalFloat} from "rain-math-float-0.3.11/src/lib/LibDecimalFloat.sol";
import {SignedContextV2} from "rainlang-0.2.30/src/interface/IInterpreterCallerV5.sol";

import {LibTestDotrain, DotrainBinding} from "test/lib/LibTestDotrain.sol";
import {ST0xOrchestratorMintWeightingFixture} from "test/src/concrete/ST0xOrchestratorMintWeightingFixture.sol";
import {
    OBSERVATION_ROWS,
    ALPACA_SOURCE,
    OBSERVATION_CURRENCY
} from "test/src/concrete/St0xAttestSubParser.signedPriceObservation.t.sol";

/// @title LeadOnlyMintWeightingTest
/// @notice `src/rain/lead-only-mint-weighting.rain` composed from the file,
/// installed on a real orchestrator and run by `mint`: the lead's attestation
/// alone mints, charged `mint-amount * lead-price`; each check refuses with
/// nothing charged; attestations after the lead's are not read. Attestations
/// carry the price API's five rows `[symbol, price, time, source, currency]`.
contract LeadOnlyMintWeightingTest is ST0xOrchestratorMintWeightingFixture {
    using Strings for address;
    using LibDecimalFloat for Float;

    struct Attestation {
        uint256 key;
        bytes32 domain;
        string ticker;
        Float price;
        Float time;
        bytes32 currency;
    }

    string internal constant SOURCE = "src/rain/lead-only-mint-weighting.rain";
    string internal constant ENTRYPOINT = "weighting";

    string internal constant VAULT_SYMBOL = "tMSTR";
    string internal constant TICKER = "MSTR";

    address internal constant OTHER_TOKEN = address(0xA22E);
    string internal constant OTHER_VAULT_SYMBOL = "tAAPL";
    string internal constant OTHER_TICKER = "AAPL";

    address internal constant ANY_TOKEN = address(0xA33E);

    int256 internal constant MAX_TIME_SPREAD = 600;
    int256 internal constant MIN_PRICE = 100;
    int256 internal constant MAX_PRICE = 1000;

    int256 internal constant NOW = 1_760_000_000;

    /// Fresh nonce per mint.
    uint256 internal mints;

    /// @inheritdoc ST0xOrchestratorMintWeightingFixture
    function tokenSymbol() internal pure override returns (string memory) {
        return VAULT_SYMBOL;
    }

    function setUp() public override {
        super.setUp();
        // forge-lint: disable-next-line(unsafe-typecast)
        vm.warp(uint256(NOW));
        _install(_evaluable(LibTestDotrain.compose(vm.readFile(SOURCE), ENTRYPOINT, _bindings())));
        _setLimits(CAPACITY, CAPACITY);
        _mockToken(OTHER_TOKEN, OTHER_VAULT_SYMBOL);
    }

    function _bindings() internal view returns (DotrainBinding[] memory) {
        DotrainBinding[] memory bindings = new DotrainBinding[](6);
        bindings[0] = DotrainBinding("st0x-attest-subparser", address(I_SUB_PARSER).toHexString());
        bindings[1] = DotrainBinding("lead-signer", vm.addr(LEAD_KEY).toHexString());
        bindings[2] = DotrainBinding("lead-domain-separator", vm.toString(LEAD_DOMAIN));
        bindings[3] = DotrainBinding("max-time-spread", vm.toString(MAX_TIME_SPREAD));
        bindings[4] = DotrainBinding("min-price", vm.toString(MIN_PRICE));
        bindings[5] = DotrainBinding("max-price", vm.toString(MAX_PRICE));
        return bindings;
    }

    /// The lead attesting `[TICKER, PRICE, now, "alpaca", "USD"]` under
    /// `LEAD_DOMAIN`.
    function _leadAttestation() internal view returns (Attestation memory) {
        return Attestation({
            key: LEAD_KEY,
            domain: LEAD_DOMAIN,
            ticker: TICKER,
            price: _f(PRICE, 0),
            time: _f(int256(block.timestamp), 0),
            currency: OBSERVATION_CURRENCY
        });
    }

    function _lead() internal view returns (Attestation[] memory) {
        Attestation[] memory attestations = new Attestation[](1);
        attestations[0] = _leadAttestation();
        return attestations;
    }

    function _leadFor(string memory ticker) internal view returns (Attestation[] memory) {
        Attestation[] memory attestations = _lead();
        attestations[0].ticker = ticker;
        return attestations;
    }

    function _leadAt(Float price) internal view returns (Attestation[] memory) {
        Attestation[] memory attestations = _lead();
        attestations[0].price = price;
        return attestations;
    }

    function _sign(Attestation[] memory attestations) internal pure returns (SignedContextV2[] memory) {
        SignedContextV2[] memory signed = new SignedContextV2[](attestations.length);
        for (uint256 i = 0; i < attestations.length; i++) {
            bytes32[] memory context = new bytes32[](OBSERVATION_ROWS);
            context[0] = symbol(attestations[i].ticker);
            context[1] = Float.unwrap(attestations[i].price);
            context[2] = Float.unwrap(attestations[i].time);
            context[3] = ALPACA_SOURCE;
            context[4] = attestations[i].currency;
            signed[i] = signUnder(attestations[i].key, attestations[i].domain, context);
        }
        return signed;
    }

    function _refused(Attestation[] memory attestations, bytes memory err) internal {
        _refused(TOKEN, attestations, err);
    }

    function _refused(address token, Attestation[] memory attestations, bytes memory err) internal {
        _refused(token, _sign(attestations), err);
    }

    function _refused(address token, SignedContextV2[] memory signed, bytes memory err) internal {
        Float before = _headroom();
        bytes memory reason = _mintReverts(token, AMOUNT, keccak256(abi.encode(err, signed)), signed);
        assertEq(reason, err, "reason");
        _assertFloatEq(_headroom(), before, "nothing was charged");
    }

    function _ensure(string memory reason) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("Error(string)", reason);
    }

    function _accepted(Attestation[] memory attestations, Float charge) internal {
        _accepted(TOKEN, _sign(attestations), charge);
    }

    function _accepted(address token, Attestation[] memory attestations, Float charge) internal {
        _accepted(token, _sign(attestations), charge);
    }

    function _accepted(address token, SignedContextV2[] memory signed, Float charge) internal {
        Float before = _headroom();
        _mint(token, AMOUNT, keccak256(abi.encode("accepted", mints++)), signed);
        _assertFloatEq(_headroom(), before.sub(charge), "charged");
    }

    // ------------------------------------------------------------------ //
    //                            the happy path                          //
    // ------------------------------------------------------------------ //

    /// Two whole tokens at 150 is 300.
    function testLeadAloneMintsAndIsChargedAmountTimesPrice() external {
        _accepted(_lead(), _f(VALUE, 0));
    }

    /// Two whole tokens at 344.63 is 689.26.
    function testChargeIsAmountTimesTheLeadsPrice() external {
        _accepted(_leadAt(_f(34463, -2)), _f(68926, -2));
    }

    function testPriceAtTheBoundsMints() external {
        _accepted(_leadAt(_f(MIN_PRICE, 0)), _f(2 * MIN_PRICE, 0));
        _setLimits(UNBOUNDED_CAPACITY, UNBOUNDED_CAPACITY);
        _accepted(_leadAt(_f(MAX_PRICE, 0)), _f(2 * MAX_PRICE, 0));
    }

    function testTimesAtTheSpreadEitherSideMint() external {
        Attestation[] memory attestations = _lead();
        attestations[0].time = _f(NOW - MAX_TIME_SPREAD, 0);
        _accepted(attestations, _f(VALUE, 0));

        attestations = _lead();
        attestations[0].time = _f(NOW + MAX_TIME_SPREAD, 0);
        _accepted(attestations, _f(VALUE, 0));
    }

    // ------------------------------------------------------------------ //
    //                       attestations after the lead                  //
    // ------------------------------------------------------------------ //

    /// Each attestation behind the lead's would be refused as the lead, and
    /// is ignored there: alone, all together, and as contexts of one row and
    /// of none.
    function testAttestationsAfterTheLeadAreIgnored() external {
        _setLimits(UNBOUNDED_CAPACITY, UNBOUNDED_CAPACITY);
        Attestation[] memory others = new Attestation[](8);
        for (uint256 i = 0; i < others.length; i++) {
            others[i] = _leadAttestation();
        }
        others[0].key = OPERATOR_KEY_0;
        others[1].domain = POOL_DOMAIN;
        others[2].ticker = OTHER_TICKER;
        others[3].currency = symbol("EUR");
        others[4].time = _f(NOW - 10 * MAX_TIME_SPREAD, 0);
        others[5].price = _f(10 * MAX_PRICE, 0);
        others[6] = Attestation({
            key: OPERATOR_KEY_0 + 1,
            domain: keccak256("another domain"),
            ticker: VAULT_SYMBOL,
            price: _f(MIN_PRICE - 1, 0),
            time: _f(NOW + 10 * MAX_TIME_SPREAD, 0),
            currency: symbol("usd")
        });
        others[7].price = _f(2 * PRICE, 0);

        for (uint256 i = 0; i < others.length; i++) {
            Attestation[] memory attestations = new Attestation[](2);
            attestations[0] = _leadAttestation();
            attestations[1] = others[i];
            _accepted(attestations, _f(VALUE, 0));
        }

        Attestation[] memory all = new Attestation[](1 + others.length);
        all[0] = _leadAttestation();
        for (uint256 i = 0; i < others.length; i++) {
            all[1 + i] = others[i];
        }
        _accepted(all, _f(VALUE, 0));

        SignedContextV2[] memory shortContexts = new SignedContextV2[](3);
        shortContexts[0] = _sign(_lead())[0];
        shortContexts[1] = sign(OPERATOR_KEY_0, new bytes32[](1));
        shortContexts[2] = sign(OPERATOR_KEY_0 + 1, new bytes32[](0));
        _accepted(TOKEN, shortContexts, _f(VALUE, 0));
    }

    // ------------------------------------------------------------------ //
    //                              the lead                              //
    // ------------------------------------------------------------------ //

    function testAnotherSignerIsRefused() external {
        Attestation[] memory attestations = _lead();
        attestations[0].key = OPERATOR_KEY_0;
        _refused(attestations, _ensure("Lead attestation missing"));
    }

    function testLeadBehindAnotherSignerIsRefused() external {
        Attestation[] memory attestations = new Attestation[](2);
        attestations[0] = _leadAttestation();
        attestations[0].key = OPERATOR_KEY_0;
        attestations[1] = _leadAttestation();
        _refused(attestations, _ensure("Lead attestation missing"));
    }

    function testNoAttestationsIsRefused() external {
        _refused(TOKEN, new SignedContextV2[](0), stdError.indexOOBError);
    }

    // ------------------------------------------------------------------ //
    //                             the domain                             //
    // ------------------------------------------------------------------ //

    function testLeadUnderAnotherDomainIsRefused(bytes32 other) external {
        vm.assume(other != LEAD_DOMAIN);
        bytes32[2] memory domains = [POOL_DOMAIN, other];
        for (uint256 i = 0; i < domains.length; i++) {
            Attestation[] memory attestations = _lead();
            attestations[0].domain = domains[i];
            _refused(attestations, _ensure("Lead domain mismatch"));
        }
    }

    // ------------------------------------------------------------------ //
    //                             the symbol                             //
    // ------------------------------------------------------------------ //

    /// One composition serves every vault, nothing recomposed between them.
    function testEveryVaultMintsThroughTheSameExpression() external {
        _accepted(OTHER_TOKEN, _leadFor(OTHER_TICKER), _f(VALUE, 0));
        _accepted(TOKEN, _lead(), _f(VALUE, 0));
        _accepted(OTHER_TOKEN, _leadFor(OTHER_TICKER), _f(VALUE, 0));
    }

    /// Thirty characters is the longest ticker a 31-byte symbol holds.
    function testATickerOfAnyLengthMints() external {
        _setLimits(UNBOUNDED_CAPACITY, UNBOUNDED_CAPACITY);
        string[4] memory tickers = ["MU", "TSM", "GOOGL", "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123"];
        for (uint256 i = 0; i < tickers.length; i++) {
            _mockToken(ANY_TOKEN, string.concat("t", tickers[i]));
            _accepted(ANY_TOKEN, _leadFor(tickers[i]), _f(VALUE, 0));
        }
    }

    function testAnotherTokensSymbolIsRefused() external {
        _refused(TOKEN, _leadFor(OTHER_TICKER), _ensure("Attestation for another token"));
        _refused(OTHER_TOKEN, _lead(), _ensure("Attestation for another token"));
    }

    function testAttestingTheVaultSymbolIsRefused() external {
        _refused(_leadFor(VAULT_SYMBOL), _ensure("Attestation for another token"));
    }

    function testAVaultSymbolWithoutTIsRefused() external {
        string[4] memory symbols = ["MSTR", "xMSTR", "TMSTR", ""];
        string[4] memory tickers = ["STR", "MSTR", "MSTR", ""];
        for (uint256 i = 0; i < symbols.length; i++) {
            _mockToken(ANY_TOKEN, symbols[i]);
            _refused(ANY_TOKEN, _leadFor(tickers[i]), _ensure("Vault symbol has no t prefix"));
        }
    }

    // ------------------------------------------------------------------ //
    //                            the currency                            //
    // ------------------------------------------------------------------ //

    function testANonUsdCurrencyIsRefused() external {
        bytes32[7] memory currencies =
            [symbol("EUR"), symbol("usd"), symbol("USDT"), symbol("US"), symbol("USD "), symbol(""), bytes32(0)];
        for (uint256 i = 0; i < currencies.length; i++) {
            Attestation[] memory attestations = _lead();
            attestations[0].currency = currencies[i];
            _refused(attestations, _ensure("Price not in USD"));
        }
    }

    function testAnyCurrencyRowButUsdIsRefused(bytes32 currency) external {
        vm.assume(currency != OBSERVATION_CURRENCY);
        Attestation[] memory attestations = _lead();
        attestations[0].currency = currency;
        _refused(attestations, _ensure("Price not in USD"));
    }

    // ------------------------------------------------------------------ //
    //                              the time                              //
    // ------------------------------------------------------------------ //

    function testATimeOutsideTheSpreadEitherSideIsRefused() external {
        Attestation[] memory attestations = _lead();
        attestations[0].time = _f(NOW - MAX_TIME_SPREAD - 1, 0);
        _refused(attestations, _ensure("Times disagree"));

        attestations = _lead();
        attestations[0].time = _f(NOW + MAX_TIME_SPREAD + 1, 0);
        _refused(attestations, _ensure("Times disagree"));
    }

    // ------------------------------------------------------------------ //
    //                               bounds                               //
    // ------------------------------------------------------------------ //

    function testAPriceOutsideTheBoundsIsRefused() external {
        _refused(_leadAt(_f(MIN_PRICE - 1, 0)), _ensure("Price outside bounds"));
        _refused(_leadAt(_f(MIN_PRICE * 100 - 1, -2)), _ensure("Price outside bounds"));
        _refused(_leadAt(_f(MAX_PRICE + 1, 0)), _ensure("Price outside bounds"));
        _refused(_leadAt(_f(MAX_PRICE * 100 + 1, -2)), _ensure("Price outside bounds"));
    }
}
