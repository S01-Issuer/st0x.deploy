// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Float, LibDecimalFloat} from "rain-math-float-0.3.11/src/lib/LibDecimalFloat.sol";
import {SignedContextV2} from "rainlang-0.2.30/src/interface/IInterpreterCallerV5.sol";

import {ST0xOrchestratorBaseForkFixture} from "test/src/concrete/ST0xOrchestratorBaseForkFixture.sol";

/// @title ST0xOrchestratorSignedPriceObservationBaseForkTest
/// @notice Either signed AAPL observation from the price API, alone as the
/// lead, mints `tAAPL` through the candidate orchestrator on a base fork,
/// verified by the orchestrator and priced by the Rainlang deployed on base,
/// and is charged `amount * 344.63` by `PRICED`.
contract ST0xOrchestratorSignedPriceObservationBaseForkTest is ST0xOrchestratorBaseForkFixture {
    using LibDecimalFloat for Float;

    function setUp() public override {
        super.setUp();
        _install(_baseEvaluable(string.concat(_baseUsingWords(), PRICED)));
        _setLimits(CAPACITY, CAPACITY);
    }

    /// Two whole tokens at 344.63.
    function _charge() internal pure returns (Float) {
        return _f(2 * 34463, -2);
    }

    function _assertChargedAsLead(SignedContextV2 memory observation, bytes32 nonce) internal {
        assertEq(AMOUNT, 2e18, "premise: two whole tokens");
        Float before = _headroom();
        _mint(TOKEN, AMOUNT, nonce, _asLead(observation));
        _assertFloatEq(_headroom(), before.sub(_charge()), "charged amount * 344.63");
    }

    function testAlpacaObservationAsTheLeadIsChargedAmountTimesItsPrice() external {
        _assertChargedAsLead(_alpaca(), keccak256("alpaca"));
    }

    function testYahooObservationAsTheLeadIsChargedAmountTimesItsPrice() external {
        _assertChargedAsLead(_yahoo(), keccak256("yahoo"));
    }
}
