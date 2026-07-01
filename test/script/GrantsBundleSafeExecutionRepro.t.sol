// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";

import {TestableDeployV4AuthoriserClone} from "./TestableDeployV4AuthoriserClone.sol";
import {IGnosisSafe} from "../../src/interface/IGnosisSafe.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibSafeOps, SafeTx} from "../../src/lib/LibSafeOps.sol";
import {LibProdDeployV4} from "../../src/lib/LibProdDeployV4.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../../src/lib/LibAuthoriserInvariants.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

/// @title GrantsBundleSafeExecutionReproTest
/// @notice FAILING reproduction for the still-open grants-bundle SafeTxHash
/// finding on `DeployV4AuthoriserClone`. NOT for the merged suite — each test
/// asserts the property that WOULD hold if the script's hash model were
/// correct, and FAILS against current code, demonstrating the bug rather than
/// enshrining it.
///
/// The script logs a composite SafeTxHash for the grants bundle — keccak256 of
/// six per-tx hashes bound to nonces N..N+5 — on the premise the bundle is "a
/// sequence of individual execTransaction calls". When the six-tx Tx Builder
/// bundle is submitted to the live ST0x Safe v1.4.1 it executes as a SINGLE
/// `MultiSendCallOnly` delegatecall: one nonce, one signable hash. So the
/// logged hash is neither what a signer signs nor what authorizes execution.
contract GrantsBundleSafeExecutionReproTest is Test {
    /// @notice Safe{Wallet} v1.4.1 `MultiSendCallOnly` — the contract the
    /// Transaction Builder app delegatecalls to execute a batch. Verified
    /// deployed on Base (410 runtime bytes).
    address internal constant MULTISEND_CALL_ONLY_1_4_1 = 0x9641d764fc13c8B624c04430C7356C1C7C8102e2;

    IGnosisSafe internal safe;

    /// @notice Fork Base, etch the not-yet-Zoltu-deployed V4 impl at its pin
    /// (the same stand-in the script's own suite uses), then `run()` to deploy
    /// a real clone on the fork and wire the testable overrides to it.
    function _setUpForkAndClone() internal returns (address clone) {
        vm.createSelectFork(LibRainDeploy.BASE);
        safe = IGnosisSafe(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);

        StoxOffchainAssetReceiptVaultAuthorizerV1 impl = new StoxOffchainAssetReceiptVaultAuthorizerV1();
        vm.etch(LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_RAIN_VATS_0_1_6, address(impl).code);

        TestableDeployV4AuthoriserClone testable = new TestableDeployV4AuthoriserClone();
        testable.run();
        clone = testable.lastPredictedClone();
        testable.setResolvedClone(clone);
        testable.setResolvedCloneCodehash(clone.codehash);
    }

    /// @notice The six-tx grants bundle the script emits — one `grantRole` per
    /// non-admin entry (indices 5..10) of `expectedGrants()`.
    function _grantsTxs(address clone) internal pure returns (SafeTx[] memory txs) {
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants();
        txs = new SafeTx[](6);
        for (uint256 i = 0; i < 6; i++) {
            RoleGrant memory g = grants[5 + i];
            txs[i] = SafeTx({
                to: clone, value: 0, data: abi.encodeCall(IAccessControl.grantRole, (g.role, g.grantee)), operation: 0
            });
        }
    }

    /// @notice Replicates the script's `computeBatchSafeTxHash`: keccak256 of
    /// the six per-tx Safe hashes bound to nonces baseNonce..baseNonce+5.
    function _scriptCompositeHash(SafeTx[] memory txs, uint256 baseNonce) internal view returns (bytes32) {
        bytes memory acc = new bytes(0);
        for (uint256 i = 0; i < txs.length; i++) {
            acc = bytes.concat(acc, LibSafeOps.computeSafeTxHashViaSafe(safe, txs[i], baseNonce + i));
        }
        return keccak256(acc);
    }

    /// @notice Encode `txs` into the `MultiSendCallOnly.multiSend(bytes)`
    /// calldata the Safe Transaction Builder produces for a batch: each inner
    /// tx packed as `operation(1) || to(20) || value(32) || len(32) || data`,
    /// then ABI-wrapped behind the `multiSend(bytes)` selector.
    function _encodeMultiSend(SafeTx[] memory txs) internal pure returns (bytes memory) {
        bytes memory payload = new bytes(0);
        for (uint256 i = 0; i < txs.length; i++) {
            payload = bytes.concat(
                payload, abi.encodePacked(uint8(0), txs[i].to, txs[i].value, txs[i].data.length, txs[i].data)
            );
        }
        return abi.encodeWithSignature("multiSend(bytes)", payload);
    }

    /// @notice Approve `hash` from the first `threshold` owners (via prank) and
    /// return the ascending packed approved-hash signature blob Safe expects.
    function _thresholdSigs(bytes32 hash) internal returns (bytes memory) {
        uint256 threshold = safe.getThreshold();
        address[] memory owners = safe.getOwners();
        address[] memory approvers = new address[](threshold);
        for (uint256 i = 0; i < threshold; i++) {
            approvers[i] = owners[i];
            vm.prank(owners[i]);
            safe.approveHash(hash);
        }
        return LibSafeOps.packApprovedHashSignatures(LibSafeOps.sortAddressesAscending(approvers), threshold);
    }

    /// @notice FAILS against current code. The script logs `scriptLogged` as
    /// the grants bundle's "SafeTxHash"; for that to mean anything to a signer
    /// it must equal the hash the Safe actually signs/executes, which is the
    /// single MultiSendCallOnly hash `realSignable`. They differ.
    function testGrantsBundleLoggedHashIsTheSignableHash() external {
        address clone = _setUpForkAndClone();
        SafeTx[] memory txs = _grantsTxs(clone);
        uint256 nonce = safe.nonce();

        bytes32 scriptLogged = _scriptCompositeHash(txs, nonce);
        SafeTx memory batchTx =
            SafeTx({to: MULTISEND_CALL_ONLY_1_4_1, value: 0, data: _encodeMultiSend(txs), operation: 1});
        bytes32 realSignable = LibSafeOps.computeSafeTxHashViaSafe(safe, batchTx, nonce);

        assertEq(scriptLogged, realSignable, "script-logged grants SafeTxHash != the hash the Safe actually signs");
    }

    /// @notice FAILS against current code. Threshold owners sign exactly what
    /// the script told them to — the logged composite hash. If the script
    /// logged the correct hash, that signature authorizes the batch. It does
    /// not: the Safe recomputes the real MultiSendCallOnly hash, finds no
    /// approval for it, and `execTransaction` reverts (`ok == false`).
    function testSigningScriptLoggedHashAuthorizesTheBatch() external {
        address clone = _setUpForkAndClone();
        SafeTx[] memory txs = _grantsTxs(clone);
        uint256 nonce = safe.nonce();

        bytes32 scriptLogged = _scriptCompositeHash(txs, nonce);
        SafeTx memory batchTx =
            SafeTx({to: MULTISEND_CALL_ONLY_1_4_1, value: 0, data: _encodeMultiSend(txs), operation: 1});

        bytes memory sigs = _thresholdSigs(scriptLogged);
        (bool ok,) = address(safe)
            .call(
                abi.encodeWithSelector(
                    IGnosisSafe.execTransaction.selector,
                    batchTx.to,
                    batchTx.value,
                    batchTx.data,
                    batchTx.operation,
                    uint256(0),
                    uint256(0),
                    uint256(0),
                    address(0),
                    payable(address(0)),
                    sigs
                )
            );
        assertTrue(ok, "signing the script-logged grants SafeTxHash did not authorize the batch");
    }
}
