// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";

import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {IGnosisSafe} from "../src/interface/IGnosisSafe.sol";
import {LibProdDeployV1} from "../src/lib/LibProdDeployV1.sol";
import {LibProdDeployV3} from "../src/lib/LibProdDeployV3.sol";
import {LibProdSafes} from "../src/lib/LibProdSafes.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibSafeOps, SafeTx, IUpgradeableBeacon} from "../src/lib/LibSafeOps.sol";

/// @notice The V3 receipt vault implementation has no runtime code at its
/// deterministic Zoltu address. The upgrade cannot be authored until the V3
/// implementation is deployed on-chain (operational step 1).
/// @param implementation The V3 implementation address that has no code.
error V3ImplementationNotDeployed(address implementation);

/// @notice The V3 receipt vault implementation's runtime codehash does not
/// match the pinned `LibProdDeployV3.STOX_RECEIPT_VAULT_CODEHASH`. Signals the
/// on-chain bytecode is not the audited V3 build.
/// @param implementation The implementation address inspected.
/// @param expected The pinned V3 codehash.
/// @param actual The codehash observed on-chain.
error V3CodehashMismatch(address implementation, bytes32 expected, bytes32 actual);

/// @title UpgradeReceiptVaultToV3
/// @notice Forge script that authors the receipt vault beacon's upgrade to the
/// V3 implementation (corporate actions). The ST0x token-owner Safe calls
/// `upgradeTo(LibProdDeployV3.STOX_RECEIPT_VAULT)` on
/// `LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1`; after execution every live
/// receipt vault routes corporate-action selectors into the V3 facet via
/// fallback delegatecall.
///
/// This is a Safe-routed operation (the beacon is Safe-owned once the
/// beacon-ownership migration has executed), so the script emits a Safe Tx
/// Builder JSON artifact for signer review + execution via the Safe UI, the
/// same flow as the threshold migration.
///
/// @dev Flow:
/// 1. **Pre-flight** — `assertAll(safe)` (the Safe is in its current expected
///    state), `assertBeaconInvariants(beacon, safe, V1 impl)` (the beacon is
///    Safe-owned and still at the V1 implementation), and a require that the
///    V3 implementation is deployed with the pinned codehash.
/// 2. **Build** — the `upgradeTo(V3 impl)` Safe transaction; compute its
///    canonical `SafeTxHash` against the live nonce.
/// 3. **Simulate** — `simulateExternalCall` prank-routes the upgrade as the
///    Safe so the post-state assertions reflect the executed state.
/// 4. **Post-state** — `assertBeaconInvariants(beacon, safe, V3 impl)` (the
///    beacon now points at V3, still Safe-owned) and `assertAll(safe)` (the
///    Safe itself is unchanged by the upgrade).
/// 5. **Artifact** — emit the Tx Builder JSON to `out/v3-upgrade.json`, frame
///    it in the console log, and print the `SafeTxHash`.
/// 6. **n+1 reversibility** — `simulateNPlus1` with the inverse
///    `upgradeTo(V1 impl)` proves the Safe can roll the beacon back to V1
///    under the live threshold (and that the threshold gate rejects
///    undersigned attempts).
contract UpgradeReceiptVaultToV3 is Script {
    /// @notice The receipt vault beacon whose implementation is upgraded.
    address internal constant BEACON = LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1;

    /// @notice The V1 implementation the beacon points at before the upgrade,
    /// and the rollback target for the n+1 reversibility inverse op.
    address internal constant V1_IMPL = LibProdDeployV1.STOX_RECEIPT_VAULT_IMPLEMENTATION;

    /// @notice The V3 implementation the beacon is upgraded to.
    address internal constant V3_IMPL = LibProdDeployV3.STOX_RECEIPT_VAULT;

    /// @notice Human-readable name embedded in the emitted Tx Builder JSON's
    /// `meta.name`. Visible to signers in the Safe Tx Builder UI.
    string internal constant BUNDLE_NAME = "ST0x receipt vault V3 upgrade";

    /// @notice Output path (relative to the project root) for the Tx Builder
    /// JSON artifact.
    string internal constant ARTIFACT_PATH = "out/v3-upgrade.json";

    /// @notice Dry-run the receipt vault V3 upgrade: pre-flight invariants,
    /// simulate the `upgradeTo`, assert the post-state, emit the Tx Builder
    /// JSON, log the SafeTxHash, and prove n+1 reversibility back to V1. Does
    /// not broadcast — execution happens via the Safe UI using the emitted
    /// artifact.
    function run() external {
        IGnosisSafe safe = IGnosisSafe(LibProdSafes.STOX_TOKEN_OWNER_SAFE);

        // Pre-flight. The Safe is in its current expected state, the beacon is
        // Safe-owned (the beacon-ownership migration has landed) and still at
        // the V1 implementation, and the V3 implementation is deployed with
        // the audited codehash.
        LibSafeInvariants.assertAll(safe);
        LibSafeInvariants.assertBeaconInvariants(BEACON, LibProdSafes.STOX_TOKEN_OWNER_SAFE, V1_IMPL);
        if (V3_IMPL.code.length == 0) {
            revert V3ImplementationNotDeployed(V3_IMPL);
        }
        bytes32 v3Codehash = V3_IMPL.codehash;
        if (v3Codehash != LibProdDeployV3.STOX_RECEIPT_VAULT_CODEHASH) {
            revert V3CodehashMismatch(V3_IMPL, LibProdDeployV3.STOX_RECEIPT_VAULT_CODEHASH, v3Codehash);
        }

        // Build the single-tx bundle: a Safe call to the beacon's
        // `upgradeTo(V3 impl)`.
        bytes memory data = abi.encodeCall(IUpgradeableBeacon.upgradeTo, (V3_IMPL));
        SafeTx memory txn = SafeTx({to: BEACON, value: 0, data: data, operation: 0});

        // Capture the nonce before any simulation. `simulateExternalCall`
        // does not advance the nonce, so the hash binds to the current Safe
        // state.
        uint256 nonce = safe.nonce();
        bytes32 safeTxHash = LibSafeOps.computeSafeTxHashViaSafe(safe, txn, nonce);

        // Simulate the upgrade as the Safe, then assert the post-state. The
        // beacon now points at the V3 implementation and is still Safe-owned;
        // the Safe itself is unchanged by the upgrade.
        LibSafeOps.simulateExternalCall(safe, BEACON, data);
        LibSafeInvariants.assertBeaconInvariants(BEACON, LibProdSafes.STOX_TOKEN_OWNER_SAFE, V3_IMPL);
        LibSafeInvariants.assertAll(safe);

        // Emit the Tx Builder JSON artifact and write it under `out/`.
        SafeTx[] memory txs = new SafeTx[](1);
        txs[0] = txn;
        string memory json = LibSafeOps.emitTxBuilderJson(address(safe), block.chainid, BUNDLE_NAME, txs);
        vm.writeFile(ARTIFACT_PATH, json);

        // Log the artifact with explicit BEGIN/END markers so CI can grep the
        // bundle from the run log even after pretty-printing.
        console2.log("==== TX BUILDER JSON BEGIN ====");
        console2.log(json);
        console2.log("==== TX BUILDER JSON END ====");
        console2.log("SafeTxHash:", vm.toString(safeTxHash));
        console2.log("Nonce:", nonce);

        // n+1 reversibility: prove the Safe can roll the beacon back to the V1
        // implementation under the live threshold, and that the threshold gate
        // rejects undersigned attempts (GS020). The inverse op is
        // `upgradeTo(V1 impl)`. Sequenced after the JSON emission so the
        // artifact reflects the forward upgrade, not the reversal; the
        // reversal exists only as a fork-local simulation.
        bytes memory inverseData = abi.encodeCall(IUpgradeableBeacon.upgradeTo, (V1_IMPL));
        LibSafeOps.simulateNPlus1(safe, BEACON, inverseData, LibProdSafes.STOX_TOKEN_OWNER_SAFE_THRESHOLD);
        // Confirm the reversal actually landed: the beacon is back at V1.
        require(
            IBeacon(BEACON).implementation() == V1_IMPL, "UpgradeReceiptVaultToV3: n+1 did not roll back to V1 impl"
        );
        console2.log("n+1 reversibility check passed: beacon rolled back to V1 impl");
    }
}
