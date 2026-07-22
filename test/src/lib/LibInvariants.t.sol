// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {IGnosisSafe} from "../../../src/interface/IGnosisSafe.sol";
import {LibInvariants} from "../../../src/lib/LibInvariants.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibTokenInvariants} from "../../../src/lib/LibTokenInvariants.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";

/// @title LibInvariantsTest
/// @notice Exercises the multichain production-state orchestrator. The Base
/// no-arg `assertAll(safe)` and the explicit `assertProductionState(...)`
/// entry point must produce the same result against live Base, proving the
/// multichain generalisation is a strict superset of the Base pre-flight (the
/// Ethereum call site is the same function with Ethereum's table + clone —
/// the token-owner Safe and grant map are shared across chains, so only those
/// deploy artifacts differ; asserted live in the cross-chain parity suite once
/// Ethereum is bootstrapped).
contract LibInvariantsTest is Test {
    /// The explicit orchestrator wired with Base's deploy artifacts passes
    /// against live Base, identically to the Base no-arg overload it backs.
    function testAssertProductionStateBasePassesLive() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        IGnosisSafe safe = IGnosisSafe(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);

        // Both forms must return silently. `assertProductionState` asserts the
        // shared token-owner Safe + shared grant map, so only the token table
        // and the live authoriser are passed. The live authoriser is the V4
        // clone since the swap batch executed on Base (2026-07).
        LibInvariants.assertAll(safe);
        LibInvariants.assertProductionState(
            LibTokenInvariants.productionTokensBase(), LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE
        );
    }
}
