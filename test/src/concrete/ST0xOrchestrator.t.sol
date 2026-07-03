// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {ST0xOrchestrator} from "../../../src/concrete/ST0xOrchestrator.sol";
import {IMintRecipient} from "../../../src/interface/IMintRecipient.sol";
import {IST0xVaultBeaconSet} from "../../../src/interface/IST0xVaultBeaconSet.sol";
import {LibProdDeployV4} from "../../../src/lib/LibProdDeployV4.sol";

import {Initializable} from "@openzeppelin-contracts-upgradeable-5.6.1/proxy/utils/Initializable.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {IERC1155} from "@openzeppelin-contracts-5.6.1/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin-contracts-5.6.1/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin-contracts-5.6.1/utils/introspection/IERC165.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin-contracts-5.6.1/proxy/beacon/BeaconProxy.sol";
import {IERC1271} from "@openzeppelin-contracts-5.6.1/interfaces/IERC1271.sol";
import {OffchainAssetReceiptVault} from "rain-vats-0.1.6/src/concrete/vault/OffchainAssetReceiptVault.sol";
import {ReceiptVault} from "rain-vats-0.1.6/src/abstract/ReceiptVault.sol";

/// @dev Comprehensive unit + fuzz tests for the SINGLETON `ST0xOrchestrator`.
/// All external dependencies (vault, receipt, ERC-20 shares, the production
/// beacon set) are mocked via `vm.mockCall` against fixed addresses — no
/// forking, no real vault deployment. The orchestrator is deployed behind a
/// real `UpgradeableBeacon` + `BeaconProxy`.
///
/// Each "token" in the singleton model is just a mock vault address on which
/// we mock the vault selectors (`receipt()`, `highwaterId()`, `mint`,
/// `redeem`), the ERC-20 selectors (`transfer`, `transferFrom`), and — on the
/// associated receipt address — the ERC-1155 `balanceOf`.
contract ST0xOrchestratorTest is Test {
    /// Canonical placeholder vault ("token") + receipt addresses. Each is a
    /// distinct, code-less address that we mock every relevant selector on.
    address internal constant TOKEN = address(0xAA17);
    address internal constant RECEIPT_ADDR = address(0xEEC1D7);

    /// A second token to prove per-token pointer independence.
    address internal constant TOKEN2 = address(0xBB28);
    address internal constant RECEIPT_ADDR2 = address(0xEEC1D8);

    /// A canonical non-orchestrator counterparty. Distinct from
    /// `address(this)` so the "transferFrom" branch is exercised.
    address internal constant BOB = address(0xB0B);

    /// Default admin passed to `initialize`.
    address internal constant OWNER = address(0x0FFCE);

    /// The vault-version guard reads these fixed production addresses.
    address internal constant DEPLOYER =
        LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_RAIN_VATS_0_1_6;
    address internal constant VAULT_BEACON = address(0xBEAC04);
    address internal constant RECEIPT_BEACON = address(0xBEAC12);
    address internal constant EXPECTED_VAULT_IMPL = LibProdDeployV4.STOX_RECEIPT_VAULT_RAIN_VATS_0_1_6;
    address internal constant EXPECTED_RECEIPT_IMPL = LibProdDeployV4.STOX_RECEIPT_RAIN_VATS_0_1_6;

    /// Storage-slot pre-image constant kept for cross-checking against source.
    bytes32 internal constant EXPECTED_MAIN_STORAGE_LOCATION =
        0x4bb94ceb743cdbfc320393e9b6fac11d883b2f90ac89bce731e459177c5be700;

    ST0xOrchestrator internal impl;
    ST0xOrchestrator internal orchestrator;

    function setUp() public {
        impl = new ST0xOrchestrator();
        orchestrator = _deployProxy(OWNER);
        _makeGuardPass();
        _mockVaultTopology(TOKEN, RECEIPT_ADDR);
        _mockVaultTopology(TOKEN2, RECEIPT_ADDR2);
    }

    // ------------------------------------------------------------------ //
    //                            Test helpers                            //
    // ------------------------------------------------------------------ //

    /// Deploy a fresh beacon + proxy pair pointing at `impl`, initialised
    /// with `owner`.
    function _deployProxy(address owner) internal returns (ST0xOrchestrator) {
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), address(this));
        bytes memory initData = abi.encodeCall(ST0xOrchestrator.initialize, (owner));
        BeaconProxy proxy = new BeaconProxy(address(beacon), initData);
        return ST0xOrchestrator(payable(address(proxy)));
    }

    /// Make the vault-logic version guard PASS: the deployer resolves each
    /// beacon and each beacon reports the expected implementation.
    function _makeGuardPass() internal {
        vm.mockCall(
            DEPLOYER,
            abi.encodeWithSelector(IST0xVaultBeaconSet.iOffchainAssetReceiptVaultBeacon.selector),
            abi.encode(VAULT_BEACON)
        );
        vm.mockCall(
            DEPLOYER, abi.encodeWithSelector(IST0xVaultBeaconSet.iReceiptBeacon.selector), abi.encode(RECEIPT_BEACON)
        );
        vm.mockCall(
            VAULT_BEACON, abi.encodeWithSelector(IBeacon.implementation.selector), abi.encode(EXPECTED_VAULT_IMPL)
        );
        vm.mockCall(
            RECEIPT_BEACON, abi.encodeWithSelector(IBeacon.implementation.selector), abi.encode(EXPECTED_RECEIPT_IMPL)
        );
    }

    /// Break the vault guard on the vault-impl leg (receipt leg is checked
    /// second, so a broken vault impl surfaces `VaultLogicMismatch`).
    function _makeGuardFailVault() internal {
        vm.mockCall(VAULT_BEACON, abi.encodeWithSelector(IBeacon.implementation.selector), abi.encode(address(0xDEAD)));
    }

    /// Break the vault guard on the receipt-impl leg only (vault leg still
    /// passes, so this surfaces `ReceiptLogicMismatch`).
    function _makeGuardFailReceipt() internal {
        vm.mockCall(
            RECEIPT_BEACON, abi.encodeWithSelector(IBeacon.implementation.selector), abi.encode(address(0xDEAD))
        );
    }

    /// Mock a token's static vault topology: `receipt()` returns its receipt.
    function _mockVaultTopology(address token, address receipt_) internal {
        vm.mockCall(token, abi.encodeWithSelector(ReceiptVault.receipt.selector), abi.encode(receipt_));
    }

    /// Mock `highwaterId()` for a token.
    function _mockHighwater(address token, uint256 hw) internal {
        vm.mockCall(token, abi.encodeWithSelector(OffchainAssetReceiptVault.highwaterId.selector), abi.encode(hw));
    }

    /// Mock the orchestrator's receipt balance at `id`.
    function _mockBalance(address receipt_, uint256 id, uint256 bal) internal {
        vm.mockCall(
            receipt_, abi.encodeWithSelector(IERC1155.balanceOf.selector, address(orchestrator), id), abi.encode(bal)
        );
    }

    /// Mock a redeem call at `id` for `shares`.
    function _mockRedeem(address token, uint256 shares, uint256 id, bytes memory info) internal {
        vm.mockCall(
            token,
            abi.encodeWithSelector(
                ReceiptVault.redeem.selector, shares, address(orchestrator), address(orchestrator), id, info
            ),
            abi.encode(shares)
        );
    }

    /// Mock the token-as-ERC20 transfer / transferFrom to succeed.
    function _mockERC20(address token) internal {
        vm.mockCall(token, abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
        vm.mockCall(token, abi.encodeWithSelector(IERC20.transferFrom.selector), abi.encode(true));
    }

    /// Grant a role to `who` via OWNER (reads the role first so the
    /// `vm.prank` isn't consumed by the view).
    function _grant(bytes32 role, address who) internal {
        vm.prank(OWNER);
        orchestrator.grantRole(role, who);
    }

    /// Encode `mint` data: `abi.encode(signature, nonce, receiptInformation)`.
    function _mintData(bytes memory sig, bytes32 nonce, bytes memory info) internal pure returns (bytes memory) {
        return abi.encode(sig, nonce, info);
    }

    // ------------------------------------------------------------------ //
    //                     Storage-layout constant check                  //
    // ------------------------------------------------------------------ //

    function testStorageLocationConstant() external pure {
        bytes32 expected =
            keccak256(abi.encode(uint256(keccak256("st0x.orchestrator.main")) - 1)) & ~bytes32(uint256(0xff));
        assertEq(expected, EXPECTED_MAIN_STORAGE_LOCATION, "MAIN_STORAGE_LOCATION formula mismatch");
    }

    // ------------------------------------------------------------------ //
    //                       Constructor / initialize                     //
    // ------------------------------------------------------------------ //

    /// The constructor disables initializers on the raw implementation.
    function testConstructorDisablesInitializers() external {
        ST0xOrchestrator raw = new ST0xOrchestrator();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        raw.initialize(OWNER);
    }

    function testInitializeGrantsAdmin() external view {
        assertTrue(orchestrator.hasRole(orchestrator.DEFAULT_ADMIN_ROLE(), OWNER), "owner missing admin role");
    }

    function testInitializeZeroOwnerReverts() external {
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), address(this));
        bytes memory initData = abi.encodeCall(ST0xOrchestrator.initialize, (address(0)));
        vm.expectRevert(ST0xOrchestrator.ZeroOwner.selector);
        new BeaconProxy(address(beacon), initData);
    }

    function testDoubleInitializeReverts() external {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        orchestrator.initialize(OWNER);
    }

    function testFuzzInitializeGrantsAdmin(address owner) external {
        vm.assume(owner != address(0));
        ST0xOrchestrator o = _deployProxy(owner);
        assertTrue(o.hasRole(o.DEFAULT_ADMIN_ROLE(), owner));
    }

    // ------------------------------------------------------------------ //
    //                               Roles                                //
    // ------------------------------------------------------------------ //

    function testRolesAreDistinct() external view {
        assertTrue(orchestrator.MINT_ROLE() != orchestrator.BURN_ROLE());
        assertTrue(orchestrator.MINT_ROLE() != orchestrator.EMERGENCY_ROLE());
        assertTrue(orchestrator.BURN_ROLE() != orchestrator.EMERGENCY_ROLE());
        assertEq(orchestrator.MINT_ROLE(), keccak256("MINT"));
        assertEq(orchestrator.BURN_ROLE(), keccak256("BURN"));
        assertEq(orchestrator.EMERGENCY_ROLE(), keccak256("EMERGENCY"));
    }

    function testFuzzMintUnauthorized(address caller) external {
        vm.assume(!orchestrator.hasRole(orchestrator.MINT_ROLE(), caller));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, orchestrator.MINT_ROLE()
            )
        );
        vm.prank(caller);
        orchestrator.mint(TOKEN, BOB, 1, _mintData("", bytes32(0), ""));
    }

    function testFuzzBurnUnauthorized(address caller) external {
        vm.assume(!orchestrator.hasRole(orchestrator.BURN_ROLE(), caller));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, orchestrator.BURN_ROLE()
            )
        );
        vm.prank(caller);
        orchestrator.burn(TOKEN, BOB, 1, "");
    }

    function testFuzzSetBurnIndexUnauthorized(address caller, uint256 newIndex) external {
        vm.assume(!orchestrator.hasRole(orchestrator.EMERGENCY_ROLE(), caller));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, orchestrator.EMERGENCY_ROLE()
            )
        );
        vm.prank(caller);
        orchestrator.setBurnIndex(TOKEN, newIndex);
    }

    function testFuzzWithdrawSharesUnauthorized(address caller) external {
        vm.assume(!orchestrator.hasRole(orchestrator.EMERGENCY_ROLE(), caller));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, orchestrator.EMERGENCY_ROLE()
            )
        );
        vm.prank(caller);
        orchestrator.withdrawShares(TOKEN, 1, BOB);
    }

    function testAdminCanGrantAndRevokeEachRole() external {
        bytes32[3] memory roles = [orchestrator.MINT_ROLE(), orchestrator.BURN_ROLE(), orchestrator.EMERGENCY_ROLE()];
        for (uint256 i = 0; i < roles.length; i++) {
            _grant(roles[i], BOB);
            assertTrue(orchestrator.hasRole(roles[i], BOB));
            vm.prank(OWNER);
            orchestrator.revokeRole(roles[i], BOB);
            assertFalse(orchestrator.hasRole(roles[i], BOB));
        }
    }

    /// A MINT_ROLE holder canNOT setBurnIndex or withdraw (EMERGENCY-gated).
    function testMintHolderCannotEmergency() external {
        _grant(orchestrator.MINT_ROLE(), BOB);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, BOB, orchestrator.EMERGENCY_ROLE()
            )
        );
        vm.prank(BOB);
        orchestrator.setBurnIndex(TOKEN, 5);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, BOB, orchestrator.EMERGENCY_ROLE()
            )
        );
        vm.prank(BOB);
        orchestrator.withdrawShares(TOKEN, 1, BOB);
    }

    /// An EMERGENCY_ROLE holder cannot mint or burn.
    function testEmergencyHolderCannotMintOrBurn() external {
        _grant(orchestrator.EMERGENCY_ROLE(), BOB);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, BOB, orchestrator.MINT_ROLE()
            )
        );
        vm.prank(BOB);
        orchestrator.mint(TOKEN, BOB, 1, _mintData("", bytes32(0), ""));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, BOB, orchestrator.BURN_ROLE()
            )
        );
        vm.prank(BOB);
        orchestrator.burn(TOKEN, BOB, 1, "");
    }

    // ------------------------------------------------------------------ //
    //                               mint()                               //
    // ------------------------------------------------------------------ //

    /// Set up the vault-side mocks for a mint that mints `amount` and returns
    /// shares. Highwater arbitrary (mint doesn't walk).
    function _prepMint(address token, uint256 hw, bytes memory info) internal {
        _mockHighwater(token, hw);
        _mockERC20(token);
        vm.mockCall(
            token,
            abi.encodeWithSelector(ReceiptVault.mint.selector, uint256(0), address(orchestrator), uint256(0), info),
            abi.encode(uint256(0))
        );
    }

    /// (a) ECDSA signature: `to` is an EOA whose key signs the digest.
    function testMintWithEcdsaSignature() external {
        (address eoa, uint256 pk) = makeAddrAndKey("recipient");
        _grant(orchestrator.MINT_ROLE(), address(this));
        uint256 amount = 500;
        bytes32 nonce = keccak256("n1");
        bytes memory info = hex"1234";

        _mockHighwater(TOKEN, 0);
        _mockERC20(TOKEN);
        vm.mockCall(
            TOKEN,
            abi.encodeWithSelector(ReceiptVault.mint.selector, amount, address(orchestrator), uint256(0), info),
            abi.encode(amount)
        );

        bytes32 digest = orchestrator.mintAuthDigest(TOKEN, eoa, amount, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        // vault.mint called with (amount, orchestrator, 0, info).
        vm.expectCall(
            TOKEN, abi.encodeWithSelector(ReceiptVault.mint.selector, amount, address(orchestrator), uint256(0), info)
        );
        // then token.transfer(to, amount).
        vm.expectCall(TOKEN, abi.encodeWithSelector(IERC20.transfer.selector, eoa, amount));

        vm.expectEmit(true, true, true, true, address(orchestrator));
        emit ST0xOrchestrator.Minted(address(this), TOKEN, eoa, amount, nonce);
        orchestrator.mint(TOKEN, eoa, amount, _mintData(sig, nonce, info));
    }

    /// (b) EIP-1271: `to` is a contract returning the 1271 magic value.
    function testMintWith1271() external {
        _grant(orchestrator.MINT_ROLE(), address(this));
        uint256 amount = 100;
        bytes32 nonce = keccak256("n2");
        bytes memory info = "";

        Mock1271 recipient = new Mock1271(true);
        _mockHighwater(TOKEN, 0);
        _mockERC20(TOKEN);
        vm.mockCall(
            TOKEN,
            abi.encodeWithSelector(ReceiptVault.mint.selector, amount, address(orchestrator), uint256(0), info),
            abi.encode(amount)
        );
        // Any non-empty signature triggers the 1271 path since `to` is a contract.
        bytes memory sig = hex"deadbeef";

        vm.expectEmit(true, true, true, true, address(orchestrator));
        emit ST0xOrchestrator.Minted(address(this), TOKEN, address(recipient), amount, nonce);
        orchestrator.mint(TOKEN, address(recipient), amount, _mintData(sig, nonce, info));
    }

    function testMint1271RejectReverts() external {
        _grant(orchestrator.MINT_ROLE(), address(this));
        Mock1271 recipient = new Mock1271(false);
        _prepMint(TOKEN, 0, "");
        vm.expectRevert(ST0xOrchestrator.BadRecipientSignature.selector);
        orchestrator.mint(TOKEN, address(recipient), 100, _mintData(hex"deadbeef", keccak256("x"), ""));
    }

    /// (c) Callback: empty signature; `to` implements IMintRecipient.
    function testMintWithCallback() external {
        _grant(orchestrator.MINT_ROLE(), address(this));
        uint256 amount = 250;
        bytes32 nonce = keccak256("n3");
        bytes memory info = hex"abcd";

        MockRecipient recipient = new MockRecipient(true);
        _mockHighwater(TOKEN, 0);
        _mockERC20(TOKEN);
        vm.mockCall(
            TOKEN,
            abi.encodeWithSelector(ReceiptVault.mint.selector, amount, address(orchestrator), uint256(0), info),
            abi.encode(amount)
        );

        bytes32 digest = orchestrator.mintAuthDigest(TOKEN, address(recipient), amount, nonce);
        vm.expectCall(address(recipient), abi.encodeWithSelector(IMintRecipient.authorizeMint.selector, digest));

        vm.expectEmit(true, true, true, true, address(orchestrator));
        emit ST0xOrchestrator.Minted(address(this), TOKEN, address(recipient), amount, nonce);
        orchestrator.mint(TOKEN, address(recipient), amount, _mintData("", nonce, info));
    }

    function testMintCallbackWrongValueReverts() external {
        _grant(orchestrator.MINT_ROLE(), address(this));
        MockRecipient recipient = new MockRecipient(false);
        _prepMint(TOKEN, 0, "");
        vm.expectRevert(abi.encodeWithSelector(ST0xOrchestrator.RecipientCallbackRejected.selector, address(recipient)));
        orchestrator.mint(TOKEN, address(recipient), 100, _mintData("", keccak256("x"), ""));
    }

    /// Signature present but recovers to a different address → BadRecipientSignature.
    function testMintBadSignatureReverts() external {
        (address eoa,) = makeAddrAndKey("recipient");
        (, uint256 wrongPk) = makeAddrAndKey("someone-else");
        _grant(orchestrator.MINT_ROLE(), address(this));
        uint256 amount = 500;
        bytes32 nonce = keccak256("n1");
        _prepMint(TOKEN, 0, "");

        bytes32 digest = orchestrator.mintAuthDigest(TOKEN, eoa, amount, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectRevert(ST0xOrchestrator.BadRecipientSignature.selector);
        orchestrator.mint(TOKEN, eoa, amount, _mintData(sig, nonce, ""));
    }

    function testMintZeroAmountReverts() external {
        _grant(orchestrator.MINT_ROLE(), address(this));
        vm.expectRevert(ST0xOrchestrator.ZeroAmount.selector);
        orchestrator.mint(TOKEN, BOB, 0, _mintData("", bytes32(0), ""));
    }

    /// Nonce/digest replay: identical (token,to,amount,nonce) twice reverts.
    function testMintReplayReverts() external {
        (address eoa, uint256 pk) = makeAddrAndKey("recipient");
        _grant(orchestrator.MINT_ROLE(), address(this));
        uint256 amount = 500;
        bytes32 nonce = keccak256("n1");
        _prepMintExact(TOKEN, amount, "");

        bytes32 digest = orchestrator.mintAuthDigest(TOKEN, eoa, amount, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        orchestrator.mint(TOKEN, eoa, amount, _mintData(sig, nonce, ""));
        assertTrue(orchestrator.mintAuthUsed(digest));

        vm.expectRevert(abi.encodeWithSelector(ST0xOrchestrator.MintAuthReplayed.selector, digest));
        orchestrator.mint(TOKEN, eoa, amount, _mintData(sig, nonce, ""));
    }

    /// A different amount with the SAME nonce is NOT blocked — replay is
    /// per-digest and the digest binds amount too.
    function testMintDifferentAmountSameNonceNotBlocked() external {
        (address eoa, uint256 pk) = makeAddrAndKey("recipient");
        _grant(orchestrator.MINT_ROLE(), address(this));
        bytes32 nonce = keccak256("n1");
        _mockHighwater(TOKEN, 0);
        _mockERC20(TOKEN);
        vm.mockCall(TOKEN, abi.encodeWithSelector(ReceiptVault.mint.selector), abi.encode(uint256(0)));

        // Mint amount 500.
        bytes32 d1 = orchestrator.mintAuthDigest(TOKEN, eoa, 500, nonce);
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(pk, d1);
        orchestrator.mint(TOKEN, eoa, 500, _mintData(abi.encodePacked(r1, s1, v1), nonce, ""));

        // Same nonce, amount 600 → different digest → succeeds.
        bytes32 d2 = orchestrator.mintAuthDigest(TOKEN, eoa, 600, nonce);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(pk, d2);
        orchestrator.mint(TOKEN, eoa, 600, _mintData(abi.encodePacked(r2, s2, v2), nonce, ""));
        assertTrue(orchestrator.mintAuthUsed(d2));
    }

    function testMintVaultGuardFailReverts() external {
        _grant(orchestrator.MINT_ROLE(), address(this));
        _makeGuardFailVault();
        vm.expectRevert(
            abi.encodeWithSelector(ST0xOrchestrator.VaultLogicMismatch.selector, EXPECTED_VAULT_IMPL, address(0xDEAD))
        );
        orchestrator.mint(TOKEN, BOB, 1, _mintData("", bytes32(0), ""));
    }

    function testMintReceiptGuardFailReverts() external {
        _grant(orchestrator.MINT_ROLE(), address(this));
        _makeGuardFailReceipt();
        vm.expectRevert(
            abi.encodeWithSelector(
                ST0xOrchestrator.ReceiptLogicMismatch.selector, EXPECTED_RECEIPT_IMPL, address(0xDEAD)
            )
        );
        orchestrator.mint(TOKEN, BOB, 1, _mintData("", bytes32(0), ""));
    }

    /// First mint of a token lazily seeds nextBurnReceiptId to highwater+1
    /// and emits TokenSeeded.
    function testMintFirstTouchSeedsToken() external {
        (address eoa, uint256 pk) = makeAddrAndKey("recipient");
        _grant(orchestrator.MINT_ROLE(), address(this));
        uint256 amount = 500;
        bytes32 nonce = keccak256("seed");
        _mockHighwater(TOKEN, 41);
        _mockERC20(TOKEN);
        vm.mockCall(TOKEN, abi.encodeWithSelector(ReceiptVault.mint.selector), abi.encode(amount));

        bytes32 digest = orchestrator.mintAuthDigest(TOKEN, eoa, amount, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);

        assertFalse(orchestrator.tokenSeeded(TOKEN));
        vm.expectEmit(true, false, false, true, address(orchestrator));
        emit ST0xOrchestrator.TokenSeeded(TOKEN, 42);
        orchestrator.mint(TOKEN, eoa, amount, _mintData(abi.encodePacked(r, s, v), nonce, ""));
        assertTrue(orchestrator.tokenSeeded(TOKEN));
        assertEq(orchestrator.nextBurnReceiptId(TOKEN), 42);
    }

    /// Helper: mock vault.mint for the exact `amount` (for replay test where
    /// two mints of the same amount fire).
    function _prepMintExact(address token, uint256 amount, bytes memory info) internal {
        _mockHighwater(token, 0);
        _mockERC20(token);
        vm.mockCall(
            token,
            abi.encodeWithSelector(ReceiptVault.mint.selector, amount, address(orchestrator), uint256(0), info),
            abi.encode(amount)
        );
    }

    // ------------------------------------------------------------------ //
    //                               burn()                               //
    // ------------------------------------------------------------------ //

    /// Seed a token's pointer to `idx` via EMERGENCY setBurnIndex so walk
    /// tests can lay receipts from a known base.
    function _seedPointer(address token, uint256 idx) internal {
        _grant(orchestrator.EMERGENCY_ROLE(), address(this));
        orchestrator.setBurnIndex(token, idx);
    }

    function testBurnZeroAmountReverts() external {
        _grant(orchestrator.BURN_ROLE(), address(this));
        vm.expectRevert(ST0xOrchestrator.ZeroAmount.selector);
        orchestrator.burn(TOKEN, BOB, 0, "");
    }

    function testBurnVaultGuardFailReverts() external {
        _grant(orchestrator.BURN_ROLE(), address(this));
        _makeGuardFailVault();
        vm.expectRevert(
            abi.encodeWithSelector(ST0xOrchestrator.VaultLogicMismatch.selector, EXPECTED_VAULT_IMPL, address(0xDEAD))
        );
        orchestrator.burn(TOKEN, BOB, 1, "");
    }

    /// Single receipt exact drain: pointer advances by 1. from != orchestrator
    /// → pulls via transferFrom.
    function testBurnSingleReceiptExactDrain() external {
        _grant(orchestrator.BURN_ROLE(), address(this));
        _seedPointer(TOKEN, 0);
        uint256 amount = 300;
        _mockHighwater(TOKEN, 1);
        _mockERC20(TOKEN);
        _mockBalance(RECEIPT_ADDR, 0, amount);
        _mockRedeem(TOKEN, amount, 0, "");

        vm.expectCall(TOKEN, abi.encodeWithSelector(IERC20.transferFrom.selector, BOB, address(orchestrator), amount));
        vm.expectCall(
            TOKEN,
            abi.encodeWithSelector(
                ReceiptVault.redeem.selector, amount, address(orchestrator), address(orchestrator), uint256(0), ""
            )
        );
        vm.expectEmit(true, true, true, true, address(orchestrator));
        emit ST0xOrchestrator.Burned(address(this), TOKEN, BOB, amount, 0, 1);
        orchestrator.burn(TOKEN, BOB, amount, "");
        assertEq(orchestrator.nextBurnReceiptId(TOKEN), 1);
    }

    /// from == orchestrator skips the transferFrom pull.
    function testBurnFromSelfSkipsPull() external {
        _grant(orchestrator.BURN_ROLE(), address(this));
        _seedPointer(TOKEN, 0);
        uint256 amount = 300;
        _mockHighwater(TOKEN, 1);
        _mockBalance(RECEIPT_ADDR, 0, amount);
        _mockRedeem(TOKEN, amount, 0, "");
        // No transferFrom mock; a call would revert. Assert none happens.
        orchestrator.burn(TOKEN, address(orchestrator), amount, "");
        assertEq(orchestrator.nextBurnReceiptId(TOKEN), 1);
    }

    /// Zero-balance skip: id 0 empty, id 1 empty, id 2 covers.
    function testBurnZeroBalanceSkip() external {
        _grant(orchestrator.BURN_ROLE(), address(this));
        _seedPointer(TOKEN, 0);
        uint256 amount = 300;
        _mockHighwater(TOKEN, 5);
        _mockERC20(TOKEN);
        _mockBalance(RECEIPT_ADDR, 0, 0);
        _mockBalance(RECEIPT_ADDR, 1, 0);
        _mockBalance(RECEIPT_ADDR, 2, amount);
        _mockRedeem(TOKEN, amount, 2, "");

        vm.expectEmit(true, true, true, true, address(orchestrator));
        emit ST0xOrchestrator.Burned(address(this), TOKEN, BOB, amount, 0, 3);
        orchestrator.burn(TOKEN, BOB, amount, "");
        assertEq(orchestrator.nextBurnReceiptId(TOKEN), 3);
    }

    /// Multi-receipt sequential: id0=100, id1=200 → drain both, pointer→2.
    function testBurnMultiReceiptSequential() external {
        _grant(orchestrator.BURN_ROLE(), address(this));
        _seedPointer(TOKEN, 0);
        _mockHighwater(TOKEN, 3);
        _mockERC20(TOKEN);
        _mockBalance(RECEIPT_ADDR, 0, 100);
        _mockBalance(RECEIPT_ADDR, 1, 200);
        _mockRedeem(TOKEN, 100, 0, "");
        _mockRedeem(TOKEN, 200, 1, "");

        vm.expectCall(
            TOKEN,
            abi.encodeWithSelector(
                ReceiptVault.redeem.selector, uint256(100), address(orchestrator), address(orchestrator), uint256(0), ""
            )
        );
        vm.expectCall(
            TOKEN,
            abi.encodeWithSelector(
                ReceiptVault.redeem.selector, uint256(200), address(orchestrator), address(orchestrator), uint256(1), ""
            )
        );
        vm.expectEmit(true, true, true, true, address(orchestrator));
        emit ST0xOrchestrator.Burned(address(this), TOKEN, BOB, 300, 0, 2);
        orchestrator.burn(TOKEN, BOB, 300, "");
        assertEq(orchestrator.nextBurnReceiptId(TOKEN), 2);
    }

    /// Partial drain parks the pointer AT the id (does not advance).
    function testBurnPartialDrainParksPointer() external {
        _grant(orchestrator.BURN_ROLE(), address(this));
        _seedPointer(TOKEN, 0);
        _mockHighwater(TOKEN, 2);
        _mockERC20(TOKEN);
        // id0 holds 500, burn only 200 → partial, take==200 != bal → park at 0.
        _mockBalance(RECEIPT_ADDR, 0, 500);
        _mockRedeem(TOKEN, 200, 0, "");

        vm.expectEmit(true, true, true, true, address(orchestrator));
        emit ST0xOrchestrator.Burned(address(this), TOKEN, BOB, 200, 0, 0);
        orchestrator.burn(TOKEN, BOB, 200, "");
        assertEq(orchestrator.nextBurnReceiptId(TOKEN), 0, "pointer parked at partially-drained id");
    }

    /// Overshoot: pointer above cap → the walk cannot cover anything →
    /// revert `InsufficientReceipts(token, amount)`. No mint-on-demand.
    function testBurnOvershootReverts() external {
        _grant(orchestrator.BURN_ROLE(), address(this));
        // Seed pointer at 1, cap at 0 → idx(1) > cap(0) immediately.
        _seedPointer(TOKEN, 1);
        uint256 amount = 42;
        _mockERC20(TOKEN);
        _mockHighwater(TOKEN, 0);

        vm.expectRevert(abi.encodeWithSelector(ST0xOrchestrator.InsufficientReceipts.selector, TOKEN, amount));
        orchestrator.burn(TOKEN, BOB, amount, "");

        assertEq(orchestrator.nextBurnReceiptId(TOKEN), 1, "pointer untouched by reverted burn");
    }

    /// Partial-then-insufficient: id1 covers 30 of 50, then idx(2)>cap(1)
    /// with 20 still unburned → the WHOLE burn reverts `InsufficientReceipts`
    /// (the id1 redeem included — no partial state survives).
    function testBurnPartialThenInsufficientReverts() external {
        _grant(orchestrator.BURN_ROLE(), address(this));
        _seedPointer(TOKEN, 0);
        uint256 amount = 50;
        _mockERC20(TOKEN);
        _mockHighwater(TOKEN, 1);

        _mockBalance(RECEIPT_ADDR, 0, 0); // skip
        _mockBalance(RECEIPT_ADDR, 1, 30); // covers 30, leaves 20 unburnable
        _mockRedeem(TOKEN, 30, 1, "");

        vm.expectRevert(abi.encodeWithSelector(ST0xOrchestrator.InsufficientReceipts.selector, TOKEN, 20));
        orchestrator.burn(TOKEN, BOB, amount, "");

        assertEq(orchestrator.nextBurnReceiptId(TOKEN), 0, "pointer untouched by reverted burn");
    }

    /// Two tokens maintain independent pointers.
    function testBurnPerTokenIndependentPointers() external {
        _grant(orchestrator.BURN_ROLE(), address(this));
        _grant(orchestrator.EMERGENCY_ROLE(), address(this));
        orchestrator.setBurnIndex(TOKEN, 0);
        orchestrator.setBurnIndex(TOKEN2, 10);

        _mockHighwater(TOKEN, 1);
        _mockERC20(TOKEN);
        _mockBalance(RECEIPT_ADDR, 0, 100);
        _mockRedeem(TOKEN, 100, 0, "");
        orchestrator.burn(TOKEN, BOB, 100, "");

        assertEq(orchestrator.nextBurnReceiptId(TOKEN), 1);
        assertEq(orchestrator.nextBurnReceiptId(TOKEN2), 10, "token2 pointer untouched");
    }

    /// Fuzz single-receipt burn: pointer moves to startIdx+1.
    function testFuzzBurnSingleReceipt(uint256 startIdx, uint256 amount) external {
        startIdx = bound(startIdx, 0, type(uint256).max - 2);
        amount = bound(amount, 1, type(uint256).max);
        _grant(orchestrator.BURN_ROLE(), address(this));
        _seedPointer(TOKEN, startIdx);

        _mockHighwater(TOKEN, startIdx + 1);
        _mockERC20(TOKEN);
        _mockBalance(RECEIPT_ADDR, startIdx, amount);
        _mockRedeem(TOKEN, amount, startIdx, "");

        vm.expectEmit(true, true, true, true, address(orchestrator));
        emit ST0xOrchestrator.Burned(address(this), TOKEN, BOB, amount, startIdx, startIdx + 1);
        orchestrator.burn(TOKEN, BOB, amount, "");
        assertEq(orchestrator.nextBurnReceiptId(TOKEN), startIdx + 1);
    }

    // ------------------------------------------------------------------ //
    //                          advanceBurnIndex()                        //
    // ------------------------------------------------------------------ //

    /// Permissionless: any caller can advance across zero-balance ids.
    function testFuzzAdvanceBurnIndexPermissionless(address caller) external {
        _seedPointer(TOKEN, 0);
        _mockHighwater(TOKEN, 5);
        _mockBalance(RECEIPT_ADDR, 0, 0);
        _mockBalance(RECEIPT_ADDR, 1, 0);
        _mockBalance(RECEIPT_ADDR, 2, 100); // stop AT first non-zero.

        vm.prank(caller);
        uint256 ret = orchestrator.advanceBurnIndex(TOKEN, 10);
        assertEq(ret, 2, "stops at first non-zero balance");
        assertEq(orchestrator.nextBurnReceiptId(TOKEN), 2);
    }

    /// First touch seeds the token.
    function testAdvanceSeedsOnFirstTouch() external {
        _mockHighwater(TOKEN, 7);
        assertFalse(orchestrator.tokenSeeded(TOKEN));
        vm.expectEmit(true, false, false, true, address(orchestrator));
        emit ST0xOrchestrator.TokenSeeded(TOKEN, 8);
        orchestrator.advanceBurnIndex(TOKEN, 5);
        assertTrue(orchestrator.tokenSeeded(TOKEN));
        // Seeded to 8 which is > cap(7), so no advance / no event beyond seed.
        assertEq(orchestrator.nextBurnReceiptId(TOKEN), 8);
    }

    /// maxIds caps the walk.
    function testAdvanceRespectsMaxIds() external {
        _seedPointer(TOKEN, 0);
        _mockHighwater(TOKEN, 10);
        for (uint256 i = 0; i < 11; i++) {
            _mockBalance(RECEIPT_ADDR, i, 0);
        }
        vm.expectEmit(true, true, false, true, address(orchestrator));
        emit ST0xOrchestrator.BurnIndexAdvanced(address(this), TOKEN, 0, 3);
        uint256 ret = orchestrator.advanceBurnIndex(TOKEN, 3);
        assertEq(ret, 3, "advances exactly maxIds");
        assertEq(orchestrator.nextBurnReceiptId(TOKEN), 3);
    }

    /// Never passes highwaterId + 1: walk stops at cap even with room in maxIds.
    function testAdvanceNeverPassesHighwater() external {
        _seedPointer(TOKEN, 0);
        _mockHighwater(TOKEN, 2);
        _mockBalance(RECEIPT_ADDR, 0, 0);
        _mockBalance(RECEIPT_ADDR, 1, 0);
        _mockBalance(RECEIPT_ADDR, 2, 0);
        uint256 ret = orchestrator.advanceBurnIndex(TOKEN, 100);
        assertEq(ret, 3, "stops one past cap (idx <= cap loop bound)");
        assertEq(orchestrator.nextBurnReceiptId(TOKEN), 3);
    }

    /// maxIds == 0 is a no-op (no event).
    function testAdvanceMaxIdsZeroNoOp() external {
        _seedPointer(TOKEN, 0);
        _mockHighwater(TOKEN, 5);
        uint256 ret = orchestrator.advanceBurnIndex(TOKEN, 0);
        assertEq(ret, 0);
        assertEq(orchestrator.nextBurnReceiptId(TOKEN), 0);
    }

    /// Parked above cap → no-op, no event.
    function testAdvanceParkedAboveCapNoOp() external {
        _seedPointer(TOKEN, 10);
        _mockHighwater(TOKEN, 5);
        uint256 ret = orchestrator.advanceBurnIndex(TOKEN, 100);
        assertEq(ret, 10, "pointer above cap stays put");
        assertEq(orchestrator.nextBurnReceiptId(TOKEN), 10);
    }

    // ------------------------------------------------------------------ //
    //                            setBurnIndex()                          //
    // ------------------------------------------------------------------ //

    function testFuzzSetBurnIndex(uint256 first, uint256 second) external {
        _grant(orchestrator.EMERGENCY_ROLE(), address(this));
        vm.expectEmit(true, false, false, true, address(orchestrator));
        emit ST0xOrchestrator.BurnIndexSet(TOKEN, 0, first);
        orchestrator.setBurnIndex(TOKEN, first);
        assertEq(orchestrator.nextBurnReceiptId(TOKEN), first);
        assertTrue(orchestrator.tokenSeeded(TOKEN));

        vm.expectEmit(true, false, false, true, address(orchestrator));
        emit ST0xOrchestrator.BurnIndexSet(TOKEN, first, second);
        orchestrator.setBurnIndex(TOKEN, second);
        assertEq(orchestrator.nextBurnReceiptId(TOKEN), second);
    }

    // ------------------------------------------------------------------ //
    //                       Emergency sweeps                             //
    // ------------------------------------------------------------------ //

    function testFuzzWithdrawReceipt(uint256 id, uint256 amount, address to) external {
        vm.assume(to != address(0));
        _grant(orchestrator.EMERGENCY_ROLE(), address(this));
        vm.mockCall(RECEIPT_ADDR, abi.encodeWithSelector(IERC1155.safeTransferFrom.selector), abi.encode());
        vm.expectCall(
            RECEIPT_ADDR,
            abi.encodeWithSelector(IERC1155.safeTransferFrom.selector, address(orchestrator), to, id, amount, "")
        );
        vm.expectEmit(true, true, true, true, address(orchestrator));
        emit ST0xOrchestrator.ReceiptsWithdrawn(TOKEN, to, id, amount);
        orchestrator.withdrawReceipt(TOKEN, id, amount, to);
    }

    function testFuzzWithdrawReceiptUnauthorized(address caller) external {
        vm.assume(!orchestrator.hasRole(orchestrator.EMERGENCY_ROLE(), caller));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, orchestrator.EMERGENCY_ROLE()
            )
        );
        vm.prank(caller);
        orchestrator.withdrawReceipt(TOKEN, 0, 1, BOB);
    }

    function testFuzzWithdrawShares(uint256 amount, address to) external {
        vm.assume(to != address(0));
        _grant(orchestrator.EMERGENCY_ROLE(), address(this));
        vm.mockCall(TOKEN, abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
        vm.expectCall(TOKEN, abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        vm.expectEmit(true, true, false, true, address(orchestrator));
        emit ST0xOrchestrator.SharesWithdrawn(TOKEN, to, amount);
        orchestrator.withdrawShares(TOKEN, amount, to);
    }

    function testFuzzSweepERC1155(address erc1155, uint256 id, uint256 amount, address to) external {
        vm.assume(to != address(0));
        vm.assume(erc1155.code.length == 0);
        _grant(orchestrator.EMERGENCY_ROLE(), address(this));
        vm.mockCall(erc1155, abi.encodeWithSelector(IERC1155.safeTransferFrom.selector), abi.encode());
        vm.expectCall(
            erc1155,
            abi.encodeWithSelector(IERC1155.safeTransferFrom.selector, address(orchestrator), to, id, amount, "")
        );
        vm.expectEmit(true, true, true, true, address(orchestrator));
        emit ST0xOrchestrator.ForeignERC1155Swept(erc1155, to, id, amount);
        orchestrator.sweepERC1155(erc1155, id, amount, to);
    }

    /// Malformed `mint` `data` reverts cleanly on the abi.decode.
    function testMintMalformedDataReverts() external {
        _makeGuardPass();
        _grant(orchestrator.MINT_ROLE(), address(this));
        vm.expectRevert();
        orchestrator.mint(TOKEN, BOB, 1, hex"01");
    }

    function testFuzzSweepERC1155Unauthorized(address caller) external {
        vm.assume(!orchestrator.hasRole(orchestrator.EMERGENCY_ROLE(), caller));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, orchestrator.EMERGENCY_ROLE()
            )
        );
        vm.prank(caller);
        orchestrator.sweepERC1155(RECEIPT_ADDR, 0, 1, BOB);
    }

    // ------------------------------------------------------------------ //
    //                       ERC-1155 receiver / 165                      //
    // ------------------------------------------------------------------ //

    function testFuzzOnERC1155Received(address operator, address from, uint256 id, uint256 value, bytes calldata data)
        external
        view
    {
        assertEq(
            orchestrator.onERC1155Received(operator, from, id, value, data), IERC1155Receiver.onERC1155Received.selector
        );
    }

    function testFuzzOnERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external view {
        assertEq(
            orchestrator.onERC1155BatchReceived(operator, from, ids, values, data),
            IERC1155Receiver.onERC1155BatchReceived.selector
        );
    }

    function testSupportsInterface() external view {
        assertTrue(orchestrator.supportsInterface(type(IERC1155Receiver).interfaceId));
        assertTrue(orchestrator.supportsInterface(type(IERC165).interfaceId));
        assertTrue(orchestrator.supportsInterface(type(IAccessControl).interfaceId));
    }

    function testFuzzSupportsInterfaceFalse(bytes4 interfaceId) external view {
        vm.assume(interfaceId != type(IERC1155Receiver).interfaceId);
        vm.assume(interfaceId != type(IERC165).interfaceId);
        vm.assume(interfaceId != type(IAccessControl).interfaceId);
        vm.assume(interfaceId != 0xffffffff);
        assertFalse(orchestrator.supportsInterface(interfaceId));
    }

    // ------------------------------------------------------------------ //
    //                               receive()                            //
    // ------------------------------------------------------------------ //

    function testReceiveEth() external {
        vm.deal(address(this), 1 ether);
        (bool ok,) = payable(address(orchestrator)).call{value: 1 ether}("");
        assertTrue(ok, "orchestrator must accept ETH");
        assertEq(address(orchestrator).balance, 1 ether);
    }

    // ------------------------------------------------------------------ //
    //                       vaultLogicIsExpected view                    //
    // ------------------------------------------------------------------ //

    function testVaultLogicIsExpectedTrue() external view {
        assertTrue(orchestrator.vaultLogicIsExpected());
    }

    function testVaultLogicIsExpectedFalse() external {
        _makeGuardFailVault();
        assertFalse(orchestrator.vaultLogicIsExpected());
    }
}

/// @dev EIP-1271 recipient mock. Returns the magic value when `accept`.
contract Mock1271 is IERC1271 {
    bool internal immutable ACCEPT;

    constructor(bool accept) {
        ACCEPT = accept;
    }

    function isValidSignature(bytes32, bytes memory) external view returns (bytes4) {
        return ACCEPT ? IERC1271.isValidSignature.selector : bytes4(0xffffffff);
    }
}

/// @dev Callback recipient mock. Returns the `authorizeMint` selector when
/// `accept`, else a wrong value.
contract MockRecipient is IMintRecipient {
    bool internal immutable ACCEPT;

    constructor(bool accept) {
        ACCEPT = accept;
    }

    function authorizeMint(bytes32) external view returns (bytes4) {
        return ACCEPT ? IMintRecipient.authorizeMint.selector : bytes4(0xdeadbeef);
    }
}
