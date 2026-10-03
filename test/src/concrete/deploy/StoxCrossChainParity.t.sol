// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.6.1/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin-contracts-5.6.1/interfaces/IERC4626.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {ERC1967Utils} from "@openzeppelin-contracts-5.6.1/proxy/ERC1967/ERC1967Utils.sol";
import {LibRainDeploy} from "rain-deploy-0.1.10/src/lib/LibRainDeploy.sol";
import {IGnosisSafe} from "../../../../src/interface/IGnosisSafe.sol";
import {IOwnable} from "rain-extrospection-0.1.14/src/interface/IOwnable.sol";
import {LibAuthoriserInvariants} from "../../../../src/lib/LibAuthoriserInvariants.sol";
import {LibProdDeployV2BaseOverrides} from "../../../../src/lib/LibProdDeployV2BaseOverrides.sol";
import {LibMigrationInvariant} from "../../../../src/lib/LibMigrationInvariant.sol";
import {FLEET_UPGRADE_DEADLINE} from "../../../lib/LibTestProd.sol";
import {LibProdDeployV4} from "../../../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../../src/lib/LibStoxDeployNetworks.sol";
import {LibTokenInvariants, TokenInstance} from "../../../../src/lib/LibTokenInvariants.sol";
import {LibProdTokenConfig, TokenConfig} from "../../../../src/lib/LibProdTokenConfig.sol";

/// @notice Minimal surface for the receipt vault's ERC-1155 receipt getter,
/// used to assert the vault points at this token's pinned receipt.
interface IReceiptVaultReceipt {
    function receipt() external view returns (address);
}

/// @notice Minimal surface for the ERC-1155 receipt's manager getter. The
/// receipt has no owner or authoriser of its own — its only access control is
/// `manager` (the receipt vault, which alone can mint/burn), so the wiring
/// check is `receipt.manager() == receiptVault`.
interface IReceiptManager {
    function manager() external view returns (address);
}

/// @notice Everything the parity suite reads per token instance on one
/// chain, captured on each chain's own fork (Base included). The vault
/// `name`/`symbol` are asserted against the `LibProdTokenConfig` baseline;
/// the remaining fields (decimals + the wrapped legs) are compared
/// field-by-field across chains, with Base as the reference.
/// @param underlying The chain-agnostic join key from the token table.
/// @param vaultName The receipt vault's ERC-20 `name()`.
/// @param vaultSymbol The receipt vault's ERC-20 `symbol()`.
/// @param vaultDecimals The receipt vault's ERC-20 `decimals()`.
/// @param wrappedName The wrapped token vault's ERC-20 `name()`.
/// @param wrappedSymbol The wrapped token vault's ERC-20 `symbol()`.
/// @param wrappedDecimals The wrapped token vault's ERC-20 `decimals()`.
struct TokenConfigSnapshot {
    string underlying;
    string vaultName;
    string vaultSymbol;
    uint8 vaultDecimals;
    string wrappedName;
    string wrappedSymbol;
    uint8 wrappedDecimals;
}

/// @notice What one chain's live legs asserted, captured for the cross-chain
/// comparison. Each leg's fields are only meaningful when its `*Live` flag is
/// true; a pending (placeholder) leg is skipped, leaving its flag false.
/// @param safeLive The Safe pin is set and its policy was asserted.
/// @param owners The Safe's live owner set (valid iff `safeLive`).
/// @param threshold The Safe's live threshold (valid iff `safeLive`).
/// @param cloneLive The authoriser clone pin is set and its codehash asserted.
/// @param cloneCodehash The clone's runtime codehash (valid iff `cloneLive`).
/// @param tokenLegLive Safe + clone + full token table all live; token
/// ownership / sole-authoriser / config asserted.
/// @param tokenConfigs Per-token config snapshots (valid iff `tokenLegLive`).
/// @param beaconImpl The receipt-vault beacon implementation (valid iff
/// `tokenLegLive`).
/// @param beaconImplCodehash The beacon implementation's codehash (valid iff
/// `tokenLegLive`).
/// @param receiptBeaconImpl The ERC-1155 receipt beacon implementation (valid
/// iff `tokenLegLive`).
/// @param receiptBeaconImplCodehash The receipt beacon implementation's
/// codehash (valid iff `tokenLegLive`).
struct ChainLegs {
    bool safeLive;
    address[] owners;
    uint256 threshold;
    bool cloneLive;
    bytes32 cloneCodehash;
    bool tokenLegLive;
    TokenConfigSnapshot[] tokenConfigs;
    address beaconImpl;
    bytes32 beaconImplCodehash;
    address receiptBeaconImpl;
    bytes32 receiptBeaconImplCodehash;
}

/// @title StoxCrossChainParityTest
/// @notice The cross-chain deployment-parity pin: every ST0x chain carries
/// identical core artifacts, identically-configured token instances and an
/// identical permission structure. Layers, per non-baseline chain vs Base:
///
/// 1. **Core artifacts** — the deterministic Zoltu addresses + codehashes
///    are asserted per-network by `StoxProdV4Test`. This suite re-asserts
///    only the per-chain authoriser clones: pinned address, shared EIP-1167
///    codehash.
/// 2. **Token instances** — for every underlying in the per-chain token
///    tables: `name` / `symbol` of both vault legs equal the
///    `LibProdTokenConfig` baseline and `decimals` equals Base's;
///    `wrapped.asset() == receiptVault`; every receipt vault's
///    `authorizer()` is the chain's pinned V4 clone and its `owner()` is
///    the chain's token-owner Safe; all of a chain's proxies share one
///    runtime codehash per leg (the codehash embeds the beacon address, so
///    it is uniform within a chain and differs across chains).
/// 3. **Beacon lineage** — each chain's receipt + receipt-vault proxies
///    resolve (via the ERC-1967 beacon slot) to a single beacon per leg,
///    owned by that chain's token-owner Safe. The receipt + receipt-vault
///    beacon impls (address + codehash) are identical across chains.
/// 4. **Role parity** — `LibAuthoriserInvariants.assertExpectedGrants` runs
///    against each chain's clone with that chain's token-owner Safe. The
///    Safe policy (owner set, threshold, v1.4.1 identity) is asserted equal
///    to Base's.
///
/// `assertCleanV4Lineage` asserts that no non-baseline chain's beacon
/// carries any `LibProdDeployV2BaseOverrides` implementation or owner.
///
/// **Per-leg placeholder gating.** A chain's token-owner Safe address,
/// authoriser clone address and token addresses are `address(0)` until
/// pinned. Each leg is asserted only when its pins are set; a placeholder
/// leg is skipped with a `PARITY PENDING` log, and the cross-chain
/// comparisons gate on both chains carrying the leg. The legs nest by
/// dependency: the **Safe leg** needs the Safe; the **authoriser leg**
/// needs the clone (its grant map also needs the Safe); the **token leg**
/// needs the Safe + clone + full token table. A partially-hydrated token
/// table (some triples set, some placeholder) fails.
contract StoxCrossChainParityTest is Test {
    /// @notice Read the address stored in `proxy`'s ERC-1967 beacon slot.
    /// @param proxy The beacon-proxy address on the active fork.
    /// @return beacon The beacon address backing the proxy.
    function readBeacon(address proxy) internal view returns (address beacon) {
        beacon = address(uint160(uint256(vm.load(proxy, ERC1967Utils.BEACON_SLOT))));
    }

    /// @notice Capture one chain's per-token config snapshot on the active
    /// fork and assert receipt/wrapped wiring, per-leg proxy codehash
    /// uniformity within the chain, and the single shared beacon per leg.
    /// @dev The uniform owner + sole-authoriser checks are in
    /// `assertChainLegs` via `LibTokenInvariants.assertAll`.
    /// @param tokens The chain's token table.
    /// @return snapshots Per-token config snapshots, table order.
    /// @return receiptVaultBeacon The single beacon backing every receipt
    /// vault proxy on this chain.
    /// @return receiptBeacon The single beacon backing every ERC-1155 receipt
    /// proxy on this chain.
    function assertChainAndSnapshot(TokenInstance[] memory tokens)
        internal
        view
        returns (TokenConfigSnapshot[] memory snapshots, address receiptVaultBeacon, address receiptBeacon)
    {
        snapshots = new TokenConfigSnapshot[](tokens.length);

        // The name/symbol baseline every chain is asserted against (Base
        // included).
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();

        // Per-leg proxy-codehash uniformity within the chain.
        bytes32 receiptVaultProxyCodehash = tokens[0].receiptVault.codehash;
        bytes32 wrappedProxyCodehash = tokens[0].wrappedTokenVault.codehash;
        bytes32 receiptProxyCodehash = tokens[0].receipt.codehash;
        receiptVaultBeacon = readBeacon(tokens[0].receiptVault);
        receiptBeacon = readBeacon(tokens[0].receipt);

        for (uint256 i = 0; i < tokens.length; i++) {
            TokenInstance memory token = tokens[i];

            snapshots[i] = TokenConfigSnapshot({
                underlying: token.underlying,
                vaultName: IERC20Metadata(token.receiptVault).name(),
                vaultSymbol: IERC20Metadata(token.receiptVault).symbol(),
                vaultDecimals: IERC20Metadata(token.receiptVault).decimals(),
                wrappedName: IERC20Metadata(token.wrappedTokenVault).name(),
                wrappedSymbol: IERC20Metadata(token.wrappedTokenVault).symbol(),
                wrappedDecimals: IERC20Metadata(token.wrappedTokenVault).decimals()
            });

            // The receipt vault's live name/symbol equal the config baseline.
            assertEq(
                snapshots[i].vaultName,
                configs[i].name,
                string.concat(token.underlying, ": vault name != canonical config baseline")
            );
            assertEq(
                snapshots[i].vaultSymbol,
                configs[i].symbol,
                string.concat(token.underlying, ": vault symbol != canonical config baseline")
            );

            // Wiring: the wrapped vault wraps this token's receipt vault.
            assertEq(
                IERC4626(token.wrappedTokenVault).asset(),
                token.receiptVault,
                string.concat(token.underlying, ": wrapped.asset() != receiptVault")
            );

            // Uniform proxy bytecode within the chain, per leg.
            assertEq(
                token.receiptVault.codehash,
                receiptVaultProxyCodehash,
                string.concat(token.underlying, ": receipt vault proxy codehash not uniform on-chain")
            );
            assertEq(
                token.wrappedTokenVault.codehash,
                wrappedProxyCodehash,
                string.concat(token.underlying, ": wrapped vault proxy codehash not uniform on-chain")
            );

            // Single shared beacon per chain for the receipt-vault leg.
            assertEq(
                readBeacon(token.receiptVault),
                receiptVaultBeacon,
                string.concat(token.underlying, ": receipt vault proxies do not share one beacon")
            );

            // ERC-1155 receipt leg: the vault points at this token's pinned
            // receipt, the receipt points back at the vault as its manager,
            // and the receipt proxies are uniform bytecode + share one beacon
            // within the chain.
            assertEq(
                IReceiptVaultReceipt(token.receiptVault).receipt(),
                token.receipt,
                string.concat(token.underlying, ": receiptVault.receipt() != pinned receipt")
            );
            assertEq(
                IReceiptManager(token.receipt).manager(),
                token.receiptVault,
                string.concat(token.underlying, ": receipt.manager() != receiptVault")
            );
            assertEq(
                token.receipt.codehash,
                receiptProxyCodehash,
                string.concat(token.underlying, ": receipt proxy codehash not uniform on-chain")
            );
            assertEq(
                readBeacon(token.receipt),
                receiptBeacon,
                string.concat(token.underlying, ": receipt proxies do not share one beacon")
            );
        }
    }

    /// @notice Assert the chain's authoriser clone is deployed at its
    /// per-chain pin with the shared EIP-1167 codehash. The clone's
    /// role-grant map is asserted in `assertChainLegs` via
    /// `LibAuthoriserInvariants.assertExpectedGrants`.
    /// @param clone The chain's pinned V4 authoriser clone.
    function assertCloneParity(address clone) internal view {
        assertTrue(clone.code.length > 0, "V4 authoriser clone not deployed");
        assertEq(
            clone.codehash,
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH,
            "V4 authoriser clone codehash mismatch (shared EIP-1167 pin)"
        );
    }

    /// @notice A non-baseline chain's beacon carries none of the
    /// `LibProdDeployV2BaseOverrides` values: neither implementation nor
    /// owner.
    /// @param receiptVaultBeacon The beacon backing the chain's receipt
    /// vault proxies.
    function assertCleanV4Lineage(address receiptVaultBeacon) internal view {
        assertTrue(
            IBeacon(receiptVaultBeacon).implementation() != LibProdDeployV2BaseOverrides.RECEIPT_BEACON_IMPLEMENTATION
                && IBeacon(receiptVaultBeacon).implementation()
                    != LibProdDeployV2BaseOverrides.VAULT_BEACON_IMPLEMENTATION,
            "clean chain's beacon serves a V2 corruption-era implementation"
        );
        assertTrue(
            IOwnable(receiptVaultBeacon).owner() != LibProdDeployV2BaseOverrides.RECEIPT_BEACON_OWNER
                && IOwnable(receiptVaultBeacon).owner() != LibProdDeployV2BaseOverrides.VAULT_BEACON_OWNER,
            "clean chain's beacon is owned by a V2 corruption-era owner"
        );
    }

    /// @notice Token-table hydration state: whether any entry and whether all
    /// entries are fully set (all three addresses non-zero). A partially-set
    /// table (some entries set, some placeholder) is neither.
    /// @param tokens The chain's token table.
    /// @return anySet At least one entry has a non-placeholder address.
    /// @return allSet Every entry is fully hydrated.
    function _tokenTableState(TokenInstance[] memory tokens) internal pure returns (bool anySet, bool allSet) {
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

    /// @notice Assert two owner rosters are equal as sets (same length, same
    /// members), order-insensitive. Safe forbids duplicate owners, so equal
    /// lengths plus one-way membership is set equality.
    /// @param a One roster.
    /// @param b The other roster.
    function assertSameOwnerSet(address[] memory a, address[] memory b) internal pure {
        assertEq(a.length, b.length, "Safe owner count diverges cross-chain");
        for (uint256 i = 0; i < a.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < b.length; j++) {
                if (a[i] == b[j]) {
                    found = true;
                    break;
                }
            }
            assertTrue(found, "Safe owner set diverges cross-chain");
        }
    }

    /// @notice Unix timestamp (`2026-10-01T00:00:00Z`) past which Ethereum's
    /// legs must have armed.
    uint256 internal constant ETHEREUM_PARITY_DEADLINE = 1_790_812_800;

    /// @notice Unix timestamp (`2026-11-01T00:00:00Z`) past which the
    /// HyperEVM legs must have armed.
    uint256 internal constant HYPEREVM_PARITY_DEADLINE = 1_793_491_200;

    /// @notice Unix timestamp (`2026-12-01T00:00:00Z`) past which the
    /// Robinhood Chain legs must have armed.
    uint256 internal constant ROBINHOOD_PARITY_DEADLINE = 1_796_083_200;

    /// @notice Unix timestamp (`2026-12-01T00:00:00Z`) past which the BNB
    /// Smart Chain legs must have armed.
    uint256 internal constant BSC_PARITY_DEADLINE = 1_796_083_200;

    /// @notice Assert every live leg of a chain on the active fork, skipping
    /// (with a PENDING log) any leg whose pins are still placeholders, and
    /// capture what it read for the cross-chain comparison. The legs nest by
    /// dependency:
    ///  - **Safe leg** (needs the Safe): the Safe matches the shared policy.
    ///  - **Authoriser leg** (needs the clone; the grant map also needs the
    ///    Safe): the clone codehash + the role-grant map.
    ///  - **Token leg** (needs Safe + clone + the full token table): ownership
    ///    by the Safe, the clone as sole authoriser, config + beacon.
    /// @param label Human chain name, used in the PENDING logs.
    /// @param safe The chain's token-owner Safe pin.
    /// @param clone The chain's authoriser clone pin.
    /// @param tokens The chain's token table.
    /// @return legs What the live legs asserted + captured, for cross-chain use.
    function assertChainLegs(string memory label, address safe, address clone, TokenInstance[] memory tokens)
        internal
        returns (ChainLegs memory legs)
    {
        // --- Safe leg (needs: Safe) ---
        legs.safeLive = safe != address(0);
        if (legs.safeLive) {
            LibSafeInvariants.assertTokenOwnerSafePolicy(IGnosisSafe(safe));
            legs.owners = IGnosisSafe(safe).getOwners();
            legs.threshold = IGnosisSafe(safe).getThreshold();
        } else {
            emit log(string.concat("PARITY PENDING: ", label, " Safe pin placeholder - Safe leg skipped"));
        }

        // --- Authoriser leg (needs: clone; grant map also needs the Safe) ---
        legs.cloneLive = clone != address(0);
        if (legs.cloneLive) {
            assertCloneParity(clone);
            legs.cloneCodehash = clone.codehash;
            if (legs.safeLive) {
                LibAuthoriserInvariants.assertExpectedGrants(clone, safe);
            }
        } else {
            emit log(string.concat("PARITY PENDING: ", label, " clone pin placeholder - authoriser leg skipped"));
        }

        // --- Token leg (needs: Safe + clone + full token table) ---
        (bool anyToken, bool allTokens) = _tokenTableState(tokens);
        assertTrue(
            !anyToken || allTokens, string.concat(label, " token table partially hydrated - pin all triples together")
        );
        legs.tokenLegLive = legs.safeLive && legs.cloneLive && allTokens;
        if (legs.tokenLegLive) {
            // Ownership (Safe) + sole authoriser (clone) across every vault.
            LibTokenInvariants.assertAll(tokens, safe, clone);
            address beacon;
            address receiptBeacon;
            (legs.tokenConfigs, beacon, receiptBeacon) = assertChainAndSnapshot(tokens);
            // In-use beacons ride the fleet-upgrade window: 0.1.1 or 0.1.30
            // until `FLEET_UPGRADE_DEADLINE`, 0.1.30 only after.
            LibMigrationInvariant.assertMigration(
                string.concat(label, " in-use receipt-vault beacon implementation()"),
                IBeacon(beacon).implementation(),
                LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_1,
                LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30,
                FLEET_UPGRADE_DEADLINE
            );
            LibMigrationInvariant.assertMigration(
                string.concat(label, " in-use receipt beacon implementation()"),
                IBeacon(receiptBeacon).implementation(),
                LibProdDeployV4.STOX_RECEIPT_0_1_1,
                LibProdDeployV4.STOX_RECEIPT_0_1_30,
                FLEET_UPGRADE_DEADLINE
            );
            assertCleanV4Lineage(beacon);
            assertCleanV4Lineage(receiptBeacon);
            // Each chain's beacons are owned by that chain's own token-owner
            // Safe; cross-chain parity is on the impl the beacons point at.
            assertEq(
                IOwnable(beacon).owner(),
                safe,
                string.concat(label, " receipt-vault beacon not owned by the chain's Safe")
            );
            assertEq(
                IOwnable(receiptBeacon).owner(),
                safe,
                string.concat(label, " receipt beacon not owned by the chain's Safe")
            );
            legs.beaconImpl = IBeacon(beacon).implementation();
            legs.beaconImplCodehash = legs.beaconImpl.codehash;
            legs.receiptBeaconImpl = IBeacon(receiptBeacon).implementation();
            legs.receiptBeaconImplCodehash = legs.receiptBeaconImpl.codehash;
        } else if (legs.safeLive && legs.cloneLive) {
            emit log(string.concat("PARITY PENDING: ", label, " token table placeholder - token leg skipped"));
        }
    }

    /// @notice Compare one chain's live legs against Base's. Every comparison
    /// is gated on both sides carrying the leg; a pending leg on either side
    /// compares nothing.
    ///  - **Safe policy**: same owner set (order-insensitive) + threshold as
    ///    Base's live Safe.
    ///  - **Authoriser clone**: the clone codehashes match.
    ///  - **Token leg**: identical receipt-vault + receipt implementation
    ///    (address + codehash) through the beacons, and identical per-token
    ///    config in identical table order.
    /// @param label Human chain name, used in the assertion messages.
    /// @param base Base's legs, the reference.
    /// @param other The compared chain's legs.
    function assertParityWithBase(string memory label, ChainLegs memory base, ChainLegs memory other) internal pure {
        string memory tag = string.concat(" (", label, ")");
        if (base.safeLive && other.safeLive) {
            assertEq(other.threshold, base.threshold, string.concat("Safe threshold diverges cross-chain", tag));
            assertSameOwnerSet(base.owners, other.owners);
        }
        if (base.cloneLive && other.cloneLive) {
            assertEq(
                other.cloneCodehash,
                base.cloneCodehash,
                string.concat("authoriser clone impl codehash diverges cross-chain", tag)
            );
        }
        if (base.tokenLegLive && other.tokenLegLive) {
            assertEq(
                other.beaconImpl, base.beaconImpl, string.concat("receipt-vault beacon impl diverges cross-chain", tag)
            );
            assertEq(
                other.beaconImplCodehash,
                base.beaconImplCodehash,
                string.concat("receipt-vault beacon impl codehash diverges cross-chain", tag)
            );
            assertEq(
                other.receiptBeaconImpl,
                base.receiptBeaconImpl,
                string.concat("receipt beacon impl diverges cross-chain", tag)
            );
            assertEq(
                other.receiptBeaconImplCodehash,
                base.receiptBeaconImplCodehash,
                string.concat("receipt beacon impl codehash diverges cross-chain", tag)
            );
            assertEq(
                base.tokenConfigs.length, other.tokenConfigs.length, string.concat("token table lengths diverge", tag)
            );
            for (uint256 i = 0; i < base.tokenConfigs.length; i++) {
                TokenConfigSnapshot memory b = base.tokenConfigs[i];
                TokenConfigSnapshot memory o = other.tokenConfigs[i];
                assertEq(o.underlying, b.underlying, string.concat("token table underlying order diverges", tag));
                assertEq(o.vaultName, b.vaultName, string.concat(b.underlying, ": vault name diverges", tag));
                assertEq(o.vaultSymbol, b.vaultSymbol, string.concat(b.underlying, ": vault symbol diverges", tag));
                assertEq(o.vaultDecimals, b.vaultDecimals, string.concat(b.underlying, ": vault decimals diverge", tag));
                assertEq(o.wrappedName, b.wrappedName, string.concat(b.underlying, ": wrapped name diverges", tag));
                assertEq(
                    o.wrappedSymbol, b.wrappedSymbol, string.concat(b.underlying, ": wrapped symbol diverges", tag)
                );
                assertEq(
                    o.wrappedDecimals, b.wrappedDecimals, string.concat(b.underlying, ": wrapped decimals diverge", tag)
                );
            }
        }
    }

    /// @notice The cross-chain parity pin. Asserts each chain's live legs on
    /// its own fork (pending legs skipped + logged), then compares whatever is
    /// live on both chains.
    function testCrossChainParity() external {
        // Every fork is created before the first is selected. Foundry captures
        // the account set of the pre-fork EVM when the first fork is selected
        // and seeds every fork created after that capture with it, so an
        // address this test reads on Base would be carried onto the later
        // networks as the empty account the default EVM holds for it — the
        // first network right and every one after it wrong.
        string[] memory parityNetworks = new string[](5);
        parityNetworks[0] = LibRainDeploy.BASE;
        parityNetworks[1] = LibStoxDeployNetworks.ETHEREUM;
        parityNetworks[2] = LibStoxDeployNetworks.HYPEREVM;
        parityNetworks[3] = LibStoxDeployNetworks.ROBINHOOD;
        parityNetworks[4] = LibStoxDeployNetworks.BSC;
        uint256[] memory parityForks = LibRainDeploy.createForks(vm, parityNetworks);

        vm.selectFork(parityForks[0]);
        ChainLegs memory base = assertChainLegs(
            "Base",
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE,
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE,
            LibTokenInvariants.productionTokensBase()
        );

        vm.selectFork(parityForks[1]);
        ChainLegs memory eth = assertChainLegs(
            "Ethereum",
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM,
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM,
            LibTokenInvariants.productionTokensEthereum()
        );

        vm.selectFork(parityForks[2]);
        ChainLegs memory hyper = assertChainLegs(
            "HyperEVM",
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_HYPEREVM,
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_HYPEREVM,
            LibTokenInvariants.productionTokensHyperEvm()
        );

        vm.selectFork(parityForks[3]);
        ChainLegs memory robinhood = assertChainLegs(
            "Robinhood Chain",
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ROBINHOOD,
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ROBINHOOD,
            LibTokenInvariants.productionTokensRobinhood()
        );

        vm.selectFork(parityForks[4]);
        ChainLegs memory bsc = assertChainLegs(
            "BNB Smart Chain",
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_BSC,
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_BSC,
            LibTokenInvariants.productionTokensBsc()
        );

        // ---- Cross-chain comparisons, each gated on both sides being live ----
        assertParityWithBase("Ethereum", base, eth);
        assertParityWithBase("HyperEVM", base, hyper);
        assertParityWithBase("Robinhood Chain", base, robinhood);
        assertParityWithBase("BNB Smart Chain", base, bsc);

        // ---- The suite proves it ran ----

        // Every comparison above is gated on both chains carrying the leg;
        // these assertions separate a suite that skipped every comparison
        // from one that checked them.

        // Base is fully bootstrapped: a pending leg here is the placeholder
        // detection reading a live pin as a placeholder.
        assertTrue(base.safeLive, "Base Safe leg reported pending - parity comparisons are disabled");
        assertTrue(base.cloneLive, "Base authoriser leg reported pending - parity comparisons are disabled");
        assertTrue(base.tokenLegLive, "Base token leg reported pending - parity comparisons are disabled");

        // Past each chain's deadline a still-pending leg fails. The windows
        // are days wide; validator timestamp skew cannot change which side
        // of them a run lands on.
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp >= ETHEREUM_PARITY_DEADLINE) {
            assertTrue(eth.safeLive, "Ethereum Safe leg still pending past the parity deadline");
            assertTrue(eth.cloneLive, "Ethereum authoriser leg still pending past the parity deadline");
            assertTrue(eth.tokenLegLive, "Ethereum token leg still pending past the parity deadline");
        }

        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp >= HYPEREVM_PARITY_DEADLINE) {
            assertTrue(hyper.safeLive, "HyperEVM Safe leg still pending past the parity deadline");
            assertTrue(hyper.cloneLive, "HyperEVM authoriser leg still pending past the parity deadline");
            assertTrue(hyper.tokenLegLive, "HyperEVM token leg still pending past the parity deadline");
        }

        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp >= ROBINHOOD_PARITY_DEADLINE) {
            assertTrue(robinhood.safeLive, "Robinhood Chain Safe leg still pending past the parity deadline");
            assertTrue(robinhood.cloneLive, "Robinhood Chain authoriser leg still pending past the parity deadline");
            assertTrue(robinhood.tokenLegLive, "Robinhood Chain token leg still pending past the parity deadline");
        }

        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp >= BSC_PARITY_DEADLINE) {
            assertTrue(bsc.safeLive, "BNB Smart Chain Safe leg still pending past the parity deadline");
            assertTrue(bsc.cloneLive, "BNB Smart Chain authoriser leg still pending past the parity deadline");
            assertTrue(bsc.tokenLegLive, "BNB Smart Chain token leg still pending past the parity deadline");
        }
    }
}
