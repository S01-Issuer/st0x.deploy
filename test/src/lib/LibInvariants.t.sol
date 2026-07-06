// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {IGnosisSafe} from "../../../src/interface/IGnosisSafe.sol";
import {LibInvariants} from "../../../src/lib/LibInvariants.sol";
import {LibChainPrincipals} from "../../../src/lib/LibChainPrincipals.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibTokenInvariants} from "../../../src/lib/LibTokenInvariants.sol";
import {LibAuthoriserInvariants} from "../../../src/lib/LibAuthoriserInvariants.sol";

/// @title LibInvariantsTest
/// @notice Exercises the chain-parametric production-state orchestrator.
/// The Base no-arg `assertAll(safe)` and the explicit
/// `assertProductionState(...)` entry point must produce the same result
/// against live Base, proving the multichain generalisation is a strict
/// superset of the Base pre-flight (the Ethereum call site is the same
/// function with Ethereum's table + clone + principals — asserted live in
/// the cross-chain parity suite once Ethereum is bootstrapped).
contract LibInvariantsTest is Test {
    /// The explicit orchestrator wired with Base's arguments passes against
    /// live Base, identically to the Base no-arg overload it backs.
    function testAssertProductionStateBasePassesLive() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        IGnosisSafe safe = IGnosisSafe(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);

        // Both forms must return silently — the no-arg overload delegates to
        // the parametric one, so this pins that delegation against real state.
        LibInvariants.assertAll(safe);
        LibInvariants.assertProductionState(
            safe,
            LibTokenInvariants.productionTokensBase(),
            LibAuthoriserInvariants.STOX_PROD_AUTHORISER,
            LibChainPrincipals.base()
        );
    }
}
