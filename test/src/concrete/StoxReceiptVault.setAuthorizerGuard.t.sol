// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
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
} from "rain-vats-0.1.6/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    OffchainAssetReceiptVaultPaymentMintAuthorizerV1Config
} from "rain-vats-0.1.6/src/concrete/authorize/OffchainAssetReceiptVaultPaymentMintAuthorizerV1.sol";
import {IAuthorizeV1} from "rain-vats-0.1.6/src/interface/IAuthorizeV1.sol";
import {CloneFactory} from "rain-factory-0.1.5/src/concrete/CloneFactory.sol";
import {VerifyAlwaysApproved} from "rain-verify-interface-0.1.0/src/concrete/VerifyAlwaysApproved.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {IERC165} from "@openzeppelin-contracts-5.6.1/utils/introspection/IERC165.sol";
import {
    IncompatibleAuthorizer,
    OffchainAssetReceiptVault
} from "rain-vats-0.1.6/src/concrete/vault/OffchainAssetReceiptVault.sol";
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
        return StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1(factory.clone(address(impl), initData));
    }

    function _newCorporateActionsAuthorizer() internal returns (StoxOffchainAssetReceiptVaultAuthorizerV1) {
        StoxOffchainAssetReceiptVaultAuthorizerV1 impl = new StoxOffchainAssetReceiptVaultAuthorizerV1();
        CloneFactory factory = new CloneFactory();
        bytes memory initData = abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: OWNER}));
        return StoxOffchainAssetReceiptVaultAuthorizerV1(factory.clone(address(impl), initData));
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
    /// DEFAULT_ADMIN_ROLE still gets rejected — on the CANCEL role.
    /// Mocked because no production authorizer presents this exact
    /// shape; the test exists to prove the second check isn't a
    /// duplicate of the first.
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

    /// On the happy path the installation actually lands — `authorizer()`
    /// returns the new address. Without `super.setAuthorizer` the guard
    /// could pass while the state stays stale, so this pins the call-
    /// through.
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

    /// `address(0)` is the canonical "no authorizer" sentinel. It has no
    /// code, so `getRoleAdmin` reverts at staticcall time. Pinning this
    /// as a named case (rather than relying on the EOA fuzz, which
    /// happens to include it) documents intent: "install no authorizer"
    /// must not silently succeed.
    function testSetAuthorizerRejectsZeroAddressAuthorizer() external {
        OwnedStoxReceiptVault vault = new OwnedStoxReceiptVault(OWNER);
        vm.prank(OWNER);
        vm.expectRevert();
        vault.setAuthorizer(IAuthorizeV1(address(0)));
    }

    /// Pin that the guard probes BOTH role admins, not just one. A
    /// refactor that collapses the two staticcalls into one — or skips
    /// the CANCEL check on the assumption that SCHEDULE implies it —
    /// would silently widen the gap the guard exists to close. Uses
    /// `vm.expectCall` so the assertion fires on call-shape, not on
    /// downstream effects.
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

    /// A guard revert must leave the prior authorizer in place — the
    /// install is all-or-nothing. Install a valid authorizer first, then
    /// try to install a bad one and assert the prior authorizer is
    /// still active. Pins that `super.setAuthorizer` runs only after the
    /// guard returns cleanly; if the guard's reverts were ever moved
    /// after the super call this assertion would fail.
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

    /// The guard's predicate is exactly `admin == bytes32(0)`, not a
    /// magnitude check or a range check. Any non-zero bytes32 — single
    /// bit, high bit, all bits — must pass. Fuzz this boundary so a
    /// refactor to `admin < someThreshold` or `uint256(admin) <= N`
    /// breaks the test rather than silently widening rejection.
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

    /// The guard is additive on top of `super.setAuthorizer`, not a
    /// replacement for its checks. Construct an authorizer that passes
    /// our role-admin guard (both admins non-zero) but explicitly fails
    /// `supportsInterface(IAuthorizeV1)`, and confirm the parent's
    /// `IncompatibleAuthorizer` revert fires. Without this pin a future
    /// refactor that drops `super.setAuthorizer` in favour of writing
    /// the storage slot directly would silently bypass the ERC165
    /// check.
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

    /// Pre-install state: `authorizer()` returns the zero address until
    /// the first `setAuthorizer` lands. Documents the baseline the guard
    /// is protecting — without a successful install, calls into the
    /// vault that staticcall `authorizer()` resolve to address(0) and
    /// fail closed.
    function testInitialAuthorizerIsZeroBeforeSetAuthorizer() external {
        OwnedStoxReceiptVault vault = new OwnedStoxReceiptVault(OWNER);
        assertEq(address(vault.authorizer()), address(0));
    }

    /// The guard depends on two assumptions about its role constants:
    /// they are distinct (otherwise a single check could satisfy both
    /// without anyone noticing) and they are non-zero (otherwise the
    /// `getRoleAdmin(DEFAULT_ADMIN_ROLE)` answer — which equals zero
    /// for an unconfigured admin — would make the guard probe its own
    /// failing condition). Pin both invariants here so a future
    /// constant rename / refactor that breaks either silently fails
    /// loudly.
    function testGuardRoleConstantsAreDistinctAndNonZero() external pure {
        assertTrue(SCHEDULE_CORPORATE_ACTION != bytes32(0));
        assertTrue(CANCEL_CORPORATE_ACTION != bytes32(0));
        assertTrue(SCHEDULE_CORPORATE_ACTION != CANCEL_CORPORATE_ACTION);
    }

    /// The override truly overrides — same 4-byte selector as the
    /// parent's `setAuthorizer`. A signature mismatch (different param
    /// type, different name) would shadow the parent rather than
    /// override it, leaving the unguarded parent function callable.
    /// Pin selector equality so a refactor that drifts the signature
    /// fails loudly.
    function testSetAuthorizerSelectorMatchesParent() external pure {
        assertEq(StoxReceiptVault.setAuthorizer.selector, OffchainAssetReceiptVault.setAuthorizer.selector);
    }

    /// The guard runs only at install time, not on every dispatch. If a
    /// previously-valid authorizer renounces its role admins post-
    /// install, `vault.authorizer()` still returns it — the guard has
    /// already done its job at the pairing point and is not re-checked.
    /// This documents the install-time-only contract; downstream
    /// operators relying on continuous validity must monitor the
    /// authorizer themselves.
    function testGuardIsInstallTimeOnlyNotPerCall() external {
        OwnedStoxReceiptVault vault = new OwnedStoxReceiptVault(OWNER);
        StoxOffchainAssetReceiptVaultAuthorizerV1 good = _newCorporateActionsAuthorizer();
        vm.prank(OWNER);
        vault.setAuthorizer(IAuthorizeV1(address(good)));
        assertEq(address(vault.authorizer()), address(good));

        // Simulate post-install role-admin renouncement by overriding the
        // authorizer's getRoleAdmin to return zero. The vault's stored
        // authorizer pointer is unchanged because the guard does not
        // re-run.
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
