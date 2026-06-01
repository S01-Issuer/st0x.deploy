// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";

import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {IAuthorizableV1} from "rain-vats-0.1.6/src/interface/IAuthorizableV1.sol";
import {IAuthorizeV1} from "rain-vats-0.1.6/src/interface/IAuthorizeV1.sol";
import {IGnosisSafe} from "../src/interface/IGnosisSafe.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibProdDeployV1} from "../src/lib/LibProdDeployV1.sol";
import {LibProdDeployV4} from "../src/lib/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibTokenInvariants} from "../src/lib/LibTokenInvariants.sol";
import {LibBeaconInvariants} from "../src/lib/LibBeaconInvariants.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibSafeOps, SafeTx, IUpgradeableBeacon} from "../src/lib/LibSafeOps.sol";

/// @notice The V4 receipt vault implementation has no runtime code at its
/// (post-rebuild) Zoltu address. The upgrade cannot be authored until the V4
/// implementation is deployed on-chain.
/// @param implementation The V4 implementation address that has no code.
error V4ImplementationNotDeployed(address implementation);

/// @notice The V4 receipt vault implementation's runtime codehash does not
/// match the pinned `LibProdDeployV4.STOX_RECEIPT_VAULT_CODEHASH_RAIN_VATS_0_1_6`.
/// Signals the on-chain bytecode is not the audited V4 build.
/// @param implementation The implementation address inspected.
/// @param expected The pinned V4 codehash.
/// @param actual The codehash observed on-chain.
error V4CodehashMismatch(address implementation, bytes32 expected, bytes32 actual);

/// @notice The V4 authoriser clone constant in `LibAuthoriserInvariants` is still
/// the `address(0)` placeholder. The clone must be deployed (and its address
/// dropped into the lib) before the upgrade can be authored.
error V4AuthoriserCloneNotPinned();

/// @notice The V4 authoriser clone address is pinned but has no runtime code.
/// @param clone The clone address that has no code.
error V4AuthoriserCloneNotDeployed(address clone);

/// @notice The V4 authoriser clone's runtime codehash does not match the
/// pinned `LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH` — the
/// clone has been etched over, or the EIP-1167 runtime does not embed the
/// pinned V4 impl address.
/// @param clone The clone address inspected.
/// @param expected The pinned clone codehash.
/// @param actual The codehash observed on-chain.
error V4AuthoriserCloneCodehashMismatch(address clone, bytes32 expected, bytes32 actual);

/// @notice The V4 authoriser clone is missing one of the role grants pinned
/// in `LibAuthoriserInvariants.expectedGrants()`. The clone's initialization +
/// grant-mirror must complete before the upgrade can be authored.
/// @param clone The clone address inspected.
/// @param role The missing role.
/// @param grantee The grantee that should hold the role.
error V4AuthoriserCloneExpectedGrantMissing(address clone, bytes32 role, address grantee);

/// @notice A production receipt vault's `authorizer()` is not the V4 clone
/// after the upgrade simulates. The `setAuthorizer` bundle item for this
/// vault failed to take effect.
/// @param vault The receipt vault inspected.
/// @param expected The pinned V4 clone address.
/// @param actual The address returned by `authorizer()`.
error VaultAuthoriserMismatchPostUpgrade(address vault, address expected, address actual);

/// @title UpgradeReceiptVaultsToV4
/// @notice **PENDING.** Forge script that authors the receipt-vault V4
/// upgrade plus the authoriser swap onto the corporate-action-aware V4
/// clone. Dispatch via `Actions → run-script` with
/// `script = 20260623-upgrade-receipt-vaults-to-v4` and `sig = run()` once
/// the V4 authoriser clone is pinned in `LibProdDeployV4`
/// (`STOX_PROD_AUTHORISER_V4_CLONE` non-zero) and all 13 grants are
/// mirrored onto it. The ST0x token-owner Safe signs a single bundle
/// that:
///
///   1. Points the receipt-vault beacon at the V4 implementation
///      (`LibProdDeployV4.STOX_RECEIPT_VAULT_RAIN_VATS_0_1_6`).
///   2. Calls `setAuthorizer(LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE)`
///      on every production receipt vault.
///
/// After execution every live receipt vault routes corporate-action selectors
/// into the V4 facet via fallback delegatecall AND is gated by the V4 authoriser
/// clone whose role-grant map matches `LibAuthoriserInvariants.expectedGrants()`.
///
/// This is a Safe-routed operation (the beacon is Safe-owned post-#196 and every
/// vault is Safe-owned by construction), so the script emits a Safe Tx Builder
/// JSON artifact for signer review + execution via the Safe UI.
///
/// @dev Flow:
/// 1. **Pre-flight** —
///    - `assertAll(safe)` (Safe is in its current expected state),
///    - `assertBeaconInvariants(beacon, safe, V1 impl)` (beacon Safe-owned, V1),
///    - the V4 impl is deployed with the pinned codehash,
///    - the V4 authoriser clone is pinned (non-zero), deployed, has the pinned
///      EIP-1167 codehash, and holds every `LibAuthoriserInvariants.expectedGrants()`
///      pair.
///    Every check fails red today because the V4 pointers and the clone
///    address are deliberate placeholders — the forcing function blocking the
///    upgrade until the patched rain.vats tag + clone deploy land.
/// 2. **Build** — a multi-tx bundle: one `upgradeTo(V4 impl)` call on the
///    beacon, plus one `setAuthorizer(V4 clone)` call per production receipt
///    vault (count = `LibTokenInvariants.productionReceiptVaults().length`,
///    20 as of 2026-06-26; the bundle grows in lockstep as new vaults are
///    added to the lib). Compute the canonical `SafeTxHash` against the live
///    nonce for the beacon-upgrade tx for signer cross-check.
/// 3. **Simulate** — prank-route each bundle item as the Safe so post-state
///    assertions reflect the executed state.
/// 4. **Post-state** —
///    - `assertBeaconInvariants(beacon, safe, V4 impl)` (beacon at V4, still
///      Safe-owned),
///    - every production receipt vault's `authorizer()` is the V4 clone,
///    - Safe identity / config + threshold unchanged.
/// 5. **Artifact** — emit the Tx Builder JSON to `out/v4-upgrade.json`, frame
///    it in the console log, print the `SafeTxHash` of the beacon-upgrade tx.
/// 6. **n+1 reversibility** — `simulateNPlus1` proves the Safe can roll the
///    beacon back to V1 under the live threshold (and that the threshold gate
///    rejects undersigned attempts). The `setAuthorizer` reversibility is
///    intrinsic — every vault is Safe-owned so the Safe can re-issue
///    `setAuthorizer(old clone)` symmetrically.
contract UpgradeReceiptVaultsToV4 is Script {
    /// @notice The receipt-vault beacon whose implementation is upgraded.
    address internal constant BEACON = LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1;

    /// @notice The V1 implementation the beacon points at before the upgrade,
    /// and the rollback target for the n+1 reversibility inverse op.
    address internal constant V1_IMPL = LibProdDeployV1.STOX_RECEIPT_VAULT_IMPLEMENTATION;

    /// @notice The V4 implementation the beacon is upgraded to. Placeholder
    /// until the patched rain.vats tag is propagated.
    address internal constant V4_IMPL = LibProdDeployV4.STOX_RECEIPT_VAULT_RAIN_VATS_0_1_6;

    /// @notice The V4 authoriser clone that every production receipt vault is
    /// rewired onto. Placeholder until the clone is deployed.
    address internal constant V4_AUTHORISER_CLONE = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE;

    /// @notice Human-readable name embedded in the emitted Tx Builder JSON's
    /// `meta.name`. Visible to signers in the Safe Tx Builder UI.
    string internal constant BUNDLE_NAME = "ST0x receipt vault V4 upgrade + authoriser swap";

    /// @notice Output path (relative to the project root) for the Tx Builder
    /// JSON artifact.
    string internal constant ARTIFACT_PATH = "out/v4-upgrade.json";

    /// @notice Dry-run the V4 upgrade + authoriser swap: pre-flight invariants,
    /// simulate the beacon upgrade + every `setAuthorizer`, assert the
    /// post-state, emit the Tx Builder JSON, log the SafeTxHash for the
    /// beacon-upgrade tx, and prove n+1 reversibility back to V1. Does not
    /// broadcast — execution happens via the Safe UI using the emitted
    /// artifact.
    function run() external {
        IGnosisSafe safe = IGnosisSafe(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
        address[] memory vaults = LibTokenInvariants.productionReceiptVaults();

        // --- Pre-flight ---------------------------------------------------

        // Safe identity / config + token-side uniformity.
        LibSafeInvariants.assertAll(safe);
        // Beacon is Safe-owned and still at V1.
        LibBeaconInvariants.assertBeaconInvariants(BEACON, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE, V1_IMPL);

        // V4 implementation pinned, deployed, audited codehash.
        if (V4_IMPL.code.length == 0) {
            revert V4ImplementationNotDeployed(V4_IMPL);
        }
        bytes32 v4Codehash = V4_IMPL.codehash;
        if (v4Codehash != LibProdDeployV4.STOX_RECEIPT_VAULT_CODEHASH_RAIN_VATS_0_1_6) {
            revert V4CodehashMismatch(V4_IMPL, LibProdDeployV4.STOX_RECEIPT_VAULT_CODEHASH_RAIN_VATS_0_1_6, v4Codehash);
        }

        // V4 authoriser clone pinned, deployed, codehash matches EIP-1167
        // runtime with V4 impl embedded, and the grant map matches the lib.
        if (V4_AUTHORISER_CLONE == address(0)) {
            revert V4AuthoriserCloneNotPinned();
        }
        if (V4_AUTHORISER_CLONE.code.length == 0) {
            revert V4AuthoriserCloneNotDeployed(V4_AUTHORISER_CLONE);
        }
        bytes32 cloneCodehash = V4_AUTHORISER_CLONE.codehash;
        if (cloneCodehash != LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH) {
            revert V4AuthoriserCloneCodehashMismatch(
                V4_AUTHORISER_CLONE, LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH, cloneCodehash
            );
        }
        IAccessControl cloneAcl = IAccessControl(V4_AUTHORISER_CLONE);
        RoleGrant[] memory expected = LibAuthoriserInvariants.expectedGrants();
        for (uint256 i = 0; i < expected.length; i++) {
            if (!cloneAcl.hasRole(expected[i].role, expected[i].grantee)) {
                revert V4AuthoriserCloneExpectedGrantMissing(V4_AUTHORISER_CLONE, expected[i].role, expected[i].grantee);
            }
        }

        // --- Build the bundle --------------------------------------------

        // One beacon upgrade + one setAuthorizer per production receipt vault.
        SafeTx[] memory txs = new SafeTx[](1 + vaults.length);
        bytes memory beaconData = abi.encodeCall(IUpgradeableBeacon.upgradeTo, (V4_IMPL));
        txs[0] = SafeTx({to: BEACON, value: 0, data: beaconData, operation: 0});
        bytes memory setAuthoriserData =
            abi.encodeCall(OffchainAssetReceiptVaultLike.setAuthorizer, (IAuthorizeV1(V4_AUTHORISER_CLONE)));
        for (uint256 i = 0; i < vaults.length; i++) {
            txs[i + 1] = SafeTx({to: vaults[i], value: 0, data: setAuthoriserData, operation: 0});
        }

        // Capture the nonce before any simulation. `simulateExternalCall`
        // does not advance the nonce, so the hash binds to the current Safe
        // state.
        uint256 nonce = safe.nonce();
        bytes32 beaconSafeTxHash = LibSafeOps.computeSafeTxHashViaSafe(safe, txs[0], nonce);

        // --- Simulate -----------------------------------------------------

        LibSafeOps.simulateExternalCall(safe, BEACON, beaconData);
        for (uint256 i = 0; i < vaults.length; i++) {
            LibSafeOps.simulateExternalCall(safe, vaults[i], setAuthoriserData);
        }

        // --- Post-state ---------------------------------------------------

        // Beacon now at V4, still Safe-owned.
        LibBeaconInvariants.assertBeaconInvariants(BEACON, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE, V4_IMPL);
        // Every production receipt vault now authorised by the V4 clone.
        for (uint256 i = 0; i < vaults.length; i++) {
            address actual = address(IAuthorizableV1(vaults[i]).authorizer());
            if (actual != V4_AUTHORISER_CLONE) {
                revert VaultAuthoriserMismatchPostUpgrade(vaults[i], V4_AUTHORISER_CLONE, actual);
            }
        }
        // Safe identity + threshold unchanged. (We don't run `assertAll`
        // here because its `assertUniformAuthoriser` leg pins the *old*
        // authoriser via `LibTokenInvariants.PROD_RECEIPT_VAULT_AUTHORISER`,
        // which the swap legitimately invalidates; the post-swap uniform
        // authoriser pin against the V4 clone is the job of the V4 prod-
        // state pin in the next PR up the stack.)
        LibSafeInvariants.assertImmutableInvariants(safe);
        LibSafeInvariants.assertThreshold(safe, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD);

        // --- Artifact -----------------------------------------------------

        string memory json = LibSafeOps.emitTxBuilderJson(address(safe), block.chainid, BUNDLE_NAME, txs);
        vm.writeFile(ARTIFACT_PATH, json);

        console2.log("==== TX BUILDER JSON BEGIN ====");
        console2.log(json);
        console2.log("==== TX BUILDER JSON END ====");
        console2.log("Beacon-upgrade SafeTxHash:", vm.toString(beaconSafeTxHash));
        console2.log("Nonce:", nonce);
        console2.log("Bundle item count:", txs.length);

        // --- n+1 reversibility -------------------------------------------

        bytes memory inverseData = abi.encodeCall(IUpgradeableBeacon.upgradeTo, (V1_IMPL));
        LibSafeOps.simulateNPlus1(safe, BEACON, inverseData, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD);
        require(
            IBeacon(BEACON).implementation() == V1_IMPL,
            "UpgradeReceiptVaultsToV4: n+1 did not roll beacon back to V1 impl"
        );
        console2.log("n+1 reversibility check passed: beacon rolled back to V1 impl");
    }
}

/// @dev Local mirror of the receipt-vault `setAuthorizer(IAuthorizeV1)`
/// selector. Avoids dragging the full `OffchainAssetReceiptVault` storage
/// inheritance into this script just to encode one selector.
interface OffchainAssetReceiptVaultLike {
    function setAuthorizer(IAuthorizeV1 newAuthorizer) external;
}
