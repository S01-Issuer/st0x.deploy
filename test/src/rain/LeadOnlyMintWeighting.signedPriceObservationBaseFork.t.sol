// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Strings} from "@openzeppelin-contracts-5.7.0/utils/Strings.sol";
import {Float, LibDecimalFloat} from "rain-math-float-0.3.11/src/lib/LibDecimalFloat.sol";
import {SignedContextV2} from "rainlang-0.2.31/src/interface/IInterpreterCallerV5.sol";

import {LibProdDeployV4} from "src/generated/LibProdDeployV4.sol";
import {LibTestDotrain, DotrainBinding} from "test/lib/LibTestDotrain.sol";
import {
    ST0xOrchestratorBaseForkFixture,
    BASE_FORK_TIMESTAMP
} from "test/src/concrete/ST0xOrchestratorBaseForkFixture.sol";
import {OBSERVATION_SIGNER, OBSERVATION_TIME} from "test/src/concrete/St0xAttestSubParser.signedPriceObservation.t.sol";

/// @title LeadOnlyMintWeightingSignedPriceObservationBaseForkTest
/// @notice `src/rain/lead-only-mint-weighting.rain`, bound to the price API's
/// signer, parsed and evaluated by the Rainlang deployed on base:
/// either signed AAPL observation alone as the lead mints `tAAPL` through the
/// candidate orchestrator and is charged `amount * 344.63`.
contract LeadOnlyMintWeightingSignedPriceObservationBaseForkTest is ST0xOrchestratorBaseForkFixture {
    using Strings for address;
    using LibDecimalFloat for Float;

    string internal constant SOURCE = "src/rain/lead-only-mint-weighting.rain";
    string internal constant ENTRYPOINT = "weighting";

    /// The chain clock at the mint less the observations' attested time.
    int256 internal constant MAX_TIME_SPREAD = int256(BASE_FORK_TIMESTAMP) - int256(uint256(OBSERVATION_TIME));
    int256 internal constant MIN_PRICE = 100;
    int256 internal constant MAX_PRICE = 1000;

    function setUp() public override {
        super.setUp();
        _install(_baseEvaluable(LibTestDotrain.compose(vm.readFile(SOURCE), ENTRYPOINT, _bindings())));
        _setLimits(CAPACITY, CAPACITY);
    }

    function _bindings() internal pure returns (DotrainBinding[] memory) {
        DotrainBinding[] memory bindings = new DotrainBinding[](5);
        bindings[0] =
            DotrainBinding("st0x-attest-subparser", LibProdDeployV4.ST0X_ATTEST_SUB_PARSER_CANDIDATE.toHexString());
        bindings[1] = DotrainBinding("lead-signer", OBSERVATION_SIGNER.toHexString());
        bindings[2] = DotrainBinding("max-time-spread", vm.toString(MAX_TIME_SPREAD));
        bindings[3] = DotrainBinding("min-price", vm.toString(MIN_PRICE));
        bindings[4] = DotrainBinding("max-price", vm.toString(MAX_PRICE));
        return bindings;
    }

    function _assertChargedAsLead(SignedContextV2 memory observation, bytes32 nonce) internal {
        assertEq(AMOUNT, 2e18, "premise: two whole tokens");
        Float before = _headroom();
        _mint(TOKEN, AMOUNT, nonce, _asLead(observation));
        _assertFloatEq(_headroom(), before.sub(_f(2 * 34463, -2)), "charged 2 * 344.63");
    }

    function testAlpacaObservationAsTheLeadMintsAndIsChargedAmountTimesItsPrice() external {
        _assertChargedAsLead(_alpaca(), keccak256("alpaca"));
    }

    function testYahooObservationAsTheLeadMintsAndIsChargedAmountTimesItsPrice() external {
        _assertChargedAsLead(_yahoo(), keccak256("yahoo"));
    }
}
