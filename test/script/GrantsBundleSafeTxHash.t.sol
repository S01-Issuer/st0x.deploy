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
/// delegatecall at one nonce, so signing the logged hash authorizes the whole
/// bundle and it lands atomically.
contract GrantsBundleSafeTxHashTest is Test {
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

    /// @notice Threshold owners signing the SafeTxHash the script logs for the
    /// grants bundle authorize its execution: the Safe runs the batch as one
    /// `MultiSendCallOnly` delegatecall, consuming a single nonce, and all six
    /// grants land on the clone.
    function testGrantsBundleExecutesViaItsLoggedSafeTxHash() external {
        address clone = _setUpForkAndClone();
        SafeTx[] memory txs = _grantsTxs(clone);
        uint256 nonce = safe.nonce();

        bytes32 loggedHash = LibSafeOps.computeMultiSendSafeTxHash(safe, txs, nonce);
        bytes memory sigs = _thresholdSigs(loggedHash);
        bool ok = safe.execTransaction(
            LibSafeOps.MULTISEND_CALL_ONLY_1_4_1,
            0,
            LibSafeOps.encodeMultiSend(txs),
            1,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            sigs
        );
        assertTrue(ok, "batch executed via the logged SafeTxHash");
        assertEq(safe.nonce(), nonce + 1, "batch consumed exactly one nonce");

        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants();
        for (uint256 i = 0; i < 6; i++) {
            assertTrue(
                IAccessControl(clone).hasRole(grants[5 + i].role, grants[5 + i].grantee),
                "grant landed via the single multiSend"
            );
        }
    }

    /// @notice The logged SafeTxHash binds to every transaction in the bundle:
    /// changing any grant's target flips the hash.
    function testTamperingAGrantChangesTheLoggedSafeTxHash() external {
        address clone = _setUpForkAndClone();
        SafeTx[] memory txs = _grantsTxs(clone);
        uint256 nonce = safe.nonce();

        bytes32 original = LibSafeOps.computeMultiSendSafeTxHash(safe, txs, nonce);
        txs[3].to = makeAddr("tampered");
        bytes32 tampered = LibSafeOps.computeMultiSendSafeTxHash(safe, txs, nonce);

        assertTrue(original != tampered, "tampering a grant must change the SafeTxHash");
    }
}
