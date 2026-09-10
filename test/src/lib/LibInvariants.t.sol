// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {IGnosisSafe} from "../../../src/interface/IGnosisSafe.sol";
import {LibInvariants} from "../../../src/lib/LibInvariants.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibTokenInvariants} from "../../../src/lib/LibTokenInvariants.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";

/// @title LibInvariantsTest
/// @notice Exercises the multichain production-state orchestrator on every
/// chain it claims to serve. `assertProductionState` documents itself as the
/// chain-agnostic generalisation of Base's `assertAll(safe)`, but a function
/// only ever called with one chain's arguments is not proven generic — its
/// per-chain resolution (`assertActiveChainTokenOwnerSafe(block.chainid)`)
/// could revert, or resolve the wrong Safe, on every chain but the one
/// tested, and nothing would say so.
///
/// So: Base runs both forms and they must agree, and Ethereum and HyperEVM
/// run the multichain form with their own tables and clones. Robinhood Chain
/// and BNB Smart Chain are deliberately absent — their token tables are still
/// placeholders, so there is nothing live for the bundle to assert; the
/// forcing function that holds those chains to a date is
/// `StoxCrossChainParityTest`'s per-chain deadline, not this suite.
/// @dev Unpinned head forks: this is a live-state pre-flight, so a pinned
/// block would freeze what it reports.
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

    /// The same orchestrator against live Ethereum, wired with Ethereum's
    /// token table and authoriser clone. Ethereum's Safe is a distinct
    /// per-chain address resolved from `block.chainid`, so this is the leg
    /// that proves the resolution is real rather than incidentally Base's.
    function testAssertProductionStateEthereumPassesLive() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        LibInvariants.assertProductionState(
            LibTokenInvariants.productionTokensEthereum(), LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM
        );
    }

    /// The same orchestrator against live HyperEVM. HyperEVM shares
    /// Ethereum's Safe address but has its own token table and clone, so it
    /// varies exactly the deploy artifacts the bundle is parameterised on.
    function testAssertProductionStateHyperEvmPassesLive() external {
        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        LibInvariants.assertProductionState(
            LibTokenInvariants.productionTokensHyperEvm(), LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_HYPEREVM
        );
    }
}
