// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";
import {Vm} from "forge-std-1.16.1/src/Vm.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";

import {IGnosisSafe} from "../src/interface/IGnosisSafe.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibSafeOps, SafeTx} from "../src/lib/LibSafeOps.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibProdDeployV4} from "../src/lib/LibProdDeployV4.sol";
import {ICloneableFactoryV2} from "rain-factory-0.1.1/src/interface/ICloneableFactoryV2.sol";
import {LibCloneFactoryDeploy} from "rain-factory-0.1.1/src/lib/LibCloneFactoryDeploy.sol";
import {
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.1.6/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";

/// @notice Pre-flight failed: the pinned V4 authoriser impl in
/// `LibProdDeployV4` has no runtime code at its pinned address. Surfaces
/// the impl address that's missing so the operator knows which Zoltu
/// deploy is still pending.
/// @param impl The expected V4 impl address (the pin in `LibProdDeployV4`).
error V4ImplNotDeployed(address impl);

/// @notice Pre-flight failed: the runtime codehash at the pinned V4 impl
/// address does not match the pinned codehash. Signals either that a
/// non-canonical contract is squatting the address or that the Zoltu
/// deploy emitted different bytecode than the lib expects.
/// @param impl The V4 impl address inspected.
/// @param expected The pinned codehash (`STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CODEHASH_RAIN_VATS_0_1_6`).
/// @param actual The codehash observed at `impl`.
error V4ImplCodehashMismatch(address impl, bytes32 expected, bytes32 actual);

/// @notice Pre-flight failed: the canonical Rain `CloneFactory` at
/// `LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS` has no runtime
/// code on the active fork. The clone-deploy bundle targets this address
/// and would revert in production, so emitting the artifact would be
/// pointless.
/// @param factory The expected canonical CloneFactory address.
error CloneFactoryNotDeployed(address factory);

/// @notice Pre-flight failed: the runtime codehash at the canonical
/// CloneFactory address does not match the pinned
/// `LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_CODEHASH`.
/// @param factory The CloneFactory address inspected.
/// @param expected The pinned codehash.
/// @param actual The codehash observed at `factory`.
error CloneFactoryCodehashMismatch(address factory, bytes32 expected, bytes32 actual);

/// @notice Pre-flight failed (deploy branch only): the simulated clone's
/// runtime codehash does not match the EIP-1167 minimal-proxy runtime
/// computed from the pinned V4 impl literal. Signals either that the
/// emitted clone has been etched over or that the V4 impl pin and the
/// runtime computation drifted apart.
/// @param clone The clone address observed in the `NewClone` event.
/// @param expected The EIP-1167 minimal-proxy runtime codehash computed
/// from the V4 impl literal.
/// @param actual The codehash observed at `clone`.
error CloneCodehashMismatch(address clone, bytes32 expected, bytes32 actual);

/// @notice Pre-flight failed: a role grant that the base authoriser's
/// `initialize` is expected to make automatically against the Safe is
/// missing on the clone. Surfaces the exact role + grantee that broke
/// the invariant.
/// @param clone The clone address inspected.
/// @param role The auto-grant role that should be held.
/// @param grantee The expected grantee (the ST0x token-owner Safe).
error AutoGrantMissing(address clone, bytes32 role, address grantee);

/// @notice Pre-flight failed (deploy branch only): a non-admin grant
/// that this script is supposed to mirror in is already held on a fresh
/// clone, before the mirror bundle has been authored. Either the clone
/// is not fresh or `LibAuthoriserInvariants.expectedGrants()` is wrong
/// about which grants the base `initialize` makes.
/// @param clone The clone address inspected.
/// @param role The non-admin role found to be unexpectedly held.
/// @param grantee The grantee that holds the role.
error UnexpectedAutoGrantHeld(address clone, bytes32 role, address grantee);

/// @notice A previously emitted Tx Builder JSON artifact (parsed via
/// `LibSafeOps.parseTxBuilderJson`) does not match the bundle the live
/// pre-flight would emit. Surfaces the first field that drifts so a
/// signer can pinpoint where the off-chain artifact diverged from the
/// on-chain state at verification time.
/// @param field The name of the field that drifted (e.g. `"chainId"`,
/// `"to"`, `"data"`, `"safeTxHash"`, `"txCount"`).
error VerifyMismatch(string field);

/// @notice `verify()` could not decide which bundle (deploy or grants)
/// the supplied artifact represents from its tx count. The deploy bundle
/// is a single tx; the grants bundle is exactly 6 txs. Any other count
/// is unambiguous drift rather than a future-proofing exercise.
/// @param actualCount The number of transactions in the parsed artifact.
error VerifyUnknownBundleShape(uint256 actualCount);

/// @title DeployV4AuthoriserClone
/// @notice Forge script that authors the V4 authoriser clone deploy +
/// the forward-mirror of the live non-admin role grants onto the new
/// clone, as two separate Safe Tx Builder JSON artifacts ready for the
/// ST0x token-owner Safe to sign and execute.
///
/// Two artifacts because `Clones.clone()` is non-deterministic
/// (nonce-based, no CREATE2 salt) — the clone's address isn't known
/// until the first bundle lands. The pattern is therefore:
///
/// 1. `run()` — authors the clone-deploy bundle (target = the canonical
///    Rain `CloneFactory`, calldata = `clone(v4Impl, abi.encode(Config(Safe)))`).
///    The base `OffchainAssetReceiptVaultAuthorizerV1.initialize` plus
///    the ST0x override grants seven `_ADMIN` roles to the Safe
///    automatically: `CERTIFY_ADMIN`, `CONFISCATE_RECEIPT_ADMIN`,
///    `CONFISCATE_SHARES_ADMIN`, `DEPOSIT_ADMIN`, `WITHDRAW_ADMIN`,
///    `SCHEDULE_CORPORATE_ACTION_ADMIN`, `CANCEL_CORPORATE_ACTION_ADMIN`.
///    No further action is required to put the Safe in admin position;
///    the deploy bundle alone is enough to land the clone.
///
/// 2. After bundle 1 executes on Base, the operator hydrates
///    `LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE` with the literal
///    clone address (separate follow-up PR — the "post-execution pin"
///    pattern), then calls `mirrorGrants(clone)` to author bundle 2.
///
/// 3. `mirrorGrants(clone)` — authors a six-tx bundle that
///    `grantRole(role, grantee)`s the six non-admin entries from
///    `LibAuthoriserInvariants.expectedGrants()` (indices 5..10) onto
///    the clone. After this bundle lands the clone holds all 13 grants
///    enumerated in `expectedGrants()` plus the two extra
///    corporate-action admins, ready for `setAuthorizer` to swap every
///    receipt vault onto it.
///
/// 4. `verify(jsonPath, clone)` — re-runs the relevant pre-flight,
///    parses the artifact, and asserts the parsed bundle matches what
///    the live pre-flight would emit. Used by signers to confirm an
///    artifact wasn't tampered with between authoring and signing. The
///    `clone` argument is ignored when the artifact is the deploy
///    bundle (the deploy bundle is authored before the clone exists);
///    callers pass `address(0)` in that case.
///
/// The two-bundle separation also gives the Safe owners a natural
/// checkpoint between deploying the clone and mirroring grants: the
/// clone's address goes into the lib's constant before grants are
/// authored, so the grants bundle's targets cannot drift away from the
/// actually-deployed clone.
contract DeployV4AuthoriserClone is Script {
    /// @notice Human-readable name embedded in the deploy bundle's
    /// `meta.name`. Visible to signers in the Safe Tx Builder UI.
    string internal constant DEPLOY_BUNDLE_NAME = "ST0x V4 authoriser - deploy clone";

    /// @notice Human-readable name embedded in the grants bundle's
    /// `meta.name`. Visible to signers in the Safe Tx Builder UI.
    string internal constant GRANTS_BUNDLE_NAME = "ST0x V4 authoriser - mirror non-admin grants";

    /// @notice Output path (relative to the project root) for the deploy
    /// bundle JSON artifact.
    string internal constant DEPLOY_ARTIFACT_PATH = "out/v4-authoriser-clone-deploy.json";

    /// @notice Output path (relative to the project root) for the grants
    /// bundle JSON artifact.
    string internal constant GRANTS_ARTIFACT_PATH = "out/v4-authoriser-clone-grants.json";

    /// @notice The deploy bundle's tx count (one — a single
    /// `CloneFactory.clone` call). Used by `verify` as the discriminator
    /// against the grants bundle's tx count.
    uint256 internal constant DEPLOY_TX_COUNT = 1;

    /// @notice The grants bundle's tx count. Six entries — the
    /// non-admin slice (indices 5..10) of
    /// `LibAuthoriserInvariants.expectedGrants()`.
    uint256 internal constant GRANTS_TX_COUNT = 6;

    /// @notice The starting index of the non-admin grant slice inside
    /// `LibAuthoriserInvariants.expectedGrants()`. Indices 0..4 are the
    /// V3-era `_ADMIN` grants which the base `initialize` auto-grants on
    /// the V4 clone (plus the two corporate-action admins the override
    /// adds), so this script never needs to mirror them. Indices 5..10
    /// are the operational grants (`DEPOSIT` / `WITHDRAW` / `CERTIFY` ×
    /// service + Safe) that must be hand-mirrored.
    uint256 internal constant MIRROR_START_INDEX = 5;

    /// @notice Dry-run the V4 authoriser clone deploy: pre-flight every
    /// invariant the bundle will rely on, simulate the clone, assert
    /// the post-state matches the auto-grants the base + override
    /// `initialize` are expected to make, emit the Tx Builder JSON
    /// artifact, and log the canonical SafeTxHash + the predicted clone
    /// address (between BEGIN/END markers so CI can grep them).
    /// @dev Does not broadcast anything — the inner call is gated
    /// behind the Safe's own signature verification in production and
    /// we explicitly simulate via `vm.prank`. The simulated nonce on
    /// the Safe is NOT advanced by `simulateExternalCall` so the
    /// captured `safeTxHash` binds to the live current nonce.
    function run() external {
        IGnosisSafe safe = IGnosisSafe(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);

        // Pre-flight: Safe immutable invariants + pinned owner set +
        // pinned threshold. Reverts with the relevant typed error from
        // `LibSafeInvariants` on first mismatch.
        LibSafeInvariants.assertAll(safe);

        // Pre-flight: V4 impl deployed at the pinned address with the
        // pinned codehash. The clone will EIP-1167-proxy this address;
        // if it isn't there or has the wrong code, the clone would
        // either fail to initialize or initialize against attacker
        // code.
        address v4Impl = LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_RAIN_VATS_0_1_6;
        assertV4ImplDeployed(v4Impl);

        // Pre-flight: the canonical CloneFactory is deployed with the
        // pinned codehash. This is the only target of the bundle, so a
        // missing factory means the bundle would revert in production.
        address factoryAddr = LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS;
        assertCloneFactoryDeployed(factoryAddr);

        // Build the single-tx bundle: target = CloneFactory, calldata =
        // `clone(v4Impl, abi.encode(Config(Safe)))`.
        bytes memory initData =
            abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: address(safe)}));
        SafeTx memory txn = SafeTx({
            to: factoryAddr,
            value: 0,
            data: abi.encodeCall(ICloneableFactoryV2.clone, (v4Impl, initData)),
            operation: 0
        });

        // Capture the nonce before any simulation. `simulateExternalCall`
        // does not advance the nonce, so the hash binds to the current
        // Safe state.
        uint256 nonce = safe.nonce();
        bytes32 safeTxHash = LibSafeOps.computeSafeTxHashViaSafe(safe, txn, nonce);

        // Simulate the inner call via `vm.prank(safe)` -> CloneFactory,
        // recording logs so we can fish the predicted clone address out
        // of the `NewClone` event. The Safe nonce is intentionally NOT
        // advanced by `simulateExternalCall`.
        vm.recordLogs();
        LibSafeOps.simulateExternalCall(safe, factoryAddr, txn.data);
        address predictedClone = extractCloneAddressFromLogs(vm.getRecordedLogs(), factoryAddr, v4Impl);

        // Assert the simulated clone's runtime codehash matches the
        // EIP-1167 minimal-proxy runtime computed from the V4 impl
        // literal. The expected codehash is the same one that
        // `LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH` will
        // eventually pin once the literal is hydrated post-deploy.
        bytes32 expectedCloneCodehash = computeMinimalProxyCodehash(v4Impl);
        assertCloneCodehash(predictedClone, expectedCloneCodehash);

        // Assert the seven auto-grants the base + override `initialize`
        // produce are actually held by the Safe, and that the six
        // non-admin grants this script is about to author are NOT yet
        // held on the fresh clone (so the mirror bundle is genuinely
        // adding new state, not no-oping).
        assertAutoGrantsHeld(predictedClone, address(safe));
        assertNonAdminGrantsAbsent(predictedClone);

        // Emit the Tx Builder JSON artifact and write it under `out/`.
        SafeTx[] memory txs = new SafeTx[](DEPLOY_TX_COUNT);
        txs[0] = txn;
        string memory json = LibSafeOps.emitTxBuilderJson(address(safe), block.chainid, DEPLOY_BUNDLE_NAME, txs);
        vm.writeFile(DEPLOY_ARTIFACT_PATH, json);

        // Log the artifact with explicit BEGIN/END markers so CI can
        // grep the bundle from the run log even when the JSON has been
        // pretty-printed by an intermediate tool. The predicted clone
        // address is logged separately so the operator can hydrate
        // `LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE` with it post-
        // execution.
        console2.log("==== TX BUILDER JSON BEGIN ====");
        console2.log(json);
        console2.log("==== TX BUILDER JSON END ====");
        console2.log("SafeTxHash:", vm.toString(safeTxHash));
        console2.log("Nonce:", nonce);
        console2.log("PredictedClone:", vm.toString(predictedClone));
        console2.log("ExpectedCloneCodehash:", vm.toString(expectedCloneCodehash));
    }

    /// @notice Dry-run the V4 authoriser non-admin grant mirror: pre-
    /// flight the Safe + the supplied clone, build the six-tx grants
    /// bundle, simulate each `grantRole` call via `vm.prank(safe)`,
    /// assert the full 11-entry `expectedGrants()` map plus the two
    /// auto-granted corporate-action admins all hold on the clone post-
    /// state, emit the Tx Builder JSON artifact, and log the canonical
    /// SafeTxHash. The bundle targets the supplied `clone` six times
    /// (one `grantRole` per non-admin entry).
    /// @dev The clone is supplied as an argument because the address is
    /// not deterministic ahead of the first bundle landing on Base;
    /// post-deploy the operator passes the literal in. This script does
    /// not consult `LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE`
    /// because the constant is `address(0)` until the post-execution
    /// hydration PR lands.
    /// @param clone The deployed clone's address (the result of the
    /// `run()` bundle, observed on Base).
    function mirrorGrants(address clone) external {
        IGnosisSafe safe = IGnosisSafe(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);

        // Pre-flight: Safe immutable invariants + pinned owner set +
        // pinned threshold.
        LibSafeInvariants.assertAll(safe);

        // Pre-flight: the clone has code, has the expected EIP-1167
        // codehash for the V4 impl, and already holds the seven auto-
        // grants the base + override `initialize` should have made
        // during deploy. If any of those is missing the deploy bundle
        // either failed or initialised against a different admin.
        address v4Impl = LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_RAIN_VATS_0_1_6;
        bytes32 expectedCloneCodehash = computeMinimalProxyCodehash(v4Impl);
        assertCloneCodehash(clone, expectedCloneCodehash);
        assertAutoGrantsHeld(clone, address(safe));

        // Build the N-tx bundle: one `grantRole(role, grantee)` per
        // non-admin entry in `expectedGrants()` (indices 5..10).
        RoleGrant[] memory allGrants = LibAuthoriserInvariants.expectedGrants();
        SafeTx[] memory txs = new SafeTx[](GRANTS_TX_COUNT);
        for (uint256 i = 0; i < GRANTS_TX_COUNT; i++) {
            RoleGrant memory grant = allGrants[MIRROR_START_INDEX + i];
            txs[i] = SafeTx({
                to: clone,
                value: 0,
                data: abi.encodeCall(IAccessControl.grantRole, (grant.role, grant.grantee)),
                operation: 0
            });
        }

        // Capture the nonce before simulation.
        uint256 nonce = safe.nonce();
        bytes32 safeTxHash = computeBatchSafeTxHash(safe, txs, nonce);

        // Simulate each `grantRole` call via `vm.prank(safe)`. The Safe
        // nonce is intentionally NOT advanced by `simulateExternalCall`.
        for (uint256 i = 0; i < GRANTS_TX_COUNT; i++) {
            LibSafeOps.simulateExternalCall(safe, txs[i].to, txs[i].data);
        }

        // Post-state: the full `expectedGrants()` map holds on the
        // clone. This re-checks the seven auto-grants AND the six just-
        // simulated mirror grants in one sweep, so any drift between
        // the bundle and the lib's invariant surfaces here.
        LibAuthoriserInvariants.assertExpectedGrants(clone);

        // Emit the Tx Builder JSON artifact and write it under `out/`.
        string memory json = LibSafeOps.emitTxBuilderJson(address(safe), block.chainid, GRANTS_BUNDLE_NAME, txs);
        vm.writeFile(GRANTS_ARTIFACT_PATH, json);

        console2.log("==== TX BUILDER JSON BEGIN ====");
        console2.log(json);
        console2.log("==== TX BUILDER JSON END ====");
        console2.log("SafeTxHash:", vm.toString(safeTxHash));
        console2.log("Nonce:", nonce);
        console2.log("Clone:", vm.toString(clone));
    }

    /// @notice Re-runs the relevant pre-flight and asserts that a pre-
    /// emitted Tx Builder JSON at `jsonPath` matches what the live
    /// pre-flight would emit. Discriminates the deploy bundle from the
    /// grants bundle by tx count.
    /// @param jsonPath Filesystem path to the Tx Builder JSON to
    /// verify.
    /// @param clone The deployed clone address. Ignored for the deploy
    /// bundle (pass `address(0)`); required for the grants bundle.
    function verify(string calldata jsonPath, address clone) external view {
        IGnosisSafe safe = IGnosisSafe(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
        LibSafeInvariants.assertAll(safe);

        (uint256 parsedChainId, address parsedTo, SafeTx[] memory parsedTxs) =
            LibSafeOps.parseTxBuilderJson(jsonPath);

        if (parsedChainId != block.chainid) revert VerifyMismatch("chainId");

        if (parsedTxs.length == DEPLOY_TX_COUNT) {
            verifyDeployBundle(safe, parsedTo, parsedTxs);
        } else if (parsedTxs.length == GRANTS_TX_COUNT) {
            verifyGrantsBundle(safe, parsedTo, parsedTxs, clone);
        } else {
            revert VerifyUnknownBundleShape(parsedTxs.length);
        }
    }

    /// @notice Deploy-bundle verify branch. Re-checks the V4 impl pin,
    /// the CloneFactory pin, asserts the parsed tx targets the factory
    /// with the canonical `clone(v4Impl, abi.encode(Config(Safe)))`
    /// calldata, and cross-checks the implied SafeTxHash against the
    /// live Safe's hash builder.
    /// @dev Note `parsedTo` from the artifact is the first tx's `to`
    /// (the canonical CloneFactory address), not the Safe. The first
    /// tx in the deploy bundle does not target the Safe, so the
    /// parsedTo check uses the factory address rather than the Safe.
    /// @param safe The live Safe handle.
    /// @param parsedTo The `transactions[0].to` reported by the parser.
    /// @param parsedTxs The parsed transactions array (length == 1).
    function verifyDeployBundle(IGnosisSafe safe, address parsedTo, SafeTx[] memory parsedTxs) internal view {
        address v4Impl = LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_RAIN_VATS_0_1_6;
        assertV4ImplDeployed(v4Impl);

        address factoryAddr = LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS;
        assertCloneFactoryDeployed(factoryAddr);

        if (parsedTo != factoryAddr) revert VerifyMismatch("to");

        bytes memory initData =
            abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: address(safe)}));
        SafeTx memory expected = SafeTx({
            to: factoryAddr,
            value: 0,
            data: abi.encodeCall(ICloneableFactoryV2.clone, (v4Impl, initData)),
            operation: 0
        });

        if (parsedTxs[0].to != expected.to) revert VerifyMismatch("to");
        if (parsedTxs[0].value != expected.value) revert VerifyMismatch("value");
        if (keccak256(parsedTxs[0].data) != keccak256(expected.data)) revert VerifyMismatch("data");

        bytes32 liveHash = LibSafeOps.computeSafeTxHashViaSafe(safe, expected, safe.nonce());
        bytes32 artifactHash = LibSafeOps.computeSafeTxHashViaSafe(safe, parsedTxs[0], safe.nonce());
        if (liveHash != artifactHash) revert VerifyMismatch("safeTxHash");
    }

    /// @notice Grants-bundle verify branch. Re-checks the clone's
    /// codehash against the EIP-1167 runtime for the V4 impl, asserts
    /// each parsed tx targets the clone with the canonical
    /// `grantRole(role, grantee)` calldata for the matching non-admin
    /// slice of `expectedGrants()`, and cross-checks the implied
    /// per-tx SafeTxHash chain against the live Safe's hash builder.
    /// @param safe The live Safe handle.
    /// @param parsedTo The `transactions[0].to` reported by the parser
    /// — should equal `clone`.
    /// @param parsedTxs The parsed transactions array (length == 6).
    /// @param clone The deployed clone address.
    function verifyGrantsBundle(IGnosisSafe safe, address parsedTo, SafeTx[] memory parsedTxs, address clone)
        internal
        view
    {
        address v4Impl = LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_RAIN_VATS_0_1_6;
        bytes32 expectedCloneCodehash = computeMinimalProxyCodehash(v4Impl);
        assertCloneCodehash(clone, expectedCloneCodehash);

        if (parsedTo != clone) revert VerifyMismatch("to");

        RoleGrant[] memory allGrants = LibAuthoriserInvariants.expectedGrants();
        for (uint256 i = 0; i < GRANTS_TX_COUNT; i++) {
            RoleGrant memory grant = allGrants[MIRROR_START_INDEX + i];
            SafeTx memory expected = SafeTx({
                to: clone,
                value: 0,
                data: abi.encodeCall(IAccessControl.grantRole, (grant.role, grant.grantee)),
                operation: 0
            });
            if (parsedTxs[i].to != expected.to) revert VerifyMismatch("to");
            if (parsedTxs[i].value != expected.value) revert VerifyMismatch("value");
            if (keccak256(parsedTxs[i].data) != keccak256(expected.data)) revert VerifyMismatch("data");
        }

        bytes32 liveHash = computeBatchSafeTxHash(safe, _buildExpectedGrantsTxs(clone), safe.nonce());
        bytes32 artifactHash = computeBatchSafeTxHash(safe, parsedTxs, safe.nonce());
        if (liveHash != artifactHash) revert VerifyMismatch("safeTxHash");
    }

    /// @notice Rebuild the canonical six-tx grants array for `clone`.
    /// Factored out so the `verify` SafeTxHash cross-check can compare
    /// the live-pre-flight bundle to the artifact bundle without
    /// duplicating the loop body in two places.
    /// @param clone The clone address each grant targets.
    /// @return txs The canonical six-tx grants array.
    function _buildExpectedGrantsTxs(address clone) internal pure returns (SafeTx[] memory txs) {
        RoleGrant[] memory allGrants = LibAuthoriserInvariants.expectedGrants();
        txs = new SafeTx[](GRANTS_TX_COUNT);
        for (uint256 i = 0; i < GRANTS_TX_COUNT; i++) {
            RoleGrant memory grant = allGrants[MIRROR_START_INDEX + i];
            txs[i] = SafeTx({
                to: clone,
                value: 0,
                data: abi.encodeCall(IAccessControl.grantRole, (grant.role, grant.grantee)),
                operation: 0
            });
        }
    }

    /// @notice Assert the V4 impl is deployed at the pinned address
    /// with the pinned codehash. Pulled out so `run()` and the deploy-
    /// branch of `verify()` share the same pre-flight.
    /// @param impl The V4 impl address to check.
    function assertV4ImplDeployed(address impl) internal view {
        if (impl.code.length == 0) revert V4ImplNotDeployed(impl);
        bytes32 actual = impl.codehash;
        bytes32 expected = LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CODEHASH_RAIN_VATS_0_1_6;
        if (actual != expected) revert V4ImplCodehashMismatch(impl, expected, actual);
    }

    /// @notice Assert the canonical CloneFactory is deployed at the
    /// rain-factory pin with the pinned codehash.
    /// @param factory The CloneFactory address to check.
    function assertCloneFactoryDeployed(address factory) internal view {
        if (factory.code.length == 0) revert CloneFactoryNotDeployed(factory);
        bytes32 actual = factory.codehash;
        bytes32 expected = LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_CODEHASH;
        if (actual != expected) revert CloneFactoryCodehashMismatch(factory, expected, actual);
    }

    /// @notice Assert the simulated clone's runtime codehash matches
    /// the EIP-1167 minimal-proxy runtime computed from the V4 impl
    /// literal. Shared by `run()`, `mirrorGrants()`, and the grants-
    /// branch of `verify()`.
    /// @param clone The clone address to check.
    /// @param expected The pre-computed minimal-proxy codehash.
    function assertCloneCodehash(address clone, bytes32 expected) internal view {
        bytes32 actual = clone.codehash;
        if (actual != expected) revert CloneCodehashMismatch(clone, expected, actual);
    }

    /// @notice Assert the seven role grants the base
    /// `OffchainAssetReceiptVaultAuthorizerV1` and the ST0x override
    /// `initialize` collectively grant to the supplied admin (the
    /// Safe) all hold on the supplied clone. Iterated in the same
    /// order as the source `_grantRole` calls in the impl so a missing
    /// role surfaces the first failure deterministically.
    /// @param clone The clone to check.
    /// @param expectedAdmin The address that should hold every auto-
    /// granted `_ADMIN` role (in production, the ST0x token-owner
    /// Safe).
    function assertAutoGrantsHeld(address clone, address expectedAdmin) internal view {
        bytes32[7] memory autoRoles = autoGrantedAdminRoles();
        IAccessControl acl = IAccessControl(clone);
        for (uint256 i = 0; i < autoRoles.length; i++) {
            if (!acl.hasRole(autoRoles[i], expectedAdmin)) {
                revert AutoGrantMissing(clone, autoRoles[i], expectedAdmin);
            }
        }
    }

    /// @notice Assert the six non-admin grants this script is about
    /// to mirror in are NOT yet held on a fresh clone. Together with
    /// `assertAutoGrantsHeld` this proves the `run()`-bundle leaves
    /// exactly the seven auto-grants and nothing else, so the mirror
    /// bundle is genuinely adding new state.
    /// @param clone The clone to check.
    function assertNonAdminGrantsAbsent(address clone) internal view {
        RoleGrant[] memory allGrants = LibAuthoriserInvariants.expectedGrants();
        IAccessControl acl = IAccessControl(clone);
        for (uint256 i = 0; i < GRANTS_TX_COUNT; i++) {
            RoleGrant memory grant = allGrants[MIRROR_START_INDEX + i];
            if (acl.hasRole(grant.role, grant.grantee)) {
                revert UnexpectedAutoGrantHeld(clone, grant.role, grant.grantee);
            }
        }
    }

    /// @notice The seven `_ADMIN` roles the base + override
    /// `initialize` grants to the supplied `initialAdmin` config.
    /// Hand-listed (in source-order of the `_grantRole` calls in the
    /// impl) rather than re-derived from `expectedGrants()` because the
    /// auto-grants overlap with — but are not identical to —
    /// `expectedGrants()` indices 0..4 (the V3 set is missing the two
    /// corporate-action admins the override adds).
    /// @return roles The seven role hashes, in `_grantRole` order.
    function autoGrantedAdminRoles() internal pure returns (bytes32[7] memory roles) {
        // Order matches the `_grantRole` sequence in the base impl
        // (`CERTIFY_ADMIN`, `CONFISCATE_RECEIPT_ADMIN`,
        // `CONFISCATE_SHARES_ADMIN`, `DEPOSIT_ADMIN`, `WITHDRAW_ADMIN`)
        // followed by the override's two extra grants
        // (`SCHEDULE_CORPORATE_ACTION_ADMIN`, `CANCEL_CORPORATE_ACTION_ADMIN`).
        roles[0] = keccak256("CERTIFY_ADMIN");
        roles[1] = keccak256("CONFISCATE_RECEIPT_ADMIN");
        roles[2] = keccak256("CONFISCATE_SHARES_ADMIN");
        roles[3] = keccak256("DEPOSIT_ADMIN");
        roles[4] = keccak256("WITHDRAW_ADMIN");
        roles[5] = keccak256("SCHEDULE_CORPORATE_ACTION_ADMIN");
        roles[6] = keccak256("CANCEL_CORPORATE_ACTION_ADMIN");
    }

    /// @notice Compute the EIP-1167 minimal-proxy runtime codehash for
    /// the supplied implementation. The OpenZeppelin `Clones` impl
    /// deploys this exact bytecode shape:
    /// `363d3d373d3d3d363d73<impl>5af43d82803e903d91602b57fd5bf3`
    /// which is what `CloneFactory.clone` produces under the hood.
    /// @dev Re-implements the codehash computation in-source rather
    /// than reading it from any external lib so the script doesn't
    /// depend on the post-deploy `LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH`
    /// pin (which is `bytes32(0)` until the clone is deployed and the
    /// post-execution PR hydrates it).
    /// @param impl The implementation address embedded in the minimal
    /// proxy.
    /// @return The keccak256 of the minimal-proxy runtime bytecode.
    function computeMinimalProxyCodehash(address impl) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(hex"363d3d373d3d3d363d73", impl, hex"5af43d82803e903d91602b57fd5bf3")
        );
    }

    /// @notice Fish the `NewClone(sender, implementation, clone)`
    /// event out of a recorded log array. The factory emits this
    /// exactly once per `clone` call; we match by emitter address (the
    /// factory) and event signature, then sanity-check the
    /// implementation field equals `expectedImpl`.
    /// @dev Reverts with a descriptive `require` message if the event
    /// is absent — that's an invariant break on the factory rather
    /// than user input, so a string-reason is a reasonable choice
    /// here (it's never reached in a healthy run).
    /// @param logs The recorded log array from `vm.getRecordedLogs()`.
    /// @param factory The CloneFactory address that should have emitted
    /// the event.
    /// @param expectedImpl The implementation address embedded in the
    /// event's `implementation` argument; cross-checked against the
    /// pinned V4 impl.
    /// @return clone The clone address from the event's `clone` field.
    function extractCloneAddressFromLogs(Vm.Log[] memory logs, address factory, address expectedImpl)
        internal
        pure
        returns (address clone)
    {
        bytes32 sig = keccak256("NewClone(address,address,address)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != factory) continue;
            if (logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] != sig) continue;
            // `NewClone` has no indexed args; sender, implementation,
            // and clone are all in `data` as three packed addresses.
            (, address implFromEvent, address cloneFromEvent) = abi.decode(logs[i].data, (address, address, address));
            require(implFromEvent == expectedImpl, "DeployV4AuthoriserClone: NewClone impl mismatch");
            return cloneFromEvent;
        }
        revert("DeployV4AuthoriserClone: NewClone not emitted");
    }

    /// @notice Compute a stable composite SafeTxHash over a batch of
    /// transactions by hashing the concatenation of the per-tx hashes.
    /// Used by `mirrorGrants` and the grants-branch of `verify` so a
    /// signer can confirm the bundle they're about to sign matches the
    /// authored artifact end-to-end.
    /// @dev Composite rather than per-tx because the Tx Builder UI
    /// signs each tx independently — the per-tx SafeTxHash chain
    /// captures the canonical hash of every signed inner tx, so any
    /// drift in any tx flips the composite. We don't try to bind to
    /// the Safe's wrapping `multiSend` hash because the bundle is a
    /// sequence of individual `execTransaction` calls, not a single
    /// delegatecall.
    /// @param safe The Safe whose nonce/domain bind into each per-tx
    /// hash.
    /// @param txs The batch of transactions.
    /// @param baseNonce The starting Safe nonce. Each tx's hash binds
    /// to `baseNonce + i`.
    /// @return The keccak256 of the concatenated per-tx hashes.
    function computeBatchSafeTxHash(IGnosisSafe safe, SafeTx[] memory txs, uint256 baseNonce)
        internal
        view
        returns (bytes32)
    {
        bytes memory acc = new bytes(0);
        for (uint256 i = 0; i < txs.length; i++) {
            acc = bytes.concat(acc, LibSafeOps.computeSafeTxHashViaSafe(safe, txs[i], baseNonce + i));
        }
        return keccak256(acc);
    }
}
