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

/// @title GrantsBundleSafeTxHashTest
/// @notice The SafeTxHash the deploy script logs for the six-tx grants bundle
/// is the hash the live Safe requires to execute that bundle. The Safe
/// Transaction Builder submits a batch as a single `MultiSendCallOnly`
/// delegatecall at one nonce, so the logged hash equals that single execution
/// hash and a signer who signs it authorizes the bundle.
contract GrantsBundleSafeTxHashTest is Test {
    /// @notice Safe{Wallet} v1.4.1 `MultiSendCallOnly`, the contract the
    /// Transaction Builder delegatecalls to execute a batch. Deployed on Base.
    address internal constant MULTISEND_CALL_ONLY_1_4_1 = 0x9641d764fc13c8B624c04430C7356C1C7C8102e2;

    IGnosisSafe internal safe;

    /// @notice Fork Base, etch the V4 impl runtime at its pin (the impl is not
    /// yet deployed on Base) so `run()`'s pre-flight passes, then `run()` to
    /// deploy a clone on the fork and wire the testable overrides to it.
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

    /// @notice The six-tx grants bundle the script emits: one `grantRole` per
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

    /// @notice The SafeTxHash the script logs for the grants bundle: keccak256
    /// of the six per-tx Safe hashes bound to nonces baseNonce..baseNonce+5.
    function _loggedGrantsSafeTxHash(SafeTx[] memory txs, uint256 baseNonce) internal view returns (bytes32) {
        bytes memory acc = new bytes(0);
        for (uint256 i = 0; i < txs.length; i++) {
            acc = bytes.concat(acc, LibSafeOps.computeSafeTxHashViaSafe(safe, txs[i], baseNonce + i));
        }
        return keccak256(acc);
    }

    /// @notice The `MultiSendCallOnly.multiSend(bytes)` calldata the Safe
    /// Transaction Builder produces for a batch: each inner tx packed as
    /// `operation(1) || to(20) || value(32) || len(32) || data`, ABI-wrapped
    /// behind the `multiSend(bytes)` selector.
    function _encodeMultiSend(SafeTx[] memory txs) internal pure returns (bytes memory) {
        bytes memory payload = new bytes(0);
        for (uint256 i = 0; i < txs.length; i++) {
            payload = bytes.concat(
                payload, abi.encodePacked(uint8(0), txs[i].to, txs[i].value, txs[i].data.length, txs[i].data)
            );
        }
        return abi.encodeWithSignature("multiSend(bytes)", payload);
    }

    /// @notice The Safe transaction that executes the grants bundle: a single
    /// DELEGATECALL to `MultiSendCallOnly` carrying the batched grants.
    function _batchTx(SafeTx[] memory txs) internal pure returns (SafeTx memory) {
        return SafeTx({to: MULTISEND_CALL_ONLY_1_4_1, value: 0, data: _encodeMultiSend(txs), operation: 1});
    }

    /// @notice Approve `hash` from the first `threshold` owners and return the
    /// ascending packed approved-hash signature blob Safe expects.
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

    /// @notice The SafeTxHash the script logs for the grants bundle equals the
    /// SafeTxHash the Safe requires to execute the bundle as a single
    /// `MultiSendCallOnly` delegatecall — the hash a signer signs.
    function testLoggedGrantsSafeTxHashMatchesSafeExecutionHash() external {
        address clone = _setUpForkAndClone();
        SafeTx[] memory txs = _grantsTxs(clone);
        uint256 nonce = safe.nonce();

        bytes32 logged = _loggedGrantsSafeTxHash(txs, nonce);
        bytes32 execution = LibSafeOps.computeSafeTxHashViaSafe(safe, _batchTx(txs), nonce);

        assertEq(logged, execution, "logged grants SafeTxHash must equal the Safe's multiSend execution hash");
    }

    /// @notice Threshold owners who sign the SafeTxHash the script logs for the
    /// grants bundle authorize its execution: approving the logged hash and
    /// submitting the `MultiSendCallOnly` batch via `execTransaction` succeeds.
    function testSigningLoggedGrantsSafeTxHashExecutesTheBundle() external {
        address clone = _setUpForkAndClone();
        SafeTx[] memory txs = _grantsTxs(clone);
        SafeTx memory batchTx = _batchTx(txs);

        bytes memory sigs = _thresholdSigs(_loggedGrantsSafeTxHash(txs, safe.nonce()));
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
        assertTrue(ok, "signing the logged grants SafeTxHash must authorize the bundle");
    }
}
