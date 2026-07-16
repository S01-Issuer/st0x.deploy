// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.6.1/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin-contracts-5.6.1/interfaces/IERC4626.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {ERC1967Utils} from "@openzeppelin-contracts-5.6.1/proxy/ERC1967/ERC1967Utils.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {IGnosisSafe} from "../../../../src/interface/IGnosisSafe.sol";
import {IOwnable} from "../../../../src/interface/IOwnable.sol";
import {LibAuthoriserInvariants} from "../../../../src/lib/LibAuthoriserInvariants.sol";
import {LibProdDeployV2BaseOverrides} from "../../../../src/lib/LibProdDeployV2BaseOverrides.sol";
import {LibProdDeployCurrent} from "../../../../src/generated/LibProdDeployCurrent.sol";
import {LibProdAuthoriserClones} from "../../../../src/lib/LibProdAuthoriserClones.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../../src/lib/LibStoxDeployNetworks.sol";
import {LibTokenInvariants, TokenInstance} from "../../../../src/lib/LibTokenInvariants.sol";

/// @notice Everything the parity suite reads per token instance on one
/// chain. Captured on the baseline chain (Base) fork, then compared
/// field-by-field on every other chain's fork.
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
    address beaconOwner;
}

/// @title StoxCrossChainParityTest
/// @notice The cross-chain deployment-parity pin (RAI-1097): an automated
/// invariant asserting every ST0x chain carries an IDENTICAL deployment —
/// identical core artifacts, identically-configured token instances,
/// identical permission structure — so parity cannot silently drift once
/// multichain is live. Runs in CI on every push and on the scheduled
/// workflow (drift introduced on-chain between pushes — a role grant, a
/// beacon upgrade — is caught by the schedule, not just by code changes).
///
/// Parity layers, per non-baseline chain vs Base (the baseline chain,
/// which carries the original production state):
///
/// 1. **Core artifacts** — the deterministic Zoltu addresses + codehashes
///    are asserted per-network by `StoxProdV4Test.checkAllV4OnChain`;
///    equality across chains follows because every network is checked
///    against the same pinned constants. This suite re-asserts only the
///    per-chain authoriser clones (the one non-deterministic core
///    artifact): pinned address, shared EIP-1167 codehash.
/// 2. **Token instances** — for every underlying in the per-chain token
///    tables: `name` / `symbol` / `decimals` of both vault legs equal the
///    Base baseline values (matched names / symbols by construction);
///    receipt + wrapped wiring is internally consistent
///    (`wrapped.asset() == receiptVault`); every receipt vault's
///    `authorizer()` is the chain's pinned V4 clone and its `owner()` is
///    the chain's token-owner Safe; all of a chain's proxies share one
///    runtime codehash per leg (beacon proxies — the codehash embeds the
///    beacon address, so it is uniform WITHIN a chain but legitimately
///    differs ACROSS chains; cross-chain implementation parity is asserted
///    through the beacon instead).
/// 3. **Beacon lineage** — each chain's receipt-vault proxies resolve
///    (via the ERC-1967 beacon slot) to a single beacon whose
///    `implementation()` is the deterministic V4 receipt vault impl —
///    the SAME address on every chain — and whose `owner()` is the
///    chain-agnostic deployer (`BEACON_INITIAL_OWNER`), the same address on
///    every chain (the beacon is deployer-owned; the token-owner Safe owns
///    the vaults, not the beacon). Cross-chain impl codehash parity is
///    asserted explicitly for both the authoriser clone (EIP-1167 over the
///    shared impl) and the receipt-vault beacon impl.
/// 4. **Role parity** — `LibAuthoriserInvariants.assertExpectedGrants` runs
///    against each chain's clone with that chain's token-owner Safe: the
///    identical grant STRUCTURE on every chain, the service-signer holder
///    shared, the Safe holder the chain's own per-chain Safe. The Safe policy
///    (owner set, threshold, v1.4.1 identity) is asserted equal to Base's, and
///    the Ethereum Safe's live owner set + threshold are compared directly to
///    Base's. Per-chain: the Safe address, the clone address, the token
///    addresses.
///
/// **Known-divergence carve-out (Base V2 beacon corruption).** Base's V2
/// OARV beacon set was corrupted post-deploy (impl downgrade + ownership
/// lock, pinned in `LibProdDeployV2BaseOverrides`). Production tokens on
/// Base never used those beacons (they run on the healthy V1 set), and no
/// new chain deploys V2 at all — Ethereum bootstraps directly at V4. The
/// carve-out is encoded, not implied: `assertCleanV4Lineage` asserts that
/// no non-baseline chain's token proxies resolve to ANY pinned V2 beacon
/// address, so the corrupted artifacts can neither mask drift on Base nor
/// leak into expectations for chains that deploy clean.
///
/// **Per-leg placeholder gating.** Each chain's per-chain deploy artifacts —
/// the token-owner Safe address, the authoriser clone address, the token
/// addresses — start as `address(0)` placeholders and are hydrated by pin PRs
/// as each is deployed. The suite asserts each leg only when its pins are set,
/// skipping placeholder legs with a loud `PARITY PENDING` log (never a silent
/// skip), and the cross-chain comparisons gate on both chains carrying the
/// leg. The legs nest by dependency: the **Safe leg** needs the Safe; the
/// **authoriser leg** needs the clone (its grant map also needs the Safe) and
/// is assertable as soon as the clone is up, independent of the tokens; the
/// **token leg** needs the Safe + clone + full token table. This is what lets
/// the whole multichain stack merge green before any chain is bootstrapped:
/// every leg skips, and each pin PR turns its leg (and its cross-chain
/// comparison) on. The one hard failure is a PARTIALLY-hydrated token table
/// (some triples set, some placeholder) — an operator error the token pin PR
/// must avoid by setting all triples together.
contract StoxCrossChainParityTest is Test {
    /// @notice Read the address stored in `proxy`'s ERC-1967 beacon slot.
    /// @param proxy The beacon-proxy address on the active fork.
    /// @return beacon The beacon address backing the proxy.
    function readBeacon(address proxy) internal view returns (address beacon) {
        beacon = address(uint160(uint256(vm.load(proxy, ERC1967Utils.BEACON_SLOT))));
    }

    /// @notice Capture one chain's per-token config snapshot on the ACTIVE
    /// fork and assert the parity-specific per-token properties the shared
    /// framework does not cover: receipt/wrapped wiring, per-leg proxy
    /// codehash uniformity within the chain, and the single shared beacon.
    /// @dev The uniform owner + sole-authoriser checks are NOT here — the token
    /// leg in `assertChainLegs` asserts them via
    /// `LibTokenInvariants.assertAll(tokens, safe, clone)`; this function adds
    /// only the per-token config snapshot + within-chain uniformity that the
    /// cross-chain comparison builds on.
    /// @param tokens The chain's token table.
    /// @return snapshots Per-token config snapshots, table order.
    /// @return receiptVaultBeacon The single beacon backing every receipt
    /// vault proxy on this chain.
    function assertChainAndSnapshot(TokenInstance[] memory tokens)
        internal
        view
        returns (TokenConfigSnapshot[] memory snapshots, address receiptVaultBeacon)
    {
        snapshots = new TokenConfigSnapshot[](tokens.length);

        // Per-leg proxy-codehash uniformity within the chain.
        bytes32 receiptVaultProxyCodehash = tokens[0].receiptVault.codehash;
        bytes32 wrappedProxyCodehash = tokens[0].wrappedTokenVault.codehash;
        receiptVaultBeacon = readBeacon(tokens[0].receiptVault);

        for (uint256 i = 0; i < tokens.length; i++) {
            TokenInstance memory token = tokens[i];

            // Config via view calls — covers matched names / symbols /
            // decimals once compared against the baseline snapshot.
            snapshots[i] = TokenConfigSnapshot({
                underlying: token.underlying,
                vaultName: IERC20Metadata(token.receiptVault).name(),
                vaultSymbol: IERC20Metadata(token.receiptVault).symbol(),
                vaultDecimals: IERC20Metadata(token.receiptVault).decimals(),
                wrappedName: IERC20Metadata(token.wrappedTokenVault).name(),
                wrappedSymbol: IERC20Metadata(token.wrappedTokenVault).symbol(),
                wrappedDecimals: IERC20Metadata(token.wrappedTokenVault).decimals()
            });

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
        }
    }

    /// @notice Assert the chain's authoriser clone is deployed at its
    /// per-chain pin with the shared EIP-1167 codehash. This is the
    /// deploy-artifact half (address + bytecode); the clone's role-grant
    /// map is asserted through the shared framework
    /// (`LibInvariants.assertProductionState` →
    /// `LibAuthoriserInvariants.assertExpectedGrants`) in
    /// `testCrossChainParity`, so it is not repeated here.
    /// @param clone The chain's pinned V4 authoriser clone.
    function assertCloneParity(address clone) internal view {
        assertTrue(clone.code.length > 0, "V4 authoriser clone not deployed");
        assertEq(
            clone.codehash,
            LibProdAuthoriserClones.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH,
            "V4 authoriser clone codehash mismatch (shared EIP-1167 pin)"
        );
    }

    /// @notice The Base-V2-corruption carve-out, stated as a positive
    /// invariant on clean chains. Base's V2 OARV beacons were corrupted
    /// post-deploy (impl downgraded, ownership locked into the V2
    /// contracts — the exact values are pinned in
    /// `LibProdDeployV2BaseOverrides`). That corruption is a named,
    /// Base-only exception: production tokens on Base never used those
    /// beacons, and no clean chain deploys V2 at all. This assertion makes
    /// the exception explicit on the clean side — a non-baseline chain's
    /// beacon must not carry any corruption-era value — so the carve-out
    /// can neither mask new drift on Base nor leak into expectations for
    /// chains that bootstrap directly at V4.
    /// @param receiptVaultBeacon The beacon backing the chain's receipt
    /// vault proxies (already asserted to serve the V4 impl).
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

    /// @notice Token-table hydration state: whether ANY entry and whether ALL
    /// entries are fully set (all three addresses non-zero). A partially-set
    /// table (some entries set, some placeholder) is neither — the caller
    /// rejects that as an operator error.
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

    /// @notice Assert two owner rosters are equal as SETS (same length, same
    /// members) — order-insensitive. Safe forbids duplicate owners, so equal
    /// lengths plus one-way membership is full set equality.
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

    /// @notice Assert every LIVE leg of a chain on the ACTIVE fork, skipping
    /// (with a loud PENDING log) any leg whose pins are still placeholders, and
    /// capture what it read for the cross-chain comparison. The legs are nested
    /// by dependency:
    ///  - **Safe leg** (needs the Safe): the Safe matches Base's policy.
    ///  - **Authoriser leg** (needs the clone; the grant map also needs the
    ///    Safe): the clone codehash + the role-grant map. Assertable as soon as
    ///    the clone is up — it does NOT wait on the tokens.
    ///  - **Token leg** (needs Safe + clone + the full token table): ownership
    ///    by the Safe, the clone as sole authoriser, config + beacon.
    /// Skipping placeholder legs is what lets the whole stack merge green: an
    /// un-bootstrapped chain skips every leg, and each pin PR turns its leg on.
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
            LibSafeInvariants.assertPolicyMatchesBase(IGnosisSafe(safe));
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
                // The grant map is assertable as soon as the clone is up — its
                // only blocker is the Safe, independent of the tokens.
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
            (legs.tokenConfigs, beacon) = assertChainAndSnapshot(tokens);
            assertEq(
                IBeacon(beacon).implementation(),
                LibProdDeployCurrent.STOX_RECEIPT_VAULT,
                string.concat(label, " receipt-vault beacon does not serve the V4 impl")
            );
            assertCleanV4Lineage(beacon);
            legs.beaconImpl = IBeacon(beacon).implementation();
            legs.beaconImplCodehash = legs.beaconImpl.codehash;
            legs.beaconOwner = IOwnable(beacon).owner();
        } else if (legs.safeLive && legs.cloneLive) {
            emit log(string.concat("PARITY PENDING: ", label, " token table placeholder - token leg skipped"));
        }
    }

    /// @notice The cross-chain parity pin. Asserts each chain's LIVE legs on
    /// its own fork (pending legs skipped + logged), then compares whatever is
    /// live on BOTH chains. Every comparison is gated on both sides carrying
    /// the relevant leg, so an un-bootstrapped chain leaves the suite green and
    /// each pin PR turns its comparisons on.
    function testCrossChainParity() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        ChainLegs memory base = assertChainLegs(
            "Base",
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE,
            LibProdAuthoriserClones.STOX_PROD_AUTHORISER_V4_CLONE_BASE,
            LibTokenInvariants.productionTokensBase()
        );

        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        ChainLegs memory eth = assertChainLegs(
            "Ethereum",
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM,
            LibProdAuthoriserClones.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM,
            LibTokenInvariants.productionTokensEthereum()
        );

        // ---- Cross-chain comparisons, each gated on both sides being live ----

        // Safe policy: same owner SET (order-insensitive) + threshold, compared
        // against Base's LIVE Safe (the Ethereum Safe is a distinct per-chain
        // address that must still carry Base's exact policy).
        if (base.safeLive && eth.safeLive) {
            assertEq(eth.threshold, base.threshold, "Safe threshold diverges cross-chain");
            assertSameOwnerSet(base.owners, eth.owners);
        }

        // Authoriser clone: EIP-1167 over the same impl on every chain, so the
        // clone codehashes match.
        if (base.cloneLive && eth.cloneLive) {
            assertEq(eth.cloneCodehash, base.cloneCodehash, "authoriser clone impl codehash diverges cross-chain");
        }

        // Token leg: identical receipt-vault implementation (address + codehash)
        // through the beacon, the shared beacon deployer, and identical per-token
        // config in identical table order.
        if (base.tokenLegLive && eth.tokenLegLive) {
            assertEq(eth.beaconImpl, base.beaconImpl, "receipt-vault beacon impl diverges cross-chain");
            assertEq(
                eth.beaconImplCodehash,
                base.beaconImplCodehash,
                "receipt-vault beacon impl codehash diverges cross-chain"
            );
            assertEq(eth.beaconOwner, base.beaconOwner, "receipt-vault beacon owner diverges cross-chain");

            assertEq(base.tokenConfigs.length, eth.tokenConfigs.length, "token table lengths diverge");
            for (uint256 i = 0; i < base.tokenConfigs.length; i++) {
                TokenConfigSnapshot memory b = base.tokenConfigs[i];
                TokenConfigSnapshot memory o = eth.tokenConfigs[i];
                assertEq(o.underlying, b.underlying, "token table underlying order diverges");
                assertEq(o.vaultName, b.vaultName, string.concat(b.underlying, ": vault name diverges"));
                assertEq(o.vaultSymbol, b.vaultSymbol, string.concat(b.underlying, ": vault symbol diverges"));
                assertEq(o.vaultDecimals, b.vaultDecimals, string.concat(b.underlying, ": vault decimals diverge"));
                assertEq(o.wrappedName, b.wrappedName, string.concat(b.underlying, ": wrapped name diverges"));
                assertEq(o.wrappedSymbol, b.wrappedSymbol, string.concat(b.underlying, ": wrapped symbol diverges"));
                assertEq(
                    o.wrappedDecimals, b.wrappedDecimals, string.concat(b.underlying, ": wrapped decimals diverge")
                );
            }
        }
    }
}
