// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {VmSafe} from "forge-std-1.16.1/src/Vm.sol";
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
import {SCHEDULE_CORPORATE_ACTION} from "../../src/lib/LibCorporateAction.sol";
import {ICloneableFactoryV2} from "rain-factory-0.1.1/src/interface/ICloneableFactoryV2.sol";
import {LibCloneFactoryDeploy} from "rain-factory-0.1.1/src/lib/LibCloneFactoryDeploy.sol";
import {IAuthorizeV1, Unauthorized} from "rain-vats-0.1.6/src/interface/IAuthorizeV1.sol";
import {DEPOSIT} from "rain-vats-0.1.6/src/concrete/vault/OffchainAssetReceiptVault.sol";
import {
    DEPOSIT_ADMIN,
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.1.6/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

/// @title AuthoriserCloneAuthorizationTest
/// @notice The clone the deploy + grants bundles produce is a functioning
/// authoriser: it authorizes every operation the grants intend, denies
/// un-granted callers, and the Safe admin the deploy bundle installs can
/// onboard new operators — including the corporate-action roles the Stox
/// override adds.
contract AuthoriserCloneAuthorizationTest is Test {
    IGnosisSafe internal safe;

    /// @notice Fork Base, deploy a clone via `run()`, and mirror the six
    /// non-admin grants so the clone holds the full production grant set.
    function _deployAndMirror() internal returns (address clone) {
        vm.createSelectFork(LibRainDeploy.BASE);
        safe = IGnosisSafe(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);

        StoxOffchainAssetReceiptVaultAuthorizerV1 impl = new StoxOffchainAssetReceiptVaultAuthorizerV1();
        vm.etch(LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1, address(impl).code);

        TestableDeployV4AuthoriserClone testable = new TestableDeployV4AuthoriserClone();
        testable.run();
        clone = testable.lastPredictedClone();
        testable.setResolvedClone(clone);
        testable.setResolvedCloneCodehash(clone.codehash);
        testable.mirrorGrants();
    }

    /// @notice Every operational grant authorizes its grantee: for each
    /// (grantee, permission) in the mirrored slice of `expectedGrants()`, the
    /// clone's `authorize` returns rather than reverting `Unauthorized`.
    function testMirroredGrantsAuthorizeTheirOperations() external {
        address clone = _deployAndMirror();
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants();
        for (uint256 i = 5; i < grants.length; i++) {
            IAuthorizeV1(clone).authorize(grants[i].grantee, grants[i].role, hex"");
        }
    }

    /// @notice An address holding no operational role is denied: `authorize`
    /// reverts `Unauthorized` for DEPOSIT.
    function testUngrantedAddressIsDeniedDeposit() external {
        address clone = _deployAndMirror();
        address nobody = makeAddr("nobody");
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, nobody, DEPOSIT, hex""));
        IAuthorizeV1(clone).authorize(nobody, DEPOSIT, hex"");
    }

    /// @notice The Safe admin the deploy bundle installs can onboard a new
    /// DEPOSIT operator, who is then authorized to deposit.
    function testSafeAdminCanOnboardADepositOperator() external {
        address clone = _deployAndMirror();
        address operator = makeAddr("operator");
        vm.prank(address(safe));
        IAccessControl(clone).grantRole(DEPOSIT, operator);
        IAuthorizeV1(clone).authorize(operator, DEPOSIT, hex"");
    }

    /// @notice A caller without DEPOSIT_ADMIN cannot grant DEPOSIT: `grantRole`
    /// reverts naming DEPOSIT_ADMIN as the missing role.
    function testNonAdminCannotGrantDeposit() external {
        address clone = _deployAndMirror();
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, attacker, DEPOSIT_ADMIN)
        );
        IAccessControl(clone).grantRole(DEPOSIT, makeAddr("victim"));
    }

    /// @notice The corporate-action admin the Stox override adds is functional:
    /// the Safe, holding SCHEDULE_CORPORATE_ACTION_ADMIN, can grant
    /// SCHEDULE_CORPORATE_ACTION to a scheduler who is then authorized for it.
    function testSafeAdminCanOnboardACorporateActionScheduler() external {
        address clone = _deployAndMirror();
        address scheduler = makeAddr("scheduler");
        vm.prank(address(safe));
        IAccessControl(clone).grantRole(SCHEDULE_CORPORATE_ACTION, scheduler);
        IAuthorizeV1(clone).authorize(scheduler, SCHEDULE_CORPORATE_ACTION, hex"");
    }

    /// @notice The six-tx grants bundle: one `grantRole` per non-admin entry
    /// (indices 5..10) of `expectedGrants()`.
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

    /// @notice Extract the clone address from the factory's `NewClone` event.
    function _cloneFromLogs(VmSafe.Log[] memory logs, address factory, address expectedImpl)
        internal
        pure
        returns (address)
    {
        bytes32 sig = keccak256("NewClone(address,address,address)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != factory) continue;
            if (logs[i].topics.length == 0 || logs[i].topics[0] != sig) continue;
            (, address implFromEvent, address cloneFromEvent) = abi.decode(logs[i].data, (address, address, address));
            require(implFromEvent == expectedImpl, "unexpected impl in NewClone");
            return cloneFromEvent;
        }
        revert("NewClone not emitted");
    }

    /// @notice End-to-end: the Safe owners sign and submit the deploy bundle as
    /// a real `execTransaction` to deploy the clone, then sign and submit the
    /// grants MultiSend bundle at the next nonce, and the clone the signed
    /// bundles produce authorizes the mirrored operations and denies an
    /// un-granted caller. The whole path runs through `checkSignatures`, not a
    /// prank of the Safe.
    function testEndToEndSignedBundlesProduceAWorkingAuthoriser() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        safe = IGnosisSafe(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
        StoxOffchainAssetReceiptVaultAuthorizerV1 impl = new StoxOffchainAssetReceiptVaultAuthorizerV1();
        address v4Impl = LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1;
        vm.etch(v4Impl, address(impl).code);
        address factory = LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS;

        // 1. Deploy bundle: a signed direct execTransaction to the CloneFactory.
        bytes memory deployData = abi.encodeCall(
            ICloneableFactoryV2.clone,
            (v4Impl, abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: address(safe)})))
        );
        bytes32 deployHash = LibSafeOps.computeSafeTxHashViaSafe(
            safe, SafeTx({to: factory, value: 0, data: deployData, operation: 0}), safe.nonce()
        );
        bytes memory deploySigs = _thresholdSigs(deployHash);
        vm.recordLogs();
        bool okDeploy =
            safe.execTransaction(factory, 0, deployData, 0, 0, 0, 0, address(0), payable(address(0)), deploySigs);
        assertTrue(okDeploy, "deploy bundle executed");
        address clone = _cloneFromLogs(vm.getRecordedLogs(), factory, v4Impl);

        // 2. Grants bundle: a signed MultiSend execTransaction at the next nonce.
        SafeTx[] memory grants = _grantsTxs(clone);
        bytes32 grantsHash = LibSafeOps.computeMultiSendSafeTxHash(safe, grants, safe.nonce());
        bytes memory grantsSigs = _thresholdSigs(grantsHash);
        bool okGrants = safe.execTransaction(
            LibSafeOps.MULTISEND_CALL_ONLY_1_4_1,
            0,
            LibSafeOps.encodeMultiSend(grants),
            1,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            grantsSigs
        );
        assertTrue(okGrants, "grants bundle executed");

        // 3. The clone the signed bundles produced authorizes the mirrored
        //    operations and denies an un-granted caller.
        RoleGrant[] memory all = LibAuthoriserInvariants.expectedGrants();
        for (uint256 i = 5; i < all.length; i++) {
            IAuthorizeV1(clone).authorize(all[i].grantee, all[i].role, hex"");
        }
        address nobody = makeAddr("nobody");
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, nobody, DEPOSIT, hex""));
        IAuthorizeV1(clone).authorize(nobody, DEPOSIT, hex"");
    }
}
