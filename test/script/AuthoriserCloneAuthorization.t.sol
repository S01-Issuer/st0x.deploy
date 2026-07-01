// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";

import {TestableDeployV4AuthoriserClone} from "./TestableDeployV4AuthoriserClone.sol";
import {IGnosisSafe} from "../../src/interface/IGnosisSafe.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibProdDeployV4} from "../../src/lib/LibProdDeployV4.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../../src/lib/LibAuthoriserInvariants.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {SCHEDULE_CORPORATE_ACTION} from "../../src/lib/LibCorporateAction.sol";
import {IAuthorizeV1, Unauthorized} from "rain-vats-0.1.6/src/interface/IAuthorizeV1.sol";
import {DEPOSIT} from "rain-vats-0.1.6/src/concrete/vault/OffchainAssetReceiptVault.sol";
import {DEPOSIT_ADMIN} from "rain-vats-0.1.6/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
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
        vm.etch(LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_RAIN_VATS_0_1_6, address(impl).code);

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
}
