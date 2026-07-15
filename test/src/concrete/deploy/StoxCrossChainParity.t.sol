// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.6.1/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin-contracts-5.6.1/interfaces/IERC4626.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {ERC1967Utils} from "@openzeppelin-contracts-5.6.1/proxy/ERC1967/ERC1967Utils.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {IOwnable} from "../../../../src/interface/IOwnable.sol";
import {LibInvariants} from "../../../../src/lib/LibInvariants.sol";
import {LibProdDeployV2BaseOverrides} from "../../../../src/lib/LibProdDeployV2BaseOverrides.sol";
import {LibProdDeployCurrent} from "../../../../src/generated/LibProdDeployCurrent.sol";
import {LibProdAuthoriserClones} from "../../../../src/lib/LibProdAuthoriserClones.sol";
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
///    the SAME address on every chain — and whose `owner()` is the shared
///    token-owner Safe (the same address on every chain). Cross-chain impl
///    codehash parity is asserted explicitly for both the authoriser clone
///    (EIP-1167 over the shared impl) and the receipt-vault beacon impl.
/// 4. **Role parity** — `LibAuthoriserInvariants.assertExpectedGrants`
///    runs against each chain's clone with the SHARED grant map: identical
///    structure AND identical holder addresses on every chain (the token-
///    owner Safe and service signer are shared). Only the clone ADDRESS is
///    per-chain; its grants are not.
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
/// **Pending-bootstrap chains.** Until a chain's bootstrap executes, its
/// deploy-artifact pins are placeholders (the token-owner Safe + grant map
/// are shared and always concrete — same matched-address Safe + shared
/// signer on every chain; only the clone + token addresses are per-chain).
/// The suite accepts exactly two states per chain: fully PENDING (the
/// authoriser clone pin AND every token entry all placeholder — logged
/// loudly, parity assertions skipped) or fully LIVE (every artifact
/// hydrated — all layers asserted, including each chain independently
/// satisfying `LibInvariants.assertProductionState`). Partial hydration
/// fails the suite.
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
    /// @dev The uniform owner + authoriser checks are NOT here — they are
    /// asserted through `LibInvariants.assertProductionState` (the shared
    /// multichain framework) in `testCrossChainParity`, so each chain first
    /// satisfies the same production-state invariant Base does, and this
    /// function adds only the cross-chain-comparison scaffolding on top.
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

    /// @notice True when the chain is cleanly pre-bootstrap: its authoriser
    /// clone pin AND every token-table entry are still `address(0)`
    /// placeholders. The principals are not part of this check — they are
    /// concrete pins on every chain (the matched-address Safe + shared
    /// signer); "bootstrapped or not" is a property of the DEPLOY ARTIFACTS
    /// (clone + token addresses), which is exactly what this reads. Any mixed
    /// state returns false on both this and the fully-hydrated check, which
    /// the test treats as failure.
    /// @param clone The chain's authoriser clone pin.
    /// @param tokens The chain's token table.
    /// @return pending Whether the chain is cleanly pre-bootstrap.
    function isFullyPending(address clone, TokenInstance[] memory tokens) internal pure returns (bool pending) {
        pending = clone == address(0);
        for (uint256 i = 0; i < tokens.length; i++) {
            pending = pending && tokens[i].receipt == address(0) && tokens[i].receiptVault == address(0)
                && tokens[i].wrappedTokenVault == address(0);
        }
    }

    /// @notice True when every deploy-artifact pin for the chain is
    /// hydrated: the authoriser clone AND every token-table entry.
    /// @param clone The chain's authoriser clone pin.
    /// @param tokens The chain's token table.
    /// @return hydrated Whether the chain is fully live.
    function isFullyHydrated(address clone, TokenInstance[] memory tokens) internal pure returns (bool hydrated) {
        hydrated = clone != address(0);
        for (uint256 i = 0; i < tokens.length; i++) {
            hydrated = hydrated && tokens[i].receipt != address(0) && tokens[i].receiptVault != address(0)
                && tokens[i].wrappedTokenVault != address(0);
        }
    }

    /// @notice The full cross-chain parity pin: snapshot Base (asserting
    /// its own uniformity + policy state as it goes), then assert every
    /// other supported chain against the snapshot, or assert it is cleanly
    /// pending bootstrap.
    function testCrossChainParity() external {
        // ---- Reference chain: Base ----
        vm.createSelectFork(LibRainDeploy.BASE);
        address baseClone = LibProdAuthoriserClones.STOX_PROD_AUTHORISER_V4_CLONE_BASE;
        assertTrue(baseClone != address(0), "Base V4 clone pin still placeholder (stack not yet executed)");
        TokenInstance[] memory baseTokens = LibTokenInvariants.productionTokensBase();
        // Shared multichain framework: Base satisfies the full production-state
        // invariant (shared Safe identity/config, token owner + authoriser
        // uniformity, shared authoriser grant map) — the same call the Ethereum
        // branch makes below. Only the token table + clone address are passed;
        // the Safe and grant map are shared across chains.
        LibInvariants.assertProductionState(baseTokens, baseClone);
        assertCloneParity(baseClone);
        (TokenConfigSnapshot[] memory baseline, address baseBeacon) = assertChainAndSnapshot(baseTokens);
        // Base's beacon lineage: the receipt-vault beacon must serve the
        // deterministic V4 impl post-upgrade. (Base's beacon ADDRESS is the
        // healthy V1-era beacon — upgraded in place — which is exactly why
        // implementation parity is asserted through the beacon rather than
        // by comparing proxy codehashes across chains.)
        assertEq(
            IBeacon(baseBeacon).implementation(),
            LibProdDeployCurrent.STOX_RECEIPT_VAULT,
            "Base receipt-vault beacon does not serve the V4 impl"
        );
        address baseBeaconOwner = IOwnable(baseBeacon).owner();

        // ---- Ethereum ----
        address ethClone = LibProdAuthoriserClones.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM;
        TokenInstance[] memory ethTokens = LibTokenInvariants.productionTokensEthereum();

        if (isFullyPending(ethClone, ethTokens)) {
            // Cleanly pre-bootstrap: nothing to check on-chain yet. Logged
            // loudly (not a silent skip) so a green run cannot be misread
            // as "Ethereum verified".
            emit log("PARITY: Ethereum PENDING bootstrap - clone + token pins placeholder, parity assertions skipped");
            return;
        }
        // Not fully pending => must be fully hydrated. Partial hydration
        // is the dangerous middle state this assertion exists to reject.
        assertTrue(
            isFullyHydrated(ethClone, ethTokens),
            "Ethereum pins partially hydrated - hydrate the clone pin and the full token table in one pin PR"
        );

        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        // Same shared framework call as Base: Ethereum must independently
        // satisfy the full production-state invariant (its matched-address
        // Safe policy-aligned to Base, its vaults uniform, its clone grants
        // in place) before any cross-chain comparison is meaningful.
        LibInvariants.assertProductionState(ethTokens, ethClone);
        assertCloneParity(ethClone);
        (TokenConfigSnapshot[] memory observed, address ethBeacon) = assertChainAndSnapshot(ethTokens);

        // Layer 3: identical implementation through the beacon, clean V4
        // lineage, shared beacon owner.
        assertEq(
            IBeacon(ethBeacon).implementation(),
            LibProdDeployCurrent.STOX_RECEIPT_VAULT,
            "Ethereum receipt-vault beacon does not serve the V4 impl"
        );
        assertCleanV4Lineage(ethBeacon);
        // The beacon owner is the shared token-owner Safe (same address on
        // every chain), so it must be byte-for-byte Base's beacon owner.
        assertEq(
            IOwnable(ethBeacon).owner(),
            baseBeaconOwner,
            "Ethereum receipt-vault beacon owner diverges from Base's shared owner"
        );

        // Cross-chain IMPL CODEHASH parity — the per-chain-unique artifacts
        // (authoriser clone address, token addresses) must still resolve to
        // the SAME implementations on every chain:
        //   - the authoriser clone is an EIP-1167 proxy whose runtime embeds
        //     the impl address, so equal clone codehashes prove equal impls;
        //   - the receipt-vault beacon serves the deterministic V4 impl (its
        //     address already asserted equal above), so its codehash matches.
        // Both are asserted against Base explicitly here, on top of each
        // chain's clone being checked against the shared codehash pin.
        assertEq(ethClone.codehash, baseClone.codehash, "authoriser clone impl codehash diverges cross-chain");
        assertEq(
            IBeacon(ethBeacon).implementation().codehash,
            IBeacon(baseBeacon).implementation().codehash,
            "receipt-vault beacon impl codehash diverges cross-chain"
        );

        // Layer 2 cross-chain: identical config per underlying, in
        // identical table order.
        assertEq(baseline.length, observed.length, "token table lengths diverge");
        for (uint256 i = 0; i < baseline.length; i++) {
            assertEq(observed[i].underlying, baseline[i].underlying, "token table underlying order diverges");
            string memory key = baseline[i].underlying;
            assertEq(observed[i].vaultName, baseline[i].vaultName, string.concat(key, ": vault name diverges"));
            assertEq(observed[i].vaultSymbol, baseline[i].vaultSymbol, string.concat(key, ": vault symbol diverges"));
            assertEq(
                observed[i].vaultDecimals, baseline[i].vaultDecimals, string.concat(key, ": vault decimals diverge")
            );
            assertEq(observed[i].wrappedName, baseline[i].wrappedName, string.concat(key, ": wrapped name diverges"));
            assertEq(
                observed[i].wrappedSymbol, baseline[i].wrappedSymbol, string.concat(key, ": wrapped symbol diverges")
            );
            assertEq(
                observed[i].wrappedDecimals,
                baseline[i].wrappedDecimals,
                string.concat(key, ": wrapped decimals diverge")
            );
        }
    }
}
