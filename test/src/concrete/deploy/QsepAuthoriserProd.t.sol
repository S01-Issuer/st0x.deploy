// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";
import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {IERC4626} from "@openzeppelin-contracts-5.7.0/interfaces/IERC4626.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.7.0/access/OwnableUpgradeable.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {IReceiptVaultV3} from "rain-vats-0.2.20/src/interface/IReceiptVaultV3.sol";
import {OffchainAssetReceiptVault} from "rain-vats-0.2.20/src/abstract/OffchainAssetReceiptVault.sol";
import {IAuthorizeV1, Unauthorized} from "rain-vats-0.2.20/src/interface/IAuthorizeV1.sol";
import {AuthorizerMissingCorporateActionAdmin} from "../../../../src/error/ErrCorporateAction.sol";

import {IST0xOrchestratorV1} from "../../../../src/interface/deprecated/IST0xOrchestratorV1.sol";
import {LibExtrospectRegistryBeaconProxy} from "rain-extrospection-0.1.16/src/lib/LibExtrospectRegistryBeaconProxy.sol";
import {IAuthorisable} from "../../../../src/interface/IAuthorisable.sol";
import {IOwnable} from "../../../../src/interface/IOwnable.sol";
import {LibAuthoriserInvariants} from "../../../../src/lib/LibAuthoriserInvariants.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../../../../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants} from "../../../../src/lib/LibTokenInvariants.sol";

/// @title QsepAuthoriserProdTest
/// @notice The tQSEP triple, read against live Base, and the one-call
/// token-owner Safe transaction that moves the tQSEP vault from the V3
/// authoriser clone onto the fleet authoriser `STOX_PROD_AUTHORISER`.
/// @dev The before-and-after tests fork Base at `PRE_SWAP_BLOCK`, where the
/// vault is still on the V3 clone, so they do not change once the Safe
/// transaction executes. The vault cannot go back to the V3 clone (see
/// `testVaultCannotGoBackToTheV3Clone`), so a live-head fork could not
/// recreate the before state.
contract QsepAuthoriserProdTest is Test {
    /// `setAuthorizer(STOX_PROD_AUTHORISER)`, sent by the token-owner Safe to
    /// `QSEP_RECEIPT_VAULT` with value 0.
    bytes internal constant SET_AUTHORIZER =
        hex"058a628f000000000000000000000000315b16faa6ee413fabca877d3851b3818369f0cd";

    /// The retired Fireblocks signer. It still holds DEPOSIT, WITHDRAW and
    /// CERTIFY on the V3 clone, and none of them on the fleet authoriser.
    address internal constant RETIRED_SIGNER_1C66 = 0x1c66D6708914C40239D54919320b4C48cAE3D1A9;

    /// A Base block where the tQSEP vault is on the V3 clone, the
    /// orchestrator holds no role there, and the fleet authoriser still
    /// grants the service signer DEPOSIT and WITHDRAW.
    uint256 internal constant PRE_SWAP_BLOCK = 55685398;

    uint256 internal constant AMOUNT = 1e18;

    OffchainAssetReceiptVault internal vault =
        OffchainAssetReceiptVault(payable(LibTokenInvariants.QSEP_RECEIPT_VAULT));

    function forkPreSwap() internal {
        vm.createSelectFork(LibRainDeploy.BASE, PRE_SWAP_BLOCK);
        assertEq(
            IAuthorisable(address(vault)).authorizer(),
            LibAuthoriserInvariants.STOX_PROD_AUTHORISER_V3_CLONE,
            "on the V3 clone before the Safe transaction"
        );
    }

    /// Live head: the triple, the owner, and the authoriser, which is the V3
    /// clone until the Safe transaction executes and the fleet one after.
    function testQsepTripleIsWired() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        address vaultAddress = address(vault);
        assertEq(address(IReceiptVaultV3(payable(vaultAddress)).receipt()), LibTokenInvariants.QSEP_RECEIPT, "receipt");
        assertEq(IERC4626(LibTokenInvariants.QSEP_WRAPPED_TOKEN_VAULT).asset(), vaultAddress, "wrapped asset");
        assertEq(IOwnable(vaultAddress).owner(), LibSafeInvariants.STOX_TOKEN_OWNER_SAFE, "owner");
        address authoriser = IAuthorisable(vaultAddress).authorizer();
        assertTrue(
            authoriser == LibAuthoriserInvariants.STOX_PROD_AUTHORISER_V3_CLONE
                || authoriser == LibAuthoriserInvariants.STOX_PROD_AUTHORISER,
            "the V3 clone before the Safe transaction, the fleet authoriser after"
        );

        // The deployed 0.1.30 guard checks the production beacons the
        // orchestrator is bound to, not each token's own proxy, so it passes
        // for every token. tQSEP's vault and receipt proxy the same
        // implementations as tAAPL's, which the orchestrator already mints.
        assertTrue(IST0xOrchestratorV1(LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR).vaultLogicIsExpected(), "guard");
        assertEq(
            beaconImplementation(vaultAddress),
            beaconImplementation(LibTokenInvariants.AAPL_RECEIPT_VAULT),
            "vault logic"
        );
        assertEq(
            beaconImplementation(LibTokenInvariants.QSEP_RECEIPT),
            beaconImplementation(LibTokenInvariants.AAPL_RECEIPT),
            "receipt logic"
        );
    }

    function beaconImplementation(address proxy) internal view returns (address) {
        (bool isProxy, address beacon) = LibExtrospectRegistryBeaconProxy.isRegistryBeaconProxy(proxy.code);
        assertTrue(isProxy, string.concat("not a registry beacon proxy: ", vm.toString(proxy)));
        return IBeacon(beacon).implementation();
    }

    function testCalldataIsSetAuthorizerToTheFleetAuthoriser() external pure {
        assertEq(
            SET_AUTHORIZER,
            abi.encodeCall(
                OffchainAssetReceiptVault.setAuthorizer, (IAuthorizeV1(LibAuthoriserInvariants.STOX_PROD_AUTHORISER))
            )
        );
        assertEq(OffchainAssetReceiptVault.setAuthorizer.selector, bytes4(0x058a628f), "setAuthorizer(address)");
    }

    function sendAsSafe() internal {
        vm.prank(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
        (bool ok,) = address(vault).call(SET_AUTHORIZER);
        assertTrue(ok, "the Safe can set the authoriser");
    }

    /// The Safe transaction changes one storage slot of the vault, the
    /// authoriser, and emits one `AuthorizerSet`. Certification, supply,
    /// receipts and ownership stay as they were.
    function testSafeTransactionChangesOnlyTheAuthoriser() external {
        forkPreSwap();
        bool expiredBefore = vault.isCertificationExpired();
        uint256 supplyBefore = vault.totalSupply();
        uint256 highwaterBefore = vault.highwaterId();

        vm.recordLogs();
        vm.record();
        sendAsSafe();
        (, bytes32[] memory writes) = vm.accesses(address(vault));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(writes.length, 1, "one slot written");
        assertEq(logs.length, 1, "one event");
        assertEq(logs[0].emitter, address(vault));
        assertEq(logs[0].topics[0], IAuthorizeV1.AuthorizerSet.selector);
        assertEq(
            logs[0].data,
            abi.encode(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE, LibAuthoriserInvariants.STOX_PROD_AUTHORISER)
        );

        assertEq(IAuthorisable(address(vault)).authorizer(), LibAuthoriserInvariants.STOX_PROD_AUTHORISER);
        assertEq(IOwnable(address(vault)).owner(), LibSafeInvariants.STOX_TOKEN_OWNER_SAFE, "owner");
        assertEq(vault.isCertificationExpired(), expiredBefore, "certification");
        assertEq(vault.totalSupply(), supplyBefore, "supply");
        assertEq(vault.highwaterId(), highwaterBefore, "receipts");
    }

    /// Only the vault owner can send it. The timelock, which holds the fleet
    /// authoriser's `_ADMIN` roles, does not own this vault.
    function testOnlyTheSafeCanSetTheAuthoriser() external {
        forkPreSwap();
        address timelock = LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK;
        vm.prank(timelock);
        (bool ok, bytes memory reason) = address(vault).call(SET_AUTHORIZER);
        assertFalse(ok);
        assertEq(reason, abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, timelock));
    }

    /// The deployed vault's `setAuthorizer` refuses an authoriser that has no
    /// corporate-action role admins, and the V3 clone has none. So after the
    /// Safe transaction the vault cannot be set back to the V3 clone.
    function testVaultCannotGoBackToTheV3Clone() external {
        forkPreSwap();
        sendAsSafe();
        address v3 = LibAuthoriserInvariants.STOX_PROD_AUTHORISER_V3_CLONE;
        vm.prank(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
        vm.expectRevert(
            abi.encodeWithSelector(
                AuthorizerMissingCorporateActionAdmin.selector, v3, keccak256("SCHEDULE_CORPORATE_ACTION")
            )
        );
        vault.setAuthorizer(IAuthorizeV1(v3));
    }

    /// Certify the vault so the role checks decide every call below.
    function certify() internal {
        vm.prank(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
        vault.certify(block.timestamp + 1 days, false, "");
    }

    function assertUnauthorized(bytes memory call, address user, bytes32 permission) internal {
        vm.prank(user);
        (bool ok, bytes memory reason) = address(vault).call(call);
        assertFalse(ok, "call must revert");
        // The revert's trailing `data` is the encoded state change, so only
        // the user and permission words are compared.
        bytes memory head = abi.encodeWithSelector(Unauthorized.selector, user, permission);
        assertGe(reason.length, head.length);
        for (uint256 i = 0; i < head.length; i++) {
            assertEq(reason[i], head[i], "Unauthorized(user, permission)");
        }
    }

    function mintCall(address to) internal view returns (bytes memory) {
        return abi.encodeCall(vault.mint, (AMOUNT, to, 0, ""));
    }

    function depositCall(address to) internal view returns (bytes memory) {
        return abi.encodeCall(vault.deposit, (AMOUNT, to, 0, ""));
    }

    /// Mint `AMOUNT` and redeem it back, as `user`, directly on the vault.
    function mintAndRedeem(address user) internal {
        uint256 before = vault.balanceOf(user);
        vm.prank(user);
        assertEq(vault.mint(AMOUNT, user, 0, ""), AMOUNT, "1:1 share ratio");
        assertEq(vault.balanceOf(user), before + AMOUNT, "minted");
        uint256 id = vault.highwaterId();
        vm.prank(user);
        vault.redeem(AMOUNT, user, user, id, "");
        assertEq(vault.balanceOf(user), before, "redeemed");
    }

    /// Deposit `AMOUNT` and withdraw it back, as `user`, directly on the
    /// vault: the issuance bot's vault-direct mint and burn.
    function depositAndWithdraw(address user) internal {
        uint256 before = vault.balanceOf(user);
        vm.prank(user);
        vault.deposit(AMOUNT, user, 0, "");
        assertEq(vault.balanceOf(user), before + AMOUNT, "deposited");
        uint256 id = vault.highwaterId();
        vm.prank(user);
        vault.withdraw(AMOUNT, user, user, id, "");
        assertEq(vault.balanceOf(user), before, "withdrawn");
    }

    /// On the V3 clone the orchestrator holds no DEPOSIT, so its mint
    /// reverts. After the Safe transaction it mints and redeems directly on
    /// the vault with the fleet authoriser's DEPOSIT and WITHDRAW. These are
    /// the vault calls that the orchestrator's `mint` and `burn` make.
    function testOrchestratorMintsAndRedeemsAfterTheSwap() external {
        address orchestrator = LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR;
        forkPreSwap();
        certify();
        assertUnauthorized(mintCall(orchestrator), orchestrator, keccak256("DEPOSIT"));

        sendAsSafe();
        mintAndRedeem(orchestrator);
    }

    /// The retired signer can mint on the V3 clone and cannot deposit,
    /// withdraw or certify after the Safe transaction, though its V3 grants
    /// stay.
    function testRetiredSignerLosesTqsepAfterTheSwap() external {
        address signer = RETIRED_SIGNER_1C66;
        forkPreSwap();
        certify();

        uint256 before = vault.balanceOf(signer);
        vm.prank(signer);
        vault.deposit(AMOUNT, signer, 0, "");
        uint256 id = vault.highwaterId();

        sendAsSafe();
        assertUnauthorized(depositCall(signer), signer, keccak256("DEPOSIT"));
        assertUnauthorized(
            abi.encodeCall(vault.withdraw, (AMOUNT, signer, signer, id, "")), signer, keccak256("WITHDRAW")
        );
        bool forceUntil;
        assertUnauthorized(
            abi.encodeCall(vault.certify, (block.timestamp + 2 days, forceUntil, "")), signer, keccak256("CERTIFY")
        );
        assertEq(vault.balanceOf(signer), before + AMOUNT, "only the pre-swap deposit");
    }

    /// The issuance bot's vault-direct path for tQSEP signs with the service
    /// signer. After the Safe transaction that path works exactly while the
    /// fleet authoriser grants the signer DEPOSIT and WITHDRAW (it does until
    /// `20261109`'s revoke executes), and on the V3 clone it reverts, because
    /// the V3 clone does not grant it DEPOSIT.
    function testServiceSignerVaultDirectFollowsTheFleetGrants() external {
        address signer = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;
        address fleet = LibAuthoriserInvariants.STOX_PROD_AUTHORISER;
        forkPreSwap();
        certify();
        assertUnauthorized(depositCall(signer), signer, keccak256("DEPOSIT"));

        sendAsSafe();

        // With the fleet grants the signer holds at `PRE_SWAP_BLOCK`.
        assertTrue(IAccessControl(fleet).hasRole(keccak256("DEPOSIT"), signer), "fleet DEPOSIT");
        assertTrue(IAccessControl(fleet).hasRole(keccak256("WITHDRAW"), signer), "fleet WITHDRAW");
        depositAndWithdraw(signer);

        // After the revoke, the vault-direct deposit reverts on the fleet
        // authoriser, as it does for every other fleet token.
        vm.startPrank(LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK);
        IAccessControl(fleet).revokeRole(keccak256("DEPOSIT"), signer);
        IAccessControl(fleet).revokeRole(keccak256("WITHDRAW"), signer);
        vm.stopPrank();
        assertUnauthorized(depositCall(signer), signer, keccak256("DEPOSIT"));
    }

    /// After the Safe transaction the fleet authoriser's CERTIFY holders, the
    /// Safe and the service signer, can certify tQSEP.
    function testFleetCertifiersCertifyAfterTheSwap() external {
        forkPreSwap();
        sendAsSafe();
        vm.prank(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
        vault.certify(block.timestamp + 1 days, false, "");
        assertFalse(vault.isCertificationExpired(), "certified by the Safe");

        vm.prank(LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C);
        vault.certify(block.timestamp + 2 days, false, "");
        assertFalse(vault.isCertificationExpired(), "certified by the service signer");
    }
}
