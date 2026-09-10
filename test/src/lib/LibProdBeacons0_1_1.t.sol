// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {ERC1967_BEACON_SLOT} from "rain-extrospection-0.1.1/src/lib/LibExtrospectERC1967BeaconProxy.sol";
import {LibBeaconInvariants} from "../../../src/lib/LibBeaconInvariants.sol";
import {LibProdBeacons0_1_1} from "../../../src/lib/LibProdBeacons0_1_1.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibTokenInvariants, TokenInstance} from "../../../src/lib/LibTokenInvariants.sol";

/// @title LibProdBeacons0_1_1Test
/// @notice The 0.1.1-bootstrap counterpart of `LibProdBeaconsBaseTest`.
/// `LibProdBeacons0_1_1` claims to name the beacons every bootstrap chain's
/// production tokens RUN ON, and every ownership invariant built on it
/// inherits that claim — but only Base's version of that claim was ever
/// checked against a chain. Name the wrong addresses here and the per-chain
/// ownership asserts still pass, against beacons no proxy points at, while
/// the live beacons go unpinned on four chains at once (the lib is
/// deterministic, so one wrong entry is wrong everywhere).
/// @dev Unpinned head forks. A pinned block would freeze the answer to
/// whatever was true at that block, which is the opposite of what a drift
/// detector is for.
// The version-suffixed name mirrors the lib under test.
// slither-disable-next-line naming-convention
contract LibProdBeacons0_1_1Test is Test {
    /// @notice Unix timestamp past which Robinhood Chain's token table must
    /// be hydrated — `2026-12-01T00:00:00Z`, the same date and the same
    /// forcing function as `StoxCrossChainParityTest.ROBINHOOD_PARITY_DEADLINE`
    /// applies to the same table. Before it, an all-placeholder table is the
    /// expected mid-bootstrap state (the 41-token deploy is in flight); after
    /// it, a table that never hydrated is a chain this pin asserts nothing
    /// about, so it fails loudly instead.
    uint256 internal constant ROBINHOOD_TOKEN_TABLE_DEADLINE = 1_796_083_200;

    /// @notice The same deadline for BNB Smart Chain's token table, matching
    /// `StoxCrossChainParityTest.BSC_PARITY_DEADLINE`.
    uint256 internal constant BSC_TOKEN_TABLE_DEADLINE = 1_796_083_200;

    /// @notice The beacon a `BeaconProxy` delegates to, read from its EIP-1967
    /// slot rather than a getter, so a proxy that does not expose one is still
    /// checkable.
    /// @param proxy The beacon proxy to read.
    /// @return The beacon it delegates to.
    function beaconOf(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967_BEACON_SLOT))));
    }

    /// @notice Whether a token table is fully hydrated, and whether any of it
    /// is. A partially hydrated table is a pin PR that landed a triple at a
    /// time and is caught by the caller — the deploy lands every token in one
    /// broadcast, so partial is drift, not a phase.
    /// @param tokens The table to inspect.
    /// @return anySet Any address in the table is non-zero.
    /// @return allSet Every address in the table is non-zero.
    function tokenTableState(TokenInstance[] memory tokens) internal pure returns (bool anySet, bool allSet) {
        allSet = true;
        for (uint256 i = 0; i < tokens.length; i++) {
            bool entrySet = tokens[i].receipt != address(0) && tokens[i].receiptVault != address(0)
                && tokens[i].wrappedTokenVault != address(0);
            bool entryClear = tokens[i].receipt == address(0) && tokens[i].receiptVault == address(0)
                && tokens[i].wrappedTokenVault == address(0);
            anySet = anySet || !entryClear;
            allSet = allSet && entrySet;
        }
    }

    /// @notice Every production token's receipt, receipt vault and wrapped
    /// vault on the ACTIVE fork sits behind the beacon this lib names for that
    /// slot, in the lib's own index order. A token migrated onto a different
    /// beacon, or an index swap in the lib, fails here — the two cases the
    /// ownership asserts cannot distinguish on their own, because a
    /// wrong-but-Safe-owned beacon satisfies them just as well as the right
    /// one.
    /// @param label Human chain name, used in the assertion messages.
    /// @param tokens The chain's production token table.
    function assertTokensRunOnPinnedBeacons(string memory label, TokenInstance[] memory tokens) internal view {
        address[4] memory beacons = LibProdBeacons0_1_1.beacons();
        assertTrue(tokens.length > 0, string.concat(label, ": no production tokens to check"));
        for (uint256 i = 0; i < tokens.length; i++) {
            assertEq(
                beaconOf(tokens[i].receipt),
                beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX],
                string.concat(label, " ", tokens[i].underlying, " receipt beacon")
            );
            assertEq(
                beaconOf(tokens[i].receiptVault),
                beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX],
                string.concat(label, " ", tokens[i].underlying, " receipt vault beacon")
            );
            assertEq(
                beaconOf(tokens[i].wrappedTokenVault),
                beacons[LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX],
                string.concat(label, " ", tokens[i].underlying, " wrapped vault beacon")
            );
        }
    }

    /// @notice As `assertTokensRunOnPinnedBeacons`, for a chain whose token
    /// table may still be an all-placeholder mid-bootstrap state: skipped
    /// with a loud PENDING log before `deadline`, failed after it. Gated on
    /// exactly the terms `StoxCrossChainParityTest` gates its token leg on,
    /// because it is gated on the same table.
    /// @param label Human chain name, used in the log and assertion messages.
    /// @param tokens The chain's production token table.
    /// @param deadline Unix timestamp past which a placeholder table fails.
    function assertTokensRunOnPinnedBeaconsOrPending(
        string memory label,
        TokenInstance[] memory tokens,
        uint256 deadline
    ) internal {
        (bool anySet, bool allSet) = tokenTableState(tokens);
        assertTrue(
            !anySet || allSet, string.concat(label, " token table partially hydrated - pin all triples together")
        );
        if (!allSet) {
            assertLt(
                block.timestamp,
                deadline,
                string.concat(
                    label, " token table still a placeholder past the deadline - the beacon pin asserts nothing"
                )
            );
            emit log(string.concat("PENDING: ", label, " token table placeholder - beacon-slot pin skipped"));
            return;
        }
        assertTokensRunOnPinnedBeacons(label, tokens);
    }

    /// @notice Ethereum's production tokens run on the pinned beacons.
    function testEthereumTokensRunOnTheseBeacons() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        assertTokensRunOnPinnedBeacons("Ethereum", LibTokenInvariants.productionTokensEthereum());
    }

    /// @notice HyperEVM's production tokens run on the pinned beacons.
    function testHyperEvmTokensRunOnTheseBeacons() external {
        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        assertTokensRunOnPinnedBeacons("HyperEVM", LibTokenInvariants.productionTokensHyperEvm());
    }

    /// @notice Robinhood Chain's production tokens run on the pinned beacons
    /// once its table hydrates; PENDING until the 41-token deploy lands.
    function testRobinhoodTokensRunOnTheseBeacons() external {
        vm.createSelectFork(LibStoxDeployNetworks.ROBINHOOD);
        assertTokensRunOnPinnedBeaconsOrPending(
            "Robinhood Chain", LibTokenInvariants.productionTokensRobinhood(), ROBINHOOD_TOKEN_TABLE_DEADLINE
        );
    }

    /// @notice BNB Smart Chain's production tokens run on the pinned beacons
    /// once its table hydrates; PENDING until the 41-token deploy lands.
    function testBscTokensRunOnTheseBeacons() external {
        vm.createSelectFork(LibStoxDeployNetworks.BSC);
        assertTokensRunOnPinnedBeaconsOrPending(
            "BNB Smart Chain", LibTokenInvariants.productionTokensBsc(), BSC_TOKEN_TABLE_DEADLINE
        );
    }

    /// @notice The four beacons are distinct. Index-aligned lists invite a
    /// copy-paste that repeats one entry, and a repeated beacon would still
    /// pass every ownership check while quietly asserting nothing about the
    /// slot it displaced.
    /// @dev Needs a fork: two of the four addresses are live reads from the
    /// 0.1.1 beacon-set deployer. Ethereum is arbitrary — the set is
    /// deterministic and identical on every bootstrap chain.
    function testTheFourBeaconsAreDistinct() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        address[4] memory beacons = LibProdBeacons0_1_1.beacons();
        for (uint256 i = 0; i < beacons.length; i++) {
            assertTrue(beacons[i] != address(0), "beacon entry is zero");
            for (uint256 j = i + 1; j < beacons.length; j++) {
                assertTrue(beacons[i] != beacons[j], "two beacon slots resolve to the same address");
            }
        }
    }
}
