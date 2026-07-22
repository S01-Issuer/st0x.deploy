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
import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
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
/// match the pinned `LibProdDeployV4.STOX_RECEIPT_VAULT_CODEHASH_0_1_1`.
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
///   1. Points all three V1 production beacons (receipt, receipt vault,
///      wrapped token vault) at their V4 implementations
///      (`LibProdDeployV4.STOX_RECEIPT_0_1_1` /
///      `STOX_RECEIPT_VAULT_0_1_1` / `STOX_WRAPPED_TOKEN_VAULT_0_1_1`).
///   2. Calls
///      `setAuthorizer(LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE)`
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
///    The V4 impl at `STOX_RECEIPT_VAULT_0_1_1` is deployed on Base with the
///    pinned codehash, so the impl-side pre-flight passes; the clone-pin check
///    fails red today because `STOX_PROD_AUTHORISER_V4_CLONE` is still
///    `address(0)` — the forcing function blocking the upgrade until the clone
///    is deployed and pinned.
/// 2. **Build** — a multi-tx bundle: one `upgradeTo(V4 impl)` call per V1
///    production beacon (receipt, receipt vault, wrapped token vault), plus
///    one `setAuthorizer(V4 clone)` call per production receipt vault
///    (count = `LibTokenInvariants.productionReceiptVaults().length`,
///    20 as of 2026-06-26; the bundle grows in lockstep as new vaults are
///    added to the lib). Compute the canonical `SafeTxHash` against the live
///    nonce for the first beacon-upgrade tx for signer cross-check.
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
    /// @notice The receipt-vault beacon — kept as a named constant because
    /// several tests exercise its pre-flight paths specifically.
    address internal constant BEACON = LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1;

    /// @notice The receipt-vault V1 implementation (rollback target).
    address internal constant V1_IMPL = LibProdDeployV1.STOX_RECEIPT_VAULT_IMPLEMENTATION;

    /// @notice The receipt-vault V4 implementation — the audited `0.1.1`
    /// build, deployed on Base at this pinned address.
    address internal constant V4_IMPL = LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_1;

    /// @notice The three V1 production beacons the bundle upgrades, in
    /// receipt → receipt-vault → wrapped-token-vault order (same order as
    /// `MigrateBeaconOwners`). Every live production token proxies through
    /// these three, so upgrading them together keeps the receipt (ERC-1155),
    /// receipt vault (ERC-20) and wrapped vault (ERC-4626) implementations
    /// in lock-step — the receipt-vault V4 impl assumes the V4 receipt
    /// behaviour and vice versa.
    function beacons() internal pure returns (address[3] memory list) {
        list[0] = LibProdDeployV1.STOX_RECEIPT_BEACON_V1;
        list[1] = LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1;
        list[2] = LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_V1;
    }

    /// @notice Each beacon's V1 implementation, index-aligned with
    /// `beacons()`. Pre-flight expectation and the n+1 rollback target.
    function v1Impls() internal pure returns (address[3] memory list) {
        list[0] = LibProdDeployV1.STOX_RECEIPT_IMPLEMENTATION;
        list[1] = LibProdDeployV1.STOX_RECEIPT_VAULT_IMPLEMENTATION;
        list[2] = LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION;
    }

    /// @notice Each beacon's V4 implementation, index-aligned with
    /// `beacons()` — the audited `0.1.1` builds pinned in the generated
    /// deploy lib.
    function v4Impls() internal pure returns (address[3] memory list) {
        list[0] = LibProdDeployV4.STOX_RECEIPT_0_1_1;
        list[1] = LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_1;
        list[2] = LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_0_1_1;
    }

    /// @notice Each V4 implementation's pinned codehash, index-aligned with
    /// `v4Impls()`.
    function v4Codehashes() internal pure returns (bytes32[3] memory list) {
        list[0] = LibProdDeployV4.STOX_RECEIPT_CODEHASH_0_1_1;
        list[1] = LibProdDeployV4.STOX_RECEIPT_VAULT_CODEHASH_0_1_1;
        list[2] = LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_CODEHASH_0_1_1;
    }

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
        _preflightBeaconsAndImpls();
        _preflightClone();

        // --- Build the bundle --------------------------------------------

        // Three beacon upgrades (receipt, receipt vault, wrapped token
        // vault) + one setAuthorizer per production receipt vault.
        SafeTx[] memory txs = _buildBundle(vaults);

        // Capture the nonce before any simulation. `simulateExternalCall`
        // does not advance the nonce, so the hash binds to the current Safe
        // state.
        uint256 nonce = safe.nonce();
        bytes32 beaconSafeTxHash = LibSafeOps.computeSafeTxHashViaSafe(safe, txs[0], nonce);

        // --- Simulate -----------------------------------------------------

        for (uint256 i = 0; i < txs.length; i++) {
            LibSafeOps.simulateExternalCall(safe, txs[i].to, txs[i].data);
        }

        // --- Post-state ---------------------------------------------------

        _assertPostState(safe, vaults);

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

        address[3] memory beaconList = beacons();
        address[3] memory v1ImplList = v1Impls();
        for (uint256 i = 0; i < beaconList.length; i++) {
            bytes memory inverseData = abi.encodeCall(IUpgradeableBeacon.upgradeTo, (v1ImplList[i]));
            LibSafeOps.simulateNPlus1(
                safe, beaconList[i], inverseData, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD
            );
            require(
                IBeacon(beaconList[i]).implementation() == v1ImplList[i],
                "UpgradeReceiptVaultsToV4: n+1 did not roll beacon back to V1 impl"
            );
        }
        console2.log("n+1 reversibility check passed: all three beacons rolled back to V1 impls");
    }

    /// @notice Pre-flight: every V1 production beacon is Safe-owned and
    /// still at its V1 implementation, and every V4 implementation is
    /// deployed with its audited codehash. The receipt-vault entry is
    /// checked first (via the scalar constants) so its typed-error paths
    /// stay deterministic for the test suite.
    function _preflightBeaconsAndImpls() internal view {
        address[3] memory beaconList = beacons();
        address[3] memory v1ImplList = v1Impls();
        address[3] memory v4ImplList = v4Impls();
        bytes32[3] memory v4CodehashList = v4Codehashes();
        if (V4_IMPL.code.length == 0) {
            revert V4ImplementationNotDeployed(V4_IMPL);
        }
        bytes32 v4Codehash = V4_IMPL.codehash;
        if (v4Codehash != LibProdDeployV4.STOX_RECEIPT_VAULT_CODEHASH_0_1_1) {
            revert V4CodehashMismatch(V4_IMPL, LibProdDeployV4.STOX_RECEIPT_VAULT_CODEHASH_0_1_1, v4Codehash);
        }
        for (uint256 i = 0; i < beaconList.length; i++) {
            LibBeaconInvariants.assertBeaconInvariants(
                beaconList[i], LibBeaconInvariants.PROD_BEACON_OWNER, v1ImplList[i]
            );
            if (v4ImplList[i].code.length == 0) {
                revert V4ImplementationNotDeployed(v4ImplList[i]);
            }
            bytes32 actualCodehash = v4ImplList[i].codehash;
            if (actualCodehash != v4CodehashList[i]) {
                revert V4CodehashMismatch(v4ImplList[i], v4CodehashList[i], actualCodehash);
            }
        }
    }

    /// @notice Pre-flight: the V4 authoriser clone is pinned, deployed, its
    /// codehash matches the EIP-1167 runtime with the V4 impl embedded, and
    /// the grant map matches the lib.
    function _preflightClone() internal view {
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

        // Verify all seven auto-granted `_ADMIN` roles hold on the Safe —
        // including the two V4-only corporate-action admins
        // (`SCHEDULE_/CANCEL_CORPORATE_ACTION_ADMIN`) that `expectedGrants()`
        // doesn't carry. Without them the swapped clone can't admin corporate
        // actions, so this is the enforcement point that must reject a clone
        // deployed missing them.
        bytes32[7] memory adminRoles = [
            keccak256("CERTIFY_ADMIN"),
            keccak256("CONFISCATE_RECEIPT_ADMIN"),
            keccak256("CONFISCATE_SHARES_ADMIN"),
            keccak256("DEPOSIT_ADMIN"),
            keccak256("WITHDRAW_ADMIN"),
            keccak256("SCHEDULE_CORPORATE_ACTION_ADMIN"),
            keccak256("CANCEL_CORPORATE_ACTION_ADMIN")
        ];
        address ownerSafe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
        for (uint256 i = 0; i < adminRoles.length; i++) {
            if (!cloneAcl.hasRole(adminRoles[i], ownerSafe)) {
                revert V4AuthoriserCloneExpectedGrantMissing(V4_AUTHORISER_CLONE, adminRoles[i], ownerSafe);
            }
        }
    }

    /// @notice Build the bundle: one `upgradeTo(V4 impl)` per V1 beacon
    /// followed by one `setAuthorizer(V4 clone)` per production vault.
    /// @param vaults The production receipt vaults the swap targets.
    /// @return txs The bundle transactions in execution order.
    function _buildBundle(address[] memory vaults) internal pure returns (SafeTx[] memory txs) {
        address[3] memory beaconList = beacons();
        address[3] memory v4ImplList = v4Impls();
        txs = new SafeTx[](beaconList.length + vaults.length);
        for (uint256 i = 0; i < beaconList.length; i++) {
            txs[i] = SafeTx({
                to: beaconList[i],
                value: 0,
                data: abi.encodeCall(IUpgradeableBeacon.upgradeTo, (v4ImplList[i])),
                operation: 0
            });
        }
        bytes memory setAuthoriserData =
            abi.encodeCall(OffchainAssetReceiptVaultLike.setAuthorizer, (IAuthorizeV1(V4_AUTHORISER_CLONE)));
        for (uint256 i = 0; i < vaults.length; i++) {
            txs[beaconList.length + i] = SafeTx({to: vaults[i], value: 0, data: setAuthoriserData, operation: 0});
        }
    }

    /// @notice Post-state assertions after the upgrade + swap simulate: all
    /// three beacons are at V4 and Safe-owned, every production receipt vault
    /// reports the V4 clone as its authoriser, and the Safe identity +
    /// threshold are unchanged. Split from `run()` so tests can drive it
    /// against a deliberately-malformed post-state (e.g. an un-swapped vault)
    /// and assert the `VaultAuthoriserMismatchPostUpgrade` guard fires.
    /// @param safe The ST0x token-owner Safe.
    /// @param vaults The production receipt vaults the swap targets.
    function _assertPostState(IGnosisSafe safe, address[] memory vaults) internal view {
        // All three beacons now at their V4 implementations, still
        // Safe-owned.
        address[3] memory beaconList = beacons();
        address[3] memory v4ImplList = v4Impls();
        for (uint256 i = 0; i < beaconList.length; i++) {
            LibBeaconInvariants.assertBeaconInvariants(
                beaconList[i], LibBeaconInvariants.PROD_BEACON_OWNER, v4ImplList[i]
            );
        }
        // Every production receipt vault now authorised by the V4 clone.
        for (uint256 i = 0; i < vaults.length; i++) {
            address actual = address(IAuthorizableV1(vaults[i]).authorizer());
            if (actual != V4_AUTHORISER_CLONE) {
                revert VaultAuthoriserMismatchPostUpgrade(vaults[i], V4_AUTHORISER_CLONE, actual);
            }
        }
        // Safe identity + threshold unchanged. (The explicit per-vault
        // V4-clone loop above is deliberately STRICTER than the
        // migration-window authoriser leg in `LibInvariants.assertAll` —
        // this is the post-state of the swap itself, so only the V4 clone
        // is acceptable regardless of the window. The Safe-side legs are
        // asserted piecemeal to avoid re-running the token-side legs the
        // loop above already covers.)
        LibSafeInvariants.assertImmutableInvariants(safe);
        LibSafeInvariants.assertThreshold(safe, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD);
    }
}

/// @dev Local mirror of the receipt-vault `setAuthorizer(IAuthorizeV1)`
/// selector. Avoids dragging the full `OffchainAssetReceiptVault` storage
/// inheritance into this script just to encode one selector.
interface OffchainAssetReceiptVaultLike {
    function setAuthorizer(IAuthorizeV1 newAuthorizer) external;
}
