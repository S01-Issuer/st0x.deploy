// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.12/src/lib/LibRainDeploy.sol";
import {LibAuthoriserInvariants} from "../../../../src/lib/LibAuthoriserInvariants.sol";
import {LibBeaconInvariants, BeaconOwnerMismatch} from "../../../../src/lib/LibBeaconInvariants.sol";
import {LibBeaconInvariantsHarness} from "../../lib/LibBeaconInvariantsHarness.sol";
import {LibSafeInvariantsHarness} from "../../lib/LibSafeInvariantsHarness.sol";
import {LibTimelockInvariantsHarness} from "../../lib/LibTimelockInvariantsHarness.sol";
import {LibTokenInvariantsHarness} from "../../lib/LibTokenInvariantsHarness.sol";
import {LibProdDeployV4} from "../../../../src/generated/LibProdDeployV4.sol";
import {LibProdBeaconsBase} from "../../../../src/lib/LibProdBeaconsBase.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../../../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants, ReceiptVaultOwnerMismatch, TokenInstance} from "../../../../src/lib/LibTokenInvariants.sol";

/// @title GovernanceTimelockMigrationTest
/// @notice Live-fork pin of the governance-timelock state on every governed
/// chain. `20260729-migrate-governance-to-timelock` has executed on Base,
/// Ethereum, HyperEVM, Robinhood Chain and BNB Smart Chain, so each chain is
/// asserted exactly:
///
/// - the timelock is the pinned, correctly configured deployment;
/// - every production receipt vault is owned by the timelock;
/// - every in-use upgrade beacon is owned by the timelock — a beacon owner
///   can repoint every production proxy in one transaction, so a beacon left
///   on the Safe would make the delay bypassable;
/// - the authoriser's seven `_ADMIN` roles sit exclusively on the timelock
///   and the Safe keeps its operational roles.
contract GovernanceTimelockMigrationTest is Test {
    /// @notice Assert the governed state for the active chain.
    /// @param tokens The chain's production token table.
    /// @param safe The chain's token-owner Safe.
    /// @param timelock The chain's governance timelock pin.
    /// @param authoriser The chain's V4 authoriser clone.
    function assertChainGoverned(TokenInstance[] memory tokens, address safe, address timelock, address authoriser)
        internal
        view
    {
        LibTimelockInvariants.assertTimelockState(timelock, safe);
        LibTokenInvariants.assertUniformOwnership(tokens, timelock);
        LibBeaconInvariants.assertProdBeaconsOwnedBy(block.chainid, timelock);
        LibAuthoriserInvariants.assertExpectedGrants(authoriser, safe, timelock);
    }

    function testBaseGoverned() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        assertChainGoverned(
            LibTokenInvariants.productionTokensBase(),
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE,
            LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK,
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE
        );
    }

    function testEthereumGoverned() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        assertChainGoverned(
            LibTokenInvariants.productionTokensEthereum(),
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM,
            LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_ETHEREUM,
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM
        );
    }

    function testHyperevmGoverned() external {
        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        assertChainGoverned(
            LibTokenInvariants.productionTokensHyperEvm(),
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_HYPEREVM,
            LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_HYPEREVM,
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_HYPEREVM
        );
    }

    function testRobinhoodGoverned() external {
        vm.createSelectFork(LibStoxDeployNetworks.ROBINHOOD);
        assertChainGoverned(
            LibTokenInvariants.productionTokensRobinhood(),
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ROBINHOOD,
            LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_ROBINHOOD,
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ROBINHOOD
        );
    }

    function testBscGoverned() external {
        vm.createSelectFork(LibStoxDeployNetworks.BSC);
        assertChainGoverned(
            LibTokenInvariants.productionTokensBsc(),
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_BSC,
            LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_BSC,
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_BSC
        );
    }

    /// @notice Chain ids ST0x governs today or is expected to govern.
    ///
    /// NOT a list of supported chains: an entry is INERT until that chain
    /// gains a pinned token-owner Safe. Listing a chain early costs nothing
    /// and is the whole point — a new chain cannot be onboarded past this
    /// guard without someone either adding its timelock arm or consciously
    /// deleting it from this list.
    /// @return ids The candidate chain ids.
    function governedChainCandidates() internal pure returns (uint256[] memory ids) {
        ids = new uint256[](5);
        ids[0] = LibSafeInvariants.BASE_CHAIN_ID;
        ids[1] = LibSafeInvariants.ETHEREUM_CHAIN_ID;
        ids[2] = LibSafeInvariants.HYPEREVM_CHAIN_ID;
        ids[3] = LibSafeInvariants.ROBINHOOD_CHAIN_ID;
        ids[4] = LibSafeInvariants.BSC_CHAIN_ID;
    }

    /// @notice Every chain ST0x governs must be known to the governance
    /// timelock library. A chain is "governed" once it has a pinned
    /// token-owner Safe; from that point `timelockForChainId` must resolve it
    /// rather than reverting `UnsupportedChainForGovernanceTimelock`, or the
    /// chain's production tokens would sit outside every timelock assertion
    /// with nothing going red.
    /// @dev Triggers on the SAFE pin rather than on a populated token table,
    /// so it fires at chain bootstrap rather than at first token deploy.
    function testEveryGovernedChainHasTimelockCoverage() external {
        LibSafeInvariantsHarness safeHarness = new LibSafeInvariantsHarness();
        LibTimelockInvariantsHarness timelockHarness = new LibTimelockInvariantsHarness();

        uint256[] memory ids = governedChainCandidates();
        for (uint256 i = 0; i < ids.length; i++) {
            // Not governed yet — nothing to cover, so the entry is inert.
            try safeHarness.callSafeForChainId(ids[i]) returns (address) {}
            catch {
                continue;
            }

            bool covered = true;
            try timelockHarness.callTimelockForChainId(ids[i]) returns (address) {}
            catch {
                covered = false;
            }
            assertTrue(
                covered,
                string.concat(
                    "chain ",
                    vm.toString(ids[i]),
                    " has a pinned token-owner Safe but no governance timelock arm: add it to",
                    " LibTimelockInvariants.timelockForChainId and to this suite's per-chain tests,",
                    " or the chain runs ungoverned by the timelock"
                )
            );
        }
    }

    /// @notice A vault handed back to the Safe trips `ReceiptVaultOwnerMismatch`:
    /// the Safe is no longer an accepted owner on any surface.
    function testVaultBackOnTheSafeTrips() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        address safe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
        TokenInstance[] memory tokens = LibTokenInvariants.productionTokensBase();
        vm.mockCall(tokens[0].receiptVault, abi.encodeWithSignature("owner()"), abi.encode(safe));

        LibTokenInvariantsHarness harness = new LibTokenInvariantsHarness();
        vm.expectRevert(
            abi.encodeWithSelector(
                ReceiptVaultOwnerMismatch.selector,
                tokens[0].receiptVault,
                LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK,
                safe
            )
        );
        harness.callAssertUniformOwnership(LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK);
    }

    /// @notice A beacon handed back to the Safe trips `BeaconOwnerMismatch`.
    function testBeaconBackOnTheSafeTrips() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        address safe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
        address beacon = LibProdBeaconsBase.beacons()[0];
        vm.mockCall(beacon, abi.encodeWithSignature("owner()"), abi.encode(safe));

        LibBeaconInvariantsHarness harness = new LibBeaconInvariantsHarness();
        vm.expectRevert(
            abi.encodeWithSelector(
                BeaconOwnerMismatch.selector, beacon, LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK, safe
            )
        );
        harness.callAssertProdBeaconsOwnedByChainTimelock(LibSafeInvariants.BASE_CHAIN_ID);
    }
}
