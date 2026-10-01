// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {OwnedStoxReceiptVault} from "./OwnedStoxReceiptVault.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1.sol";
import {
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.2.1/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    OffchainAssetReceiptVaultPaymentMintAuthorizerV1Config
} from "rain-vats-0.2.1/src/concrete/authorize/OffchainAssetReceiptVaultPaymentMintAuthorizerV1.sol";
import {IAuthorizeV1} from "rain-vats-0.2.1/src/interface/IAuthorizeV1.sol";
import {CloneFactory} from "rain-factory-0.1.5/src/concrete/CloneFactory.sol";
import {VerifyAlwaysApproved} from "rain-verify-interface-0.1.0/src/concrete/VerifyAlwaysApproved.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {IERC165} from "@openzeppelin-contracts-5.6.1/utils/introspection/IERC165.sol";
import {
    IncompatibleAuthorizer,
    OffchainAssetReceiptVault
} from "rain-vats-0.2.1/src/concrete/vault/OffchainAssetReceiptVault.sol";
import {AuthorizerMissingCorporateActionAdmin} from "../../../src/error/ErrCorporateAction.sol";
import {SCHEDULE_CORPORATE_ACTION, CANCEL_CORPORATE_ACTION} from "../../../src/lib/LibCorporateAction.sol";
import {MockERC20} from "../../concrete/MockERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.6.1/access/OwnableUpgradeable.sol";

/// @title StoxReceiptVault setAuthorizer guard
/// @notice Pins that `StoxReceiptVault.setAuthorizer` rejects authorizers
/// that lack admin hierarchy for either corporate-action role, surfacing
/// `AuthorizerMissingCorporateActionAdmin` at the pairing point instead
/// of the (much later) first attempted use.
contract StoxReceiptVaultSetAuthorizerGuardTest is Test {
    address constant OWNER = address(uint160(uint256(keccak256("OWNER"))));

    function _newPaymentMintAuthorizer() internal returns (StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1) {
        StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1 impl =
            new StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1();
        CloneFactory factory = new CloneFactory();
        bytes memory initData = abi.encode(
            OffchainAssetReceiptVaultPaymentMintAuthorizerV1Config({
                receiptVault: address(this),
                verify: address(new VerifyAlwaysApproved()),
                owner: OWNER,
                paymentToken: address(new MockERC20()),
                maxSharesSupply: 1e27
            })
        );
        return StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1(
            factory.cloneDeterministic(address(impl), initData, bytes32(0))
        );
    }

    function _newCorporateActionsAuthorizer() internal returns (StoxOffchainAssetReceiptVaultAuthorizerV1) {
        StoxOffchainAssetReceiptVaultAuthorizerV1 impl = new StoxOffchainAssetReceiptVaultAuthorizerV1();
        CloneFactory factory = new CloneFactory();
        bytes memory initData = abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: OWNER}));
        return
            StoxOffchainAssetReceiptVaultAuthorizerV1(factory.cloneDeterministic(address(impl), initData, bytes32(0)));
    }

    /// Pairing the PaymentMint authorizer (missing corporate-action role
    /// admin hierarchy) reverts at setAuthorizer time on
    /// SCHEDULE_CORPORATE_ACTION before it ever lands.
    function testSetAuthorizerRejectsPaymentMintAuthorizer() external {
        OwnedStoxReceiptVault vault = new OwnedStoxReceiptVault(OWNER);
        StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1 bad = _newPaymentMintAuthorizer();
        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                AuthorizerMissingCorporateActionAdmin.selector, address(bad), SCHEDULE_CORPORATE_ACTION
            )
        );
        vault.setAuthorizer(IAuthorizeV1(address(bad)));
    }

    /// The corporate-actions authorizer configures both role admins, so
    /// the guard accepts it and the installation goes through.
    function testSetAuthorizerAcceptsCorporateActionsAuthorizer() external {
        OwnedStoxReceiptVault vault = new OwnedStoxReceiptVault(OWNER);
        StoxOffchainAssetReceiptVaultAuthorizerV1 good = _newCorporateActionsAuthorizer();
        vm.prank(OWNER);
        vault.setAuthorizer(IAuthorizeV1(address(good)));
    }

    /// `onlyOwner` is inherited via `super.setAuthorizer` — the override
    /// itself has no modifier, so the guard's role-admin staticcalls run
    /// before the ownership check. With a well-behaved authorizer that
    /// passes the guard, control falls through to `super.setAuthorizer`,
    /// which reverts `OwnableUnauthorizedAccount` for non-owner callers.
    function testSetAuthorizerRejectsNonOwnerCaller(address attacker) external {
        vm.assume(attacker != OWNER);
        OwnedStoxReceiptVault vault = new OwnedStoxReceiptVault(OWNER);
        StoxOffchainAssetReceiptVaultAuthorizerV1 good = _newCorporateActionsAuthorizer();
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, attacker));
        vault.setAuthorizer(IAuthorizeV1(address(good)));
    }

    /// Independence of the two role checks: an authorizer that
    /// configures the SCHEDULE admin but leaves CANCEL falling back to
    /// DEFAULT_ADMIN_ROLE still gets rejected, on the CANCEL role.
    /// Mocked: no production authorizer presents this shape.
    function testSetAuthorizerRejectsAuthorizerWithOnlyScheduleAdminConfigured() external {
        OwnedStoxReceiptVault vault = new OwnedStoxReceiptVault(OWNER);
        address half = makeAddr("half-configured-authorizer");
        vm.mockCall(
            half,
            abi.encodeWithSelector(IAccessControl.getRoleAdmin.selector, SCHEDULE_CORPORATE_ACTION),
            abi.encode(bytes32(uint256(1)))
        );
        vm.mockCall(
            half,
            abi.encodeWithSelector(IAccessControl.getRoleAdmin.selector, CANCEL_CORPORATE_ACTION),
            abi.encode(bytes32(0))
        );
        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(AuthorizerMissingCorporateActionAdmin.selector, half, CANCEL_CORPORATE_ACTION)
        );
        vault.setAuthorizer(IAuthorizeV1(half));
    }

    /// On the happy path the installation lands: `authorizer()` returns the
    /// new address.
    function testSetAuthorizerInstallsAuthorizerOnSuccess() external {
        OwnedStoxReceiptVault vault = new OwnedStoxReceiptVault(OWNER);
        StoxOffchainAssetReceiptVaultAuthorizerV1 good = _newCorporateActionsAuthorizer();
        vm.prank(OWNER);
        vault.setAuthorizer(IAuthorizeV1(address(good)));
        assertEq(address(vault.authorizer()), address(good));
    }

    /// `super.setAuthorizer` emits `AuthorizerSet`. The guard adds no
    /// events of its own; pin that the call-through still emits.
    function testSetAuthorizerEmitsAuthorizerSet() external {
        OwnedStoxReceiptVault vault = new OwnedStoxReceiptVault(OWNER);
        StoxOffchainAssetReceiptVaultAuthorizerV1 good = _newCorporateActionsAuthorizer();
        vm.prank(OWNER);
        vm.expectEmit(true, true, true, true, address(vault));
        emit IAuthorizeV1.AuthorizerSet(OWNER, IAuthorizeV1(address(good)));
        vault.setAuthorizer(IAuthorizeV1(address(good)));
    }

    /// An EOA / zero-code address can't satisfy `getRoleAdmin`. Solidity
    /// reverts the staticcall when the target has no code. The guard
    /// surfaces this as a raw revert, not as
    /// `AuthorizerMissingCorporateActionAdmin` — the latter is reserved
    /// for the case where the contract IS present but explicitly leaves
    /// the admin unconfigured.
    function testSetAuthorizerRevertsOnNonContractAuthorizer(address eoa) external {
        vm.assume(eoa.code.length == 0);
        OwnedStoxReceiptVault vault = new OwnedStoxReceiptVault(OWNER);
        vm.prank(OWNER);
        vm.expectRevert();
        vault.setAuthorizer(IAuthorizeV1(eoa));
    }

    /// Setting authorizer twice in sequence with two distinct valid
    /// authorizers works — second call overwrites the first.
    function testSetAuthorizerReinstallReplacesPriorAuthorizer() external {
        OwnedStoxReceiptVault vault = new OwnedStoxReceiptVault(OWNER);
        StoxOffchainAssetReceiptVaultAuthorizerV1 first = _newCorporateActionsAuthorizer();
        StoxOffchainAssetReceiptVaultAuthorizerV1 second = _newCorporateActionsAuthorizer();
        assertTrue(address(first) != address(second), "fixture must produce distinct authorizers");

        vm.startPrank(OWNER);
        vault.setAuthorizer(IAuthorizeV1(address(first)));
        assertEq(address(vault.authorizer()), address(first));
        vault.setAuthorizer(IAuthorizeV1(address(second)));
        assertEq(address(vault.authorizer()), address(second));
        vm.stopPrank();
    }

    /// A revert raised inside the authorizer's `getRoleAdmin` propagates
    /// verbatim. The guard does not try-catch, swallow, or rewrap — if
    /// the authorizer signals an error during the role-admin probe the
    /// caller sees exactly that error, not
    /// `AuthorizerMissingCorporateActionAdmin`.
    function testSetAuthorizerBubblesUpRevertFromAuthorizer() external {
        OwnedStoxReceiptVault vault = new OwnedStoxReceiptVault(OWNER);
        address reverting = makeAddr("reverting-authorizer");
        bytes memory canary = abi.encodeWithSignature("AuthorizerProbeFailed(string)", "probe");
        vm.mockCallRevert(
            reverting, abi.encodeWithSelector(IAccessControl.getRoleAdmin.selector, SCHEDULE_CORPORATE_ACTION), canary
        );
        vm.prank(OWNER);
        vm.expectRevert(canary);
        vault.setAuthorizer(IAuthorizeV1(reverting));
    }

    /// Reinstalling the same authorizer is a no-op from the role-admin
    /// guard's perspective: the same staticcalls run again, the same
    /// non-zero admins are read, the call falls through to super, and
    /// `authorizer()` returns the same address. Pin that idempotent
    /// installation is allowed — the guard isn't accidentally one-shot.
    function testSetAuthorizerSameAuthorizerTwiceIsAllowed() external {
        OwnedStoxReceiptVault vault = new OwnedStoxReceiptVault(OWNER);
        StoxOffchainAssetReceiptVaultAuthorizerV1 good = _newCorporateActionsAuthorizer();
        vm.startPrank(OWNER);
        vault.setAuthorizer(IAuthorizeV1(address(good)));
        vault.setAuthorizer(IAuthorizeV1(address(good)));
        vm.stopPrank();
        assertEq(address(vault.authorizer()), address(good));
    }

    /// `address(0)` has no code, so `getRoleAdmin` reverts at staticcall
    /// time: "install no authorizer" does not succeed.
    function testSetAuthorizerRejectsZeroAddressAuthorizer() external {
        OwnedStoxReceiptVault vault = new OwnedStoxReceiptVault(OWNER);
        vm.prank(OWNER);
        vm.expectRevert();
        vault.setAuthorizer(IAuthorizeV1(address(0)));
    }

    /// The guard probes both role admins. `vm.expectCall` asserts on
    /// call shape, not on downstream effects.
    function testSetAuthorizerCallsGetRoleAdminForBothRoles() external {
        OwnedStoxReceiptVault vault = new OwnedStoxReceiptVault(OWNER);
        StoxOffchainAssetReceiptVaultAuthorizerV1 good = _newCorporateActionsAuthorizer();
        vm.expectCall(
            address(good), abi.encodeWithSelector(IAccessControl.getRoleAdmin.selector, SCHEDULE_CORPORATE_ACTION)
        );
        vm.expectCall(
            address(good), abi.encodeWithSelector(IAccessControl.getRoleAdmin.selector, CANCEL_CORPORATE_ACTION)
        );
        vm.prank(OWNER);
        vault.setAuthorizer(IAuthorizeV1(address(good)));
    }

    /// A guard revert leaves the prior authorizer in place: install a
    /// valid authorizer, then try to install a bad one and assert the
    /// prior authorizer is still active.
    function testSetAuthorizerKeepsPriorAuthorizerOnGuardRevert() external {
        OwnedStoxReceiptVault vault = new OwnedStoxReceiptVault(OWNER);
        StoxOffchainAssetReceiptVaultAuthorizerV1 good = _newCorporateActionsAuthorizer();
        StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1 bad = _newPaymentMintAuthorizer();

        vm.startPrank(OWNER);
        vault.setAuthorizer(IAuthorizeV1(address(good)));
        assertEq(address(vault.authorizer()), address(good));
        vm.expectRevert(
            abi.encodeWithSelector(
                AuthorizerMissingCorporateActionAdmin.selector, address(bad), SCHEDULE_CORPORATE_ACTION
            )
        );
        vault.setAuthorizer(IAuthorizeV1(address(bad)));
        vm.stopPrank();
        assertEq(address(vault.authorizer()), address(good));
    }

    /// The guard's predicate is `admin == bytes32(0)`: any non-zero
    /// bytes32 passes.
    function testSetAuthorizerAcceptsAnyNonZeroRoleAdmin(bytes32 scheduleAdmin, bytes32 cancelAdmin) external {
        vm.assume(scheduleAdmin != bytes32(0));
        vm.assume(cancelAdmin != bytes32(0));
        OwnedStoxReceiptVault vault = new OwnedStoxReceiptVault(OWNER);
        address mocked = makeAddr("mocked-authorizer");
        vm.mockCall(
            mocked,
            abi.encodeWithSelector(IAccessControl.getRoleAdmin.selector, SCHEDULE_CORPORATE_ACTION),
            abi.encode(scheduleAdmin)
        );
        vm.mockCall(
            mocked,
            abi.encodeWithSelector(IAccessControl.getRoleAdmin.selector, CANCEL_CORPORATE_ACTION),
            abi.encode(cancelAdmin)
        );
        // super._setAuthorizer probes IERC165(authorizer).supportsInterface(IAuthorizeV1).
        vm.mockCall(
            mocked,
            abi.encodeWithSelector(IERC165.supportsInterface.selector, type(IAuthorizeV1).interfaceId),
            abi.encode(true)
        );
        vm.prank(OWNER);
        vault.setAuthorizer(IAuthorizeV1(mocked));
        assertEq(address(vault.authorizer()), mocked);
    }

    /// The guard is additive on top of `super.setAuthorizer`: an
    /// authorizer that passes the role-admin guard but fails
    /// `supportsInterface(IAuthorizeV1)` reverts `IncompatibleAuthorizer`.
    function testSetAuthorizerStillEnforcesSuperInterfaceCheck() external {
        OwnedStoxReceiptVault vault = new OwnedStoxReceiptVault(OWNER);
        address mocked = makeAddr("interface-failing-authorizer");
        vm.mockCall(
            mocked,
            abi.encodeWithSelector(IAccessControl.getRoleAdmin.selector, SCHEDULE_CORPORATE_ACTION),
            abi.encode(bytes32(uint256(1)))
        );
        vm.mockCall(
            mocked,
            abi.encodeWithSelector(IAccessControl.getRoleAdmin.selector, CANCEL_CORPORATE_ACTION),
            abi.encode(bytes32(uint256(1)))
        );
        vm.mockCall(
            mocked,
            abi.encodeWithSelector(IERC165.supportsInterface.selector, type(IAuthorizeV1).interfaceId),
            abi.encode(false)
        );
        vm.prank(OWNER);
        vm.expectRevert(IncompatibleAuthorizer.selector);
        vault.setAuthorizer(IAuthorizeV1(mocked));
    }

    /// `authorizer()` returns the zero address until the first
    /// `setAuthorizer` lands.
    function testInitialAuthorizerIsZeroBeforeSetAuthorizer() external {
        OwnedStoxReceiptVault vault = new OwnedStoxReceiptVault(OWNER);
        assertEq(address(vault.authorizer()), address(0));
    }

    /// The guard's role constants are distinct and non-zero. A zero role
    /// would make `getRoleAdmin` answer zero for an unconfigured admin and
    /// the guard probe its own failing condition.
    function testGuardRoleConstantsAreDistinctAndNonZero() external pure {
        assertTrue(SCHEDULE_CORPORATE_ACTION != bytes32(0));
        assertTrue(CANCEL_CORPORATE_ACTION != bytes32(0));
        assertTrue(SCHEDULE_CORPORATE_ACTION != CANCEL_CORPORATE_ACTION);
    }

    /// The override has the same 4-byte selector as the parent's
    /// `setAuthorizer`; a signature mismatch would leave the unguarded
    /// parent function callable.
    function testSetAuthorizerSelectorMatchesParent() external pure {
        assertEq(StoxReceiptVault.setAuthorizer.selector, OffchainAssetReceiptVault.setAuthorizer.selector);
    }

    /// The guard runs only at install time. If an installed authorizer
    /// renounces its role admins afterwards, `vault.authorizer()` still
    /// returns it.
    function testGuardIsInstallTimeOnlyNotPerCall() external {
        OwnedStoxReceiptVault vault = new OwnedStoxReceiptVault(OWNER);
        StoxOffchainAssetReceiptVaultAuthorizerV1 good = _newCorporateActionsAuthorizer();
        vm.prank(OWNER);
        vault.setAuthorizer(IAuthorizeV1(address(good)));
        assertEq(address(vault.authorizer()), address(good));

        // Simulate post-install role-admin renouncement by overriding the
        // authorizer's getRoleAdmin to return zero.
        vm.mockCall(
            address(good),
            abi.encodeWithSelector(IAccessControl.getRoleAdmin.selector, SCHEDULE_CORPORATE_ACTION),
            abi.encode(bytes32(0))
        );
        vm.mockCall(
            address(good),
            abi.encodeWithSelector(IAccessControl.getRoleAdmin.selector, CANCEL_CORPORATE_ACTION),
            abi.encode(bytes32(0))
        );
        assertEq(address(vault.authorizer()), address(good));
    }
}
