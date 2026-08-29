// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.6.1/token/ERC20/extensions/IERC20Metadata.sol";

import {IGnosisSafe} from "../src/interface/IGnosisSafe.sol";
import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibBeaconInvariants} from "../src/lib/LibBeaconInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "../src/lib/LibTokenInvariants.sol";
import {LibSafeOps, SafeTx} from "../src/lib/LibSafeOps.sol";

/// @dev Unix timestamp (2026-10-01T00:00:00Z) by which the fleet upgrade
/// must have executed on every chain. Shared by the migration-window
/// invariants that accept either the 0.1.1 or 0.1.30 implementation until
/// then; the orchestrator rollout shares the same date — this upgrade gates
/// its cutover.
uint256 constant FLEET_UPGRADE_DEADLINE = 1_790_812_800;

/// @notice A 0.1.30 implementation this upgrade would repoint a beacon to
/// has no runtime code (or the wrong codehash) on the active chain. Ship the
/// audited closure via `manual-sol-artifacts-0-1-30.yaml` first.
/// @param impl The pinned 0.1.30 implementation inspected.
error UpgradeTargetNotDeployed(address impl);

/// @notice A production beacon is neither in the pre-upgrade (0.1.1) nor the
/// post-upgrade (0.1.30) implementation state — unknown drift; resolve
/// manually rather than upgrading over it.
/// @param beacon The beacon inspected.
/// @param actualImpl The implementation it points at.
error BeaconInUnknownState(address beacon, address actualImpl);

/// @notice Both gated beacons already serve the 0.1.30 implementations —
/// the fleet upgrade has executed on this chain and a re-dispatch has
/// nothing to author.
error FleetAlreadyUpgraded();

/// @notice A production token's reported state changed across the simulated
/// upgrade. The 0.1.30 receipt-vault impl (the H01 remediation) must leave
/// every reported balance and supply exactly as it was.
/// @param receiptVault The vault whose reads drifted.
error UpgradeChangedTokenState(address receiptVault);

/// @title UpgradeFleetTo0_1_30
/// @notice **PENDING.** Authors the per-chain Safe Tx Builder bundle that
/// upgrades the production token fleet to the audited 0.1.30
/// implementations — one atomic MultiSend repointing the chain's IN-USE
/// receipt beacon and receipt-vault beacon (`upgradeTo`) from the audited
/// 0.1.1 impls to the audited 0.1.30 impls. Every production token is a
/// proxy of these two beacons, so the whole fleet moves in one batch: this
/// is the H01 remediation going live, and the state the orchestrator
/// cutover (`20260825-cutover-orchestrator-roles`) hard-gates on.
///
/// The wrapped-token-vault beacon is deliberately NOT repointed: the 0.1.30
/// WTV bytecode differs only by the optimizer change (no behavioural delta,
/// no audit finding), and the coordinated-release note in `CHANGELOG.md`
/// scopes the lockstep set to the receipt vault (the fix), the
/// corporate-actions facet (baked into the new vault) and the receipt (the
/// orchestrator's lockstep partner). Repointing WTV is a separate decision.
///
/// @dev Dispatch via `Actions → run-script` with
/// `script = 20260825-upgrade-fleet-to-0-1-30` per chain; sign and execute
/// the artifact in the Safe UI (the in-use beacons are owned by each
/// chain's token-owner Safe). Dispatch the three chains in ONE operational
/// window — cross-chain parity is red in between, by design.
///
/// Pre-flight: the 0.1.30 receipt, receipt-vault and corporate-actions
/// facet must be live at their pins by codehash (the new vault's
/// `fallback()` delegatecalls the new facet — a code-less facet silently
/// no-ops); each gated beacon must be exactly in the 0.1.1 state (or
/// already upgraded — self-scoped); the Safe must own both beacons. The
/// simulation then proves, for EVERY production token on the chain, that
/// `totalSupply` / `symbol` / `decimals` read identically across the
/// upgrade — the H01 fix changes internal accounting, never reported state.
///
/// The post-execution pin PR flips `LibProdBeaconsBase` /
/// `LibProdBeacons0_1_1`'s `implementations()` (and the fork asserts riding
/// them) to the 0.1.30 pins and retires this script's fixtures.
contract UpgradeFleetTo0_1_30 is Script {
    /// @notice Signer-visible `meta.name` for the emitted bundle.
    string internal constant BUNDLE_NAME = "ST0x fleet upgrade: receipt + receipt-vault beacons to audited 0.1.30";

    /// @notice Chain-suffixed artifact path (three chains dispatch in one
    /// window; a shared path would let bundles overwrite each other).
    /// @return path The artifact path for the ACTIVE chain.
    function artifactPath() internal view virtual returns (string memory path) {
        path = string.concat("out/20260825-upgrade-fleet-to-0-1-30-", vm.toString(block.chainid), ".json");
    }

    /// @notice Assert one 0.1.30 upgrade target is live at its pin with the
    /// audited codehash.
    /// @param impl The pinned implementation address.
    /// @param codehash The pinned 0.1.30 codehash.
    function assertTargetDeployed(address impl, bytes32 codehash) internal view {
        if (impl.code.length == 0 || impl.codehash != codehash) {
            revert UpgradeTargetNotDeployed(impl);
        }
    }

    /// @notice Pre-flight the beacons and self-scope the bundle: one
    /// `upgradeTo` per gated beacon still serving 0.1.1. A beacon in
    /// neither state is unknown drift; both already at 0.1.30 refuses.
    /// @return txs The self-scoped upgrade transactions.
    /// @dev The two gated beacons are resolved by role, not by position in
    /// `prodBeaconsForChainId`, so that set can gain the orchestrator beacon
    /// (#333) without this bundle silently re-pointing at a different one.
    function authorBundle() internal view returns (SafeTx[] memory txs) {
        address[2] memory gated = [
            LibBeaconInvariants.receiptBeaconForChainId(block.chainid),
            LibBeaconInvariants.receiptVaultBeaconForChainId(block.chainid)
        ];
        address[2] memory pre = [LibProdDeployV4.STOX_RECEIPT_0_1_1, LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_1];
        address[2] memory post = [LibProdDeployV4.STOX_RECEIPT_0_1_30, LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30];

        SafeTx[] memory candidates = new SafeTx[](2);
        uint256 count = 0;
        for (uint256 i = 0; i < gated.length; i++) {
            address actual = IBeacon(gated[i]).implementation();
            if (actual == post[i]) {
                continue;
            }
            if (actual != pre[i]) {
                revert BeaconInUnknownState(gated[i], actual);
            }
            candidates[count++] = SafeTx({
                to: gated[i], value: 0, data: abi.encodeCall(IUpgradeableBeaconLike.upgradeTo, (post[i])), operation: 0
            });
        }
        if (count == 0) {
            revert FleetAlreadyUpgraded();
        }
        txs = new SafeTx[](count);
        for (uint256 i = 0; i < count; i++) {
            txs[i] = candidates[i];
        }
    }

    /// @notice The active chain's production token table (empty tables are
    /// valid — a chain carrying no tokens yet has nothing to snapshot).
    /// @return tokens The chain's token instances.
    function activeChainTokens() internal view returns (TokenInstance[] memory tokens) {
        if (block.chainid == LibSafeInvariants.BASE_CHAIN_ID) {
            return LibTokenInvariants.productionTokensBase();
        }
        if (block.chainid == LibSafeInvariants.ETHEREUM_CHAIN_ID) {
            return LibTokenInvariants.productionTokensEthereum();
        }
        return LibTokenInvariants.productionTokensHyperEvm();
    }

    /// @notice Snapshot every production token's reported state (receipt
    /// vault `totalSupply`, `symbol` hash, `decimals`) so the post-upgrade
    /// reads can be proven identical.
    /// @param tokens The chain's token instances.
    /// @return supplies Each vault's `totalSupply`.
    /// @return metaHashes keccak of each vault's `symbol` + `decimals`.
    function snapshotTokenState(TokenInstance[] memory tokens)
        internal
        view
        returns (uint256[] memory supplies, bytes32[] memory metaHashes)
    {
        supplies = new uint256[](tokens.length);
        metaHashes = new bytes32[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20Metadata vault = IERC20Metadata(tokens[i].receiptVault);
            supplies[i] = vault.totalSupply();
            metaHashes[i] = keccak256(abi.encode(vault.symbol(), vault.decimals()));
        }
    }

    /// @notice Assert every token's reported state is unchanged against the
    /// pre-upgrade snapshot — the H01 fix must be invisible in reads.
    /// @param tokens The chain's token instances.
    /// @param supplies The pre-upgrade `totalSupply` snapshot.
    /// @param metaHashes The pre-upgrade metadata snapshot.
    function assertTokenStatePreserved(
        TokenInstance[] memory tokens,
        uint256[] memory supplies,
        bytes32[] memory metaHashes
    ) internal view {
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20Metadata vault = IERC20Metadata(tokens[i].receiptVault);
            if (
                vault.totalSupply() != supplies[i]
                    || keccak256(abi.encode(vault.symbol(), vault.decimals())) != metaHashes[i]
            ) {
                revert UpgradeChangedTokenState(tokens[i].receiptVault);
            }
        }
    }

    /// @notice Author the fleet-upgrade bundle for the active chain: see
    /// the contract-level flow. Does not broadcast — execution happens via
    /// the Safe UI using the emitted artifact.
    function run() external {
        // --- Pre-flight ---------------------------------------------------

        address safeAddr = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        IGnosisSafe safe = IGnosisSafe(safeAddr);

        // The audited 0.1.30 targets (and the facet the new vault
        // delegatecalls) must be live at their pins by codehash.
        assertTargetDeployed(LibProdDeployV4.STOX_RECEIPT_0_1_30, LibProdDeployV4.STOX_RECEIPT_CODEHASH_0_1_30);
        assertTargetDeployed(
            LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30, LibProdDeployV4.STOX_RECEIPT_VAULT_CODEHASH_0_1_30
        );
        assertTargetDeployed(
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_0_1_30,
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CODEHASH_0_1_30
        );

        // The in-use beacons are deployed, OZ bytecode, Safe-owned.
        LibBeaconInvariants.assertProdBeaconsOwnedByChainSafe(block.chainid);
        address receiptBeacon = LibBeaconInvariants.receiptBeaconForChainId(block.chainid);
        address receiptVaultBeacon = LibBeaconInvariants.receiptVaultBeaconForChainId(block.chainid);

        // --- Build the bundle ----------------------------------------------

        SafeTx[] memory txs = authorBundle();

        uint256 nonce = safe.nonce();
        bytes32 bundleSafeTxHash = LibSafeOps.computeMultiSendSafeTxHash(safe, txs, nonce);

        // --- Simulate, proving token-state preservation --------------------

        TokenInstance[] memory tokens = activeChainTokens();
        (uint256[] memory supplies, bytes32[] memory metaHashes) = snapshotTokenState(tokens);

        for (uint256 i = 0; i < txs.length; i++) {
            LibSafeOps.simulateExternalCall(safe, txs[i].to, txs[i].data);
        }

        // --- Post-state ---------------------------------------------------

        require(
            IBeacon(receiptBeacon).implementation() == LibProdDeployV4.STOX_RECEIPT_0_1_30
                && IBeacon(receiptVaultBeacon).implementation() == LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30,
            "UpgradeFleetTo0_1_30: beacons did not land on the 0.1.30 impls"
        );
        assertTokenStatePreserved(tokens, supplies, metaHashes);
        LibSafeInvariants.assertImmutableInvariants(safe);
        LibSafeInvariants.assertThreshold(safe, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD);

        // --- Artifact -----------------------------------------------------

        string memory json = LibSafeOps.emitTxBuilderJson(safeAddr, block.chainid, BUNDLE_NAME, txs);
        vm.writeFile(artifactPath(), json);

        console2.log("==== TX BUILDER JSON BEGIN ====");
        console2.log(json);
        console2.log("==== TX BUILDER JSON END ====");
        console2.log("Bundle MultiSend SafeTxHash:", vm.toString(bundleSafeTxHash));
        console2.log("Nonce:", nonce);
        console2.log("Bundle item count:", txs.length);
        console2.log("Chain:", block.chainid);
        console2.log("Tokens proven state-preserving across the upgrade:", tokens.length);

        // --- n+1 reversal proof --------------------------------------------

        // The upgrade is reversible while the Safe owns the beacons: prove a
        // downgrade back to 0.1.1 clears the live threshold, then re-upgrade
        // so the fork ends on 0.1.30.
        LibSafeOps.simulateNPlus1(
            safe,
            receiptBeacon,
            abi.encodeCall(IUpgradeableBeaconLike.upgradeTo, (LibProdDeployV4.STOX_RECEIPT_0_1_1)),
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD
        );
        require(
            IBeacon(receiptBeacon).implementation() == LibProdDeployV4.STOX_RECEIPT_0_1_1,
            "UpgradeFleetTo0_1_30: n+1 downgrade did not land"
        );
        LibSafeOps.simulateExternalCall(
            safe, receiptBeacon, abi.encodeCall(IUpgradeableBeaconLike.upgradeTo, (LibProdDeployV4.STOX_RECEIPT_0_1_30))
        );
        console2.log("n+1 reversal check passed: the Safe can downgrade (and re-upgrade) under the live threshold");
    }

    /// @notice Signer-side integrity check for a CI-authored upgrade
    /// artifact, run LOCALLY against a live fork before signing. Deliberately
    /// NOT in the run-script dispatcher: it takes a local path and runs on
    /// the signer's machine.
    /// @param jsonPath Filesystem path to the downloaded Tx Builder JSON.
    function verify(string calldata jsonPath) external view {
        address safeAddr = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        IGnosisSafe safe = IGnosisSafe(safeAddr);
        LibBeaconInvariants.assertProdBeaconsOwnedByChainSafe(block.chainid);

        SafeTx[] memory expected = authorBundle();
        LibSafeOps.assertParsedTxsMatch(expected, jsonPath);

        uint256 nonce = safe.nonce();
        console2.log("Artifact verified against live state.");
        console2.log(
            "Bundle MultiSend SafeTxHash:", vm.toString(LibSafeOps.computeMultiSendSafeTxHash(safe, expected, nonce))
        );
        console2.log("Nonce:", nonce);
    }
}

/// @dev Local mirror of OZ `UpgradeableBeacon.upgradeTo` — rain-vats ships
/// no interface carrying it and OZ's contract is not an interface.
interface IUpgradeableBeaconLike {
    function upgradeTo(address newImplementation) external;
}
