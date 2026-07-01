// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {ST0xOrchestrator} from "../../../src/concrete/ST0xOrchestrator.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable-5.6.1/proxy/utils/Initializable.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {IERC1155} from "@openzeppelin-contracts-5.6.1/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin-contracts-5.6.1/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin-contracts-5.6.1/utils/introspection/IERC165.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin-contracts-5.6.1/proxy/beacon/BeaconProxy.sol";
import {OffchainAssetReceiptVault} from "rain-vats-0.1.6/src/concrete/vault/OffchainAssetReceiptVault.sol";
import {ReceiptVault} from "rain-vats-0.1.6/src/abstract/ReceiptVault.sol";

/// @dev Comprehensive unit + fuzz tests for `ST0xOrchestrator`. All external
/// dependencies (vault, receipt, ERC-20 shares) are mocked via `vm.mockCall`
/// against fixed vault / receipt addresses — no forking, no real vault
/// deployment. See parent contract source for the code paths being exercised.
contract ST0xOrchestratorTest is Test {
    /// Canonical placeholders for the vault and receipt addresses. The vault
    /// is a distinct, code-less address that we mock every relevant selector
    /// on; likewise the receipt.
    address internal constant VAULT_ADDR = address(0xAA17);
    address internal constant RECEIPT_ADDR = address(0xEEC1D7);

    /// A canonical non-orchestrator counterparty that appears throughout the
    /// tests. Chosen to be distinct from `address(this)` so the "transfer"
    /// branches are exercised.
    address internal constant BOB = address(0xB0B);

    /// Default admin passed to `initialize`. Used to check role plumbing.
    address internal constant OWNER = address(0x0FFCE);

    /// Storage-slot pre-image constant kept for cross-checking against the
    /// contract source — updated in lockstep if the source changes.
    bytes32 internal constant EXPECTED_MAIN_STORAGE_LOCATION =
        0x4bb94ceb743cdbfc320393e9b6fac11d883b2f90ac89bce731e459177c5be700;

    ST0xOrchestrator internal impl;
    ST0xOrchestrator internal orchestrator;

    function setUp() public {
        impl = new ST0xOrchestrator();
        orchestrator = _deployProxy(VAULT_ADDR, OWNER);
    }

    // ------------------------------------------------------------------ //
    //                            Test helpers                            //
    // ------------------------------------------------------------------ //

    /// Deploy a fresh beacon + proxy pair pointing at `impl`, initialised
    /// with `(vault_, owner)`. Mocks `vault.receipt()` first so the
    /// initializer can read a non-zero receipt address.
    function _deployProxy(address vault_, address owner) internal returns (ST0xOrchestrator) {
        // Mock the vault's `receipt()` view — needed because `initialize`
        // reads it to seed `$.receipt`. Address must be non-zero so later
        // `receipt()` view calls return the right thing.
        vm.mockCall(vault_, abi.encodeWithSelector(ReceiptVault.receipt.selector), abi.encode(RECEIPT_ADDR));

        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), address(this));
        bytes memory initData =
            abi.encodeCall(ST0xOrchestrator.initialize, (OffchainAssetReceiptVault(payable(vault_)), owner));
        BeaconProxy proxy = new BeaconProxy(address(beacon), initData);
        return ST0xOrchestrator(payable(address(proxy)));
    }

    /// Grant `MINT_BURN_ROLE` to `who` via the initialised OWNER.
    /// Reads the role first so `vm.prank(OWNER)` isn't consumed by the view.
    function _grantMintBurn(ST0xOrchestrator o, address who) internal {
        bytes32 role = o.MINT_BURN_ROLE();
        vm.prank(OWNER);
        o.grantRole(role, who);
    }

    // ------------------------------------------------------------------ //
    //                     Storage-layout constant check                  //
    // ------------------------------------------------------------------ //

    /// The `MAIN_STORAGE_LOCATION` constant matches the ERC-7201 formula.
    function testStorageLocationConstant() external pure {
        bytes32 expected =
            keccak256(abi.encode(uint256(keccak256("st0x.orchestrator.main")) - 1)) & ~bytes32(uint256(0xff));
        assertEq(expected, EXPECTED_MAIN_STORAGE_LOCATION, "expected constant off");
    }

    // ------------------------------------------------------------------ //
    //                             Constructor                            //
    // ------------------------------------------------------------------ //

    /// The constructor disables initializers on the raw implementation.
    /// Calling `initialize` on the impl must revert with
    /// `Initializable.InvalidInitialization`.
    function testConstructorDisablesInitializers() external {
        ST0xOrchestrator raw = new ST0xOrchestrator();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        raw.initialize(OffchainAssetReceiptVault(payable(VAULT_ADDR)), OWNER);
    }

    // ------------------------------------------------------------------ //
    //                              initialize                            //
    // ------------------------------------------------------------------ //

    /// `initialize` on a proxy stores the vault + receipt + zero pointer and
    /// grants `DEFAULT_ADMIN_ROLE` to the given owner.
    function testInitialize() external view {
        assertEq(address(orchestrator.vault()), VAULT_ADDR, "vault mismatch");
        assertEq(address(orchestrator.receipt()), RECEIPT_ADDR, "receipt mismatch");
        assertEq(orchestrator.nextBurnReceiptId(), 0, "pointer must start at 0");
        assertTrue(orchestrator.hasRole(orchestrator.DEFAULT_ADMIN_ROLE(), OWNER), "owner missing admin role");
    }

    /// Fuzz vault + owner: initialize sets each field correctly.
    function testFuzzInitialize(address vault_, address owner, address fakeReceipt) external {
        // Deployment path uses `vault.receipt()` which mockCall must serve.
        vm.assume(vault_ != address(0));
        vm.assume(owner != address(0));
        vm.assume(fakeReceipt != address(0));
        // Avoid clashing with the two cheatcode-managed globals and with
        // precompiles (which vm.etch rejects).
        vm.assume(vault_ != address(vm) && fakeReceipt != address(vm));
        vm.assume(uint160(vault_) > 0x10);
        // Force an empty EOA-ish target so `vm.mockCall` doesn't tangle with
        // pre-existing code at these addresses.
        vm.etch(vault_, hex"");
        vm.mockCall(vault_, abi.encodeWithSelector(ReceiptVault.receipt.selector), abi.encode(fakeReceipt));

        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), address(this));
        bytes memory initData =
            abi.encodeCall(ST0xOrchestrator.initialize, (OffchainAssetReceiptVault(payable(vault_)), owner));
        BeaconProxy proxy = new BeaconProxy(address(beacon), initData);
        ST0xOrchestrator o = ST0xOrchestrator(payable(address(proxy)));

        assertEq(address(o.vault()), vault_);
        assertEq(address(o.receipt()), fakeReceipt);
        assertEq(o.nextBurnReceiptId(), 0);
        assertTrue(o.hasRole(o.DEFAULT_ADMIN_ROLE(), owner));
    }

    /// A second `initialize` reverts `InvalidInitialization`.
    function testInitializeSecondCallReverts() external {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        orchestrator.initialize(OffchainAssetReceiptVault(payable(VAULT_ADDR)), OWNER);
    }

    /// `initialize` with `vault == address(0)` reverts `ZeroVault`.
    function testInitializeZeroVaultReverts() external {
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), address(this));
        bytes memory initData =
            abi.encodeCall(ST0xOrchestrator.initialize, (OffchainAssetReceiptVault(payable(address(0))), OWNER));
        vm.expectRevert(ST0xOrchestrator.ZeroVault.selector);
        new BeaconProxy(address(beacon), initData);
    }

    /// `initialize` with `owner == address(0)` reverts `ZeroOwner`.
    function testInitializeZeroOwnerReverts() external {
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), address(this));
        bytes memory initData =
            abi.encodeCall(ST0xOrchestrator.initialize, (OffchainAssetReceiptVault(payable(VAULT_ADDR)), address(0)));
        vm.expectRevert(ST0xOrchestrator.ZeroOwner.selector);
        new BeaconProxy(address(beacon), initData);
    }

    /// `initialize` with a vault whose `receipt()` returns `address(0)`
    /// reverts `ZeroReceipt`.
    function testInitializeZeroReceiptReverts() external {
        address vaultWithZeroReceipt = address(0x1234);
        vm.etch(vaultWithZeroReceipt, hex"");
        vm.mockCall(vaultWithZeroReceipt, abi.encodeWithSelector(ReceiptVault.receipt.selector), abi.encode(address(0)));

        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), address(this));
        bytes memory initData = abi.encodeCall(
            ST0xOrchestrator.initialize, (OffchainAssetReceiptVault(payable(vaultWithZeroReceipt)), OWNER)
        );
        vm.expectRevert(ST0xOrchestrator.ZeroReceipt.selector);
        new BeaconProxy(address(beacon), initData);
    }

    // ------------------------------------------------------------------ //
    //                              mint()                                //
    // ------------------------------------------------------------------ //

    /// Any caller without `MINT_BURN_ROLE` reverts.
    function testFuzzMintUnauthorized(address caller, address to, uint256 amount) external {
        // Caller must genuinely not have MINT_BURN.
        vm.assume(!orchestrator.hasRole(orchestrator.MINT_BURN_ROLE(), caller));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, orchestrator.MINT_BURN_ROLE()
            )
        );
        vm.prank(caller);
        orchestrator.mint(to, amount);
    }

    /// `mint(to != this, amount)` calls `vault.mint` then `vault.safeTransfer(to, amount)`
    /// and emits `Minted(caller, to, amount)`.
    function testMintToOther() external {
        _grantMintBurn(orchestrator, address(this));
        uint256 amount = 12345;

        vm.mockCall(
            VAULT_ADDR,
            abi.encodeWithSelector(ReceiptVault.mint.selector, amount, address(orchestrator), uint256(0), ""),
            abi.encode(amount)
        );
        vm.mockCall(VAULT_ADDR, abi.encodeWithSelector(IERC20.transfer.selector, BOB, amount), abi.encode(true));

        // Expect both external calls in order.
        vm.expectCall(
            VAULT_ADDR,
            abi.encodeWithSelector(ReceiptVault.mint.selector, amount, address(orchestrator), uint256(0), "")
        );
        vm.expectCall(VAULT_ADDR, abi.encodeWithSelector(IERC20.transfer.selector, BOB, amount));

        vm.expectEmit(true, true, false, true, address(orchestrator));
        emit ST0xOrchestrator.Minted(address(this), BOB, amount);
        orchestrator.mint(BOB, amount);
    }

    /// `mint(this, amount)` calls `vault.mint` but does NOT trigger any
    /// share transfer.
    function testMintToSelfNoTransfer() external {
        _grantMintBurn(orchestrator, address(this));
        uint256 amount = 42;

        vm.mockCall(
            VAULT_ADDR,
            abi.encodeWithSelector(ReceiptVault.mint.selector, amount, address(orchestrator), uint256(0), ""),
            abi.encode(amount)
        );
        // Mock the transfer path to revert if hit — proves no transfer call.
        vm.mockCallRevert(
            VAULT_ADDR,
            abi.encodeWithSelector(IERC20.transfer.selector, address(orchestrator), amount),
            abi.encode("must not be called")
        );

        vm.expectCall(
            VAULT_ADDR,
            abi.encodeWithSelector(ReceiptVault.mint.selector, amount, address(orchestrator), uint256(0), "")
        );
        vm.expectEmit(true, true, false, true, address(orchestrator));
        emit ST0xOrchestrator.Minted(address(this), address(orchestrator), amount);
        orchestrator.mint(address(orchestrator), amount);
    }

    /// Fuzz `to` + amount: cover both to-branches and full u256 amount range.
    function testFuzzMint(address to, uint256 amount) external {
        _grantMintBurn(orchestrator, address(this));

        vm.mockCall(
            VAULT_ADDR,
            abi.encodeWithSelector(ReceiptVault.mint.selector, amount, address(orchestrator), uint256(0), ""),
            abi.encode(amount)
        );
        // `to == this` branch skips the transfer; otherwise the mint code
        // calls `vault.transfer(to, amount)`. Register both so either branch
        // has a live mock.
        vm.mockCall(VAULT_ADDR, abi.encodeWithSelector(IERC20.transfer.selector, to, amount), abi.encode(true));

        vm.expectEmit(true, true, false, true, address(orchestrator));
        emit ST0xOrchestrator.Minted(address(this), to, amount);
        orchestrator.mint(to, amount);
    }

    // ------------------------------------------------------------------ //
    //                              burn()                                //
    // ------------------------------------------------------------------ //

    /// Non-holder of `MINT_BURN_ROLE` cannot burn.
    function testFuzzBurnUnauthorized(address caller, address from, uint256 amount) external {
        vm.assume(!orchestrator.hasRole(orchestrator.MINT_BURN_ROLE(), caller));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, orchestrator.MINT_BURN_ROLE()
            )
        );
        vm.prank(caller);
        orchestrator.burn(from, amount);
    }

    /// `burn(from != this)` pulls shares via `safeTransferFrom(from, this, amount)`.
    /// `burn(from == this)` does NOT pull. Verified by both `expectCall` for
    /// the pull path and `mockCallRevert` for the self path.
    function testBurnFromOtherPulls() external {
        _grantMintBurn(orchestrator, address(this));
        uint256 amount = 100;

        // One receipt with enough balance at id 0 covers the whole burn.
        vm.mockCall(VAULT_ADDR, abi.encodeWithSelector(OffchainAssetReceiptVault.highwaterId.selector), abi.encode(1));
        vm.mockCall(
            RECEIPT_ADDR,
            abi.encodeWithSelector(IERC1155.balanceOf.selector, address(orchestrator), uint256(0)),
            abi.encode(amount)
        );
        vm.mockCall(
            VAULT_ADDR,
            abi.encodeWithSelector(
                ReceiptVault.redeem.selector, amount, address(orchestrator), address(orchestrator), uint256(0), ""
            ),
            abi.encode(amount)
        );
        vm.mockCall(
            VAULT_ADDR,
            abi.encodeWithSelector(IERC20.transferFrom.selector, BOB, address(orchestrator), amount),
            abi.encode(true)
        );

        vm.expectCall(
            VAULT_ADDR, abi.encodeWithSelector(IERC20.transferFrom.selector, BOB, address(orchestrator), amount)
        );
        vm.expectEmit(true, true, false, true, address(orchestrator));
        emit ST0xOrchestrator.Burned(address(this), BOB, amount, 0, 1);
        orchestrator.burn(BOB, amount);
        assertEq(orchestrator.nextBurnReceiptId(), 1);
    }

    /// `burn(from == this)` skips the transferFrom pull.
    function testBurnFromSelfNoPull() external {
        _grantMintBurn(orchestrator, address(this));
        uint256 amount = 100;

        vm.mockCall(VAULT_ADDR, abi.encodeWithSelector(OffchainAssetReceiptVault.highwaterId.selector), abi.encode(1));
        vm.mockCall(
            RECEIPT_ADDR,
            abi.encodeWithSelector(IERC1155.balanceOf.selector, address(orchestrator), uint256(0)),
            abi.encode(amount)
        );
        vm.mockCall(
            VAULT_ADDR,
            abi.encodeWithSelector(
                ReceiptVault.redeem.selector, amount, address(orchestrator), address(orchestrator), uint256(0), ""
            ),
            abi.encode(amount)
        );
        vm.mockCallRevert(
            VAULT_ADDR,
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(orchestrator), address(orchestrator), amount),
            abi.encode("must not pull from self")
        );

        vm.expectEmit(true, true, false, true, address(orchestrator));
        emit ST0xOrchestrator.Burned(address(this), address(orchestrator), amount, 0, 1);
        orchestrator.burn(address(orchestrator), amount);
    }

    /// Zero-balance receipts are skipped and idx advances until it finds a
    /// non-zero balance or exhausts the cap.
    function testBurnSkipsZeroBalanceReceipts() external {
        _grantMintBurn(orchestrator, address(this));
        uint256 amount = 50;

        // highwater = 5, only id 3 holds balance covering the whole burn.
        vm.mockCall(VAULT_ADDR, abi.encodeWithSelector(OffchainAssetReceiptVault.highwaterId.selector), abi.encode(5));
        vm.mockCall(
            RECEIPT_ADDR,
            abi.encodeWithSelector(IERC1155.balanceOf.selector, address(orchestrator), uint256(0)),
            abi.encode(0)
        );
        vm.mockCall(
            RECEIPT_ADDR,
            abi.encodeWithSelector(IERC1155.balanceOf.selector, address(orchestrator), uint256(1)),
            abi.encode(0)
        );
        vm.mockCall(
            RECEIPT_ADDR,
            abi.encodeWithSelector(IERC1155.balanceOf.selector, address(orchestrator), uint256(2)),
            abi.encode(0)
        );
        vm.mockCall(
            RECEIPT_ADDR,
            abi.encodeWithSelector(IERC1155.balanceOf.selector, address(orchestrator), uint256(3)),
            abi.encode(amount)
        );
        vm.mockCall(
            VAULT_ADDR,
            abi.encodeWithSelector(
                ReceiptVault.redeem.selector, amount, address(orchestrator), address(orchestrator), uint256(3), ""
            ),
            abi.encode(amount)
        );
        vm.mockCall(
            VAULT_ADDR,
            abi.encodeWithSelector(IERC20.transferFrom.selector, BOB, address(orchestrator), amount),
            abi.encode(true)
        );

        vm.expectEmit(true, true, false, true, address(orchestrator));
        emit ST0xOrchestrator.Burned(address(this), BOB, amount, 0, 4);
        orchestrator.burn(BOB, amount);
        assertEq(orchestrator.nextBurnReceiptId(), 4);
    }

    /// Multiple receipts are consumed in sequence when a single receipt
    /// doesn't cover the amount.
    function testBurnMultipleReceiptsSequential() external {
        _grantMintBurn(orchestrator, address(this));
        uint256 amount = 300;

        // highwater = 3. Balances: id0=100, id1=200 → covers 300 exactly,
        // walk advances to 2 (one past id1 since fully drained).
        vm.mockCall(VAULT_ADDR, abi.encodeWithSelector(OffchainAssetReceiptVault.highwaterId.selector), abi.encode(3));
        vm.mockCall(
            RECEIPT_ADDR,
            abi.encodeWithSelector(IERC1155.balanceOf.selector, address(orchestrator), uint256(0)),
            abi.encode(100)
        );
        vm.mockCall(
            RECEIPT_ADDR,
            abi.encodeWithSelector(IERC1155.balanceOf.selector, address(orchestrator), uint256(1)),
            abi.encode(200)
        );
        vm.mockCall(
            VAULT_ADDR,
            abi.encodeWithSelector(
                ReceiptVault.redeem.selector, uint256(100), address(orchestrator), address(orchestrator), uint256(0), ""
            ),
            abi.encode(uint256(100))
        );
        vm.mockCall(
            VAULT_ADDR,
            abi.encodeWithSelector(
                ReceiptVault.redeem.selector, uint256(200), address(orchestrator), address(orchestrator), uint256(1), ""
            ),
            abi.encode(uint256(200))
        );
        vm.mockCall(
            VAULT_ADDR,
            abi.encodeWithSelector(IERC20.transferFrom.selector, BOB, address(orchestrator), amount),
            abi.encode(true)
        );

        vm.expectCall(
            VAULT_ADDR,
            abi.encodeWithSelector(
                ReceiptVault.redeem.selector, uint256(100), address(orchestrator), address(orchestrator), uint256(0), ""
            )
        );
        vm.expectCall(
            VAULT_ADDR,
            abi.encodeWithSelector(
                ReceiptVault.redeem.selector, uint256(200), address(orchestrator), address(orchestrator), uint256(1), ""
            )
        );
        vm.expectEmit(true, true, false, true, address(orchestrator));
        emit ST0xOrchestrator.Burned(address(this), BOB, amount, 0, 2);
        orchestrator.burn(BOB, amount);
        assertEq(orchestrator.nextBurnReceiptId(), 2);
    }

    /// Partial drain: the last receipt is only partially consumed; idx stays
    /// on it (not advanced) because `take != bal`.
    function testBurnPartialDrainDoesNotAdvance() external {
        _grantMintBurn(orchestrator, address(this));
        uint256 amount = 30;

        vm.mockCall(VAULT_ADDR, abi.encodeWithSelector(OffchainAssetReceiptVault.highwaterId.selector), abi.encode(2));
        vm.mockCall(
            RECEIPT_ADDR,
            abi.encodeWithSelector(IERC1155.balanceOf.selector, address(orchestrator), uint256(0)),
            abi.encode(uint256(100))
        );
        vm.mockCall(
            VAULT_ADDR,
            abi.encodeWithSelector(
                ReceiptVault.redeem.selector, amount, address(orchestrator), address(orchestrator), uint256(0), ""
            ),
            abi.encode(amount)
        );
        vm.mockCall(
            VAULT_ADDR,
            abi.encodeWithSelector(IERC20.transferFrom.selector, BOB, address(orchestrator), amount),
            abi.encode(true)
        );

        vm.expectEmit(true, true, false, true, address(orchestrator));
        emit ST0xOrchestrator.Burned(address(this), BOB, amount, 0, 0);
        orchestrator.burn(BOB, amount);
        // Pointer parked on the same id — the next burn re-reads its balance.
        assertEq(orchestrator.nextBurnReceiptId(), 0);
    }

    /// Overshoot: idx > cap and remaining > 0. Contract mints a fresh
    /// receipt-backed batch, re-reads highwaterId, resumes the walk at the
    /// new cap. Verify `vault.mint(remaining, this, 0, "")` is invoked.
    ///
    /// Sequencing highwaterId across mint requires a stateful vault mock —
    /// `vm.mockCall` returns the same value forever. We deploy a
    /// `_HighwaterFlipper` and use `vm.mockFunction` to route the
    /// `highwaterId` and `mint` selectors on VAULT_ADDR through it; the
    /// flipper bumps `_highwater` on mint, so the subsequent highwaterId
    /// read returns the new cap. See `_HighwaterFlipper` for the mechanic.
    function testBurnOvershootMintsOnDemand() external {
        _grantMintBurn(orchestrator, address(this));
        // Bootstrap the pointer at id=1 so idx (1) > initial cap (0) and the
        // overshoot branch fires on the first while iteration.
        vm.prank(OWNER);
        orchestrator.setBurnIndex(1);

        uint256 amount = 42;

        _HighwaterFlipper flipper = new _HighwaterFlipper();
        flipper.setHighwater(0);

        // Route `highwaterId()` calls on VAULT_ADDR to the flipper.
        vm.mockFunction(VAULT_ADDR, address(flipper), abi.encodePacked(OffchainAssetReceiptVault.highwaterId.selector));
        // Route `mint(...)` calls on VAULT_ADDR to the flipper — its mint
        // bumps the internal highwater, so the subsequent `highwaterId()`
        // returns 1. Match on selector only (prefix), not on args.
        vm.mockFunction(VAULT_ADDR, address(flipper), abi.encodePacked(ReceiptVault.mint.selector));

        // Receipt at the newly-minted id (=1) has enough to cover the burn.
        vm.mockCall(
            RECEIPT_ADDR,
            abi.encodeWithSelector(IERC1155.balanceOf.selector, address(orchestrator), uint256(1)),
            abi.encode(amount)
        );
        vm.mockCall(
            VAULT_ADDR,
            abi.encodeWithSelector(
                ReceiptVault.redeem.selector, amount, address(orchestrator), address(orchestrator), uint256(1), ""
            ),
            abi.encode(amount)
        );
        vm.mockCall(
            VAULT_ADDR,
            abi.encodeWithSelector(IERC20.transferFrom.selector, BOB, address(orchestrator), amount),
            abi.encode(true)
        );

        // Under-hood expected call sequence:
        // 1. transferFrom(BOB, this, amount) — pull shares.
        // 2. highwaterId() → 0 — cap seed.
        // 3. mint(amount, this, 0, "") — mint-on-demand.
        // 4. highwaterId() → 1 — new cap after mint.
        // 5. balanceOf(this, 1) → amount.
        // 6. redeem(amount, this, this, 1, "") — consume.
        // `expectCall` doesn't see mockFunction-delegated calls, so we
        // verify mint fired via the vault's post-state. `mockFunction`
        // delegatecalls into the flipper — storage writes land in
        // VAULT_ADDR's slot 0 (the flipper's `_highwater`), not the
        // flipper's own storage. If mint hadn't been called, the value would
        // remain 0 and the second highwaterId() would return 0, wedging the
        // walk into an infinite loop / gas failure.
        vm.expectEmit(true, true, false, true, address(orchestrator));
        emit ST0xOrchestrator.Burned(address(this), BOB, amount, 1, 2);
        orchestrator.burn(BOB, amount);
        assertEq(orchestrator.nextBurnReceiptId(), 2);
        assertEq(uint256(vm.load(VAULT_ADDR, bytes32(uint256(0)))), 1, "mint should have bumped highwater");
    }

    /// Fuzz burn amount + initial pointer. Uses a single all-covering
    /// receipt at the starting id so the walk drains in one shot; verifies
    /// the pointer moves to `startIdx + 1` and the event carries the right
    /// bounds.
    function testFuzzBurnSingleReceipt(uint256 startIdx, uint256 amount) external {
        // Bound to keep `+ 1` arithmetic safe (contract itself uses unchecked
        // so an actual overflow would just wrap — this stays inside the
        // realistic domain).
        startIdx = bound(startIdx, 0, type(uint256).max - 2);
        // Cap = startIdx + 1, so the walk stays inside the cap.
        _grantMintBurn(orchestrator, address(this));
        if (startIdx != 0) {
            vm.prank(OWNER);
            orchestrator.setBurnIndex(startIdx);
        }

        vm.mockCall(
            VAULT_ADDR, abi.encodeWithSelector(OffchainAssetReceiptVault.highwaterId.selector), abi.encode(startIdx + 1)
        );
        vm.mockCall(
            RECEIPT_ADDR,
            abi.encodeWithSelector(IERC1155.balanceOf.selector, address(orchestrator), startIdx),
            abi.encode(amount)
        );
        // Amount 0 skips redeem entirely (while loop never enters).
        if (amount > 0) {
            vm.mockCall(
                VAULT_ADDR,
                abi.encodeWithSelector(
                    ReceiptVault.redeem.selector, amount, address(orchestrator), address(orchestrator), startIdx, ""
                ),
                abi.encode(amount)
            );
        }
        vm.mockCall(
            VAULT_ADDR,
            abi.encodeWithSelector(IERC20.transferFrom.selector, BOB, address(orchestrator), amount),
            abi.encode(true)
        );

        // Expected: idx=startIdx, take=amount, remaining=0 → loop exits.
        // If amount>0 && amount==bal, `take==bal` bumps idx by 1 → end idx =
        // startIdx+1. If amount==0, the while never runs → end idx =
        // startIdx.
        uint256 expectedEnd = amount == 0 ? startIdx : startIdx + 1;

        vm.expectEmit(true, true, false, true, address(orchestrator));
        emit ST0xOrchestrator.Burned(address(this), BOB, amount, startIdx, expectedEnd);
        orchestrator.burn(BOB, amount);
        assertEq(orchestrator.nextBurnReceiptId(), expectedEnd);
    }

    // ------------------------------------------------------------------ //
    //                          setBurnIndex()                            //
    // ------------------------------------------------------------------ //

    function testFuzzSetBurnIndexUnauthorized(address caller, uint256 newIndex) external {
        vm.assume(!orchestrator.hasRole(orchestrator.DEFAULT_ADMIN_ROLE(), caller));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, orchestrator.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(caller);
        orchestrator.setBurnIndex(newIndex);
    }

    /// Admin can move the pointer forwards and backwards and to
    /// `type(uint256).max`; each call emits `BurnIndexSet(old, new)`.
    function testFuzzSetBurnIndex(uint256 first, uint256 second) external {
        vm.startPrank(OWNER);
        vm.expectEmit(false, false, false, true, address(orchestrator));
        emit ST0xOrchestrator.BurnIndexSet(0, first);
        orchestrator.setBurnIndex(first);
        assertEq(orchestrator.nextBurnReceiptId(), first);

        vm.expectEmit(false, false, false, true, address(orchestrator));
        emit ST0xOrchestrator.BurnIndexSet(first, second);
        orchestrator.setBurnIndex(second);
        assertEq(orchestrator.nextBurnReceiptId(), second);
        vm.stopPrank();
    }

    /// Explicit uint256.max exercise — belt-and-braces above the fuzz.
    function testSetBurnIndexMax() external {
        vm.prank(OWNER);
        orchestrator.setBurnIndex(type(uint256).max);
        assertEq(orchestrator.nextBurnReceiptId(), type(uint256).max);
    }

    // ------------------------------------------------------------------ //
    //                          withdrawReceipt()                         //
    // ------------------------------------------------------------------ //

    function testFuzzWithdrawReceiptUnauthorized(address caller, uint256 id, uint256 amount, address to) external {
        vm.assume(!orchestrator.hasRole(orchestrator.DEFAULT_ADMIN_ROLE(), caller));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, orchestrator.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(caller);
        orchestrator.withdrawReceipt(id, amount, to);
    }

    /// Admin call routes to `receipt.safeTransferFrom(this, to, id, amount, "")`
    /// and emits `ReceiptsWithdrawn(to, id, amount)`.
    function testFuzzWithdrawReceipt(uint256 id, uint256 amount, address to) external {
        vm.mockCall(
            RECEIPT_ADDR,
            abi.encodeWithSelector(IERC1155.safeTransferFrom.selector, address(orchestrator), to, id, amount, ""),
            abi.encode()
        );

        vm.expectCall(
            RECEIPT_ADDR,
            abi.encodeWithSelector(IERC1155.safeTransferFrom.selector, address(orchestrator), to, id, amount, "")
        );
        vm.expectEmit(true, true, false, true, address(orchestrator));
        emit ST0xOrchestrator.ReceiptsWithdrawn(to, id, amount);
        vm.prank(OWNER);
        orchestrator.withdrawReceipt(id, amount, to);
    }

    // ------------------------------------------------------------------ //
    //                          withdrawShares()                          //
    // ------------------------------------------------------------------ //

    function testFuzzWithdrawSharesUnauthorized(address caller, uint256 amount, address to) external {
        vm.assume(!orchestrator.hasRole(orchestrator.DEFAULT_ADMIN_ROLE(), caller));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, orchestrator.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(caller);
        orchestrator.withdrawShares(amount, to);
    }

    function testFuzzWithdrawShares(uint256 amount, address to) external {
        vm.mockCall(VAULT_ADDR, abi.encodeWithSelector(IERC20.transfer.selector, to, amount), abi.encode(true));

        vm.expectCall(VAULT_ADDR, abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        vm.expectEmit(true, false, false, true, address(orchestrator));
        emit ST0xOrchestrator.SharesWithdrawn(to, amount);
        vm.prank(OWNER);
        orchestrator.withdrawShares(amount, to);
    }

    // ------------------------------------------------------------------ //
    //                    ERC-1155 receiver / ERC-165                     //
    // ------------------------------------------------------------------ //

    /// `onERC1155Received` returns the correct selector when called by the
    /// configured receipt token; any inputs are accepted (fuzzed).
    function testFuzzOnERC1155ReceivedFromReceipt(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external {
        vm.prank(RECEIPT_ADDR);
        bytes4 sel = orchestrator.onERC1155Received(operator, from, id, value, data);
        assertEq(sel, IERC1155Receiver.onERC1155Received.selector);
    }

    /// `onERC1155BatchReceived` returns the correct selector from the receipt.
    function testFuzzOnERC1155BatchReceivedFromReceipt(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external {
        vm.prank(RECEIPT_ADDR);
        bytes4 sel = orchestrator.onERC1155BatchReceived(operator, from, ids, values, data);
        assertEq(sel, IERC1155Receiver.onERC1155BatchReceived.selector);
    }

    /// Non-receipt callers are rejected with `UnrecognisedERC1155Source`.
    function testFuzzOnERC1155ReceivedRejectsOthers(
        address caller,
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external {
        vm.assume(caller != RECEIPT_ADDR);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(ST0xOrchestrator.UnrecognisedERC1155Source.selector, caller));
        orchestrator.onERC1155Received(operator, from, id, value, data);
    }

    function testFuzzOnERC1155BatchReceivedRejectsOthers(
        address caller,
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external {
        vm.assume(caller != RECEIPT_ADDR);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(ST0xOrchestrator.UnrecognisedERC1155Source.selector, caller));
        orchestrator.onERC1155BatchReceived(operator, from, ids, values, data);
    }

    /// `supportsInterface` returns true for the three canonical interfaces.
    function testSupportsInterfaceKnown() external view {
        assertTrue(orchestrator.supportsInterface(type(IERC1155Receiver).interfaceId));
        assertTrue(orchestrator.supportsInterface(type(IERC165).interfaceId));
        assertTrue(orchestrator.supportsInterface(type(IAccessControl).interfaceId));
    }

    /// Fuzz other selectors: only interfaceIds that match the three canonical
    /// ones must return true. Everything else is false.
    function testFuzzSupportsInterfaceUnknown(bytes4 selector) external view {
        vm.assume(selector != type(IERC1155Receiver).interfaceId);
        vm.assume(selector != type(IERC165).interfaceId);
        vm.assume(selector != type(IAccessControl).interfaceId);
        assertFalse(orchestrator.supportsInterface(selector));
    }

    // ------------------------------------------------------------------ //
    //                          receive() / ETH                           //
    // ------------------------------------------------------------------ //

    /// The orchestrator accepts arbitrary ETH via `receive()`.
    function testReceiveEth() external {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(orchestrator).call{value: 1 ether}("");
        assertTrue(ok, "receive should accept ETH");
        assertEq(address(orchestrator).balance, 1 ether);
    }

    /// A zero-value send — matches `Address.sendValue(this, 0)` from the
    /// vault's `mint` refund path — must also succeed.
    function testReceiveZeroEth() external {
        (bool ok,) = address(orchestrator).call{value: 0}("");
        assertTrue(ok, "receive should accept zero-value ETH");
    }

    /// Fuzz any callable value.
    function testFuzzReceiveEth(uint96 amount) external {
        vm.deal(address(this), amount);
        (bool ok,) = address(orchestrator).call{value: amount}("");
        assertTrue(ok);
    }

    // ------------------------------------------------------------------ //
    //                     Role admin & role plumbing                     //
    // ------------------------------------------------------------------ //

    /// `MINT_BURN_ROLE`'s admin is `DEFAULT_ADMIN_ROLE`. The admin can grant
    /// and revoke it; a non-admin cannot.
    function testRoleAdminMintBurn() external view {
        assertEq(orchestrator.getRoleAdmin(orchestrator.MINT_BURN_ROLE()), orchestrator.DEFAULT_ADMIN_ROLE());
    }

    /// A non-admin cannot grant `MINT_BURN_ROLE`.
    function testFuzzGrantMintBurnFromNonAdminReverts(address stranger, address grantee) external {
        bytes32 adminRole = orchestrator.DEFAULT_ADMIN_ROLE();
        bytes32 mintBurnRole = orchestrator.MINT_BURN_ROLE();
        vm.assume(!orchestrator.hasRole(adminRole, stranger));
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, adminRole)
        );
        vm.prank(stranger);
        orchestrator.grantRole(mintBurnRole, grantee);
    }

    /// The admin can grant and revoke `MINT_BURN_ROLE`.
    function testFuzzAdminGrantsAndRevokesMintBurn(address grantee) external {
        assertFalse(orchestrator.hasRole(orchestrator.MINT_BURN_ROLE(), grantee));
        vm.startPrank(OWNER);
        orchestrator.grantRole(orchestrator.MINT_BURN_ROLE(), grantee);
        assertTrue(orchestrator.hasRole(orchestrator.MINT_BURN_ROLE(), grantee));
        orchestrator.revokeRole(orchestrator.MINT_BURN_ROLE(), grantee);
        assertFalse(orchestrator.hasRole(orchestrator.MINT_BURN_ROLE(), grantee));
        vm.stopPrank();
    }
}

// ------------------------------------------------------------------ //
//                    Stateful mock helpers                           //
// ------------------------------------------------------------------ //

/// @dev Stateful stand-in used by `testBurnOvershootMintsOnDemand`.
/// Provides a stubbed `highwaterId` that can be mutated between calls, and a
/// `mint` that bumps the highwater by 1 (mirroring the real vault, which
/// mints a fresh receipt id and advances the highwater).
contract _HighwaterFlipper {
    uint256 internal _highwater;

    function setHighwater(uint256 v) external {
        _highwater = v;
    }

    function getHighwater() external view returns (uint256) {
        return _highwater;
    }

    /// Delegated `highwaterId()` — matches the vault's selector.
    function highwaterId() external view returns (uint256) {
        return _highwater;
    }

    /// Delegated `mint(uint256,address,uint256,bytes)` — bumps the flipper's
    /// internal highwater to simulate a fresh receipt id. Payable to match
    /// the vault's signature exactly (`ReceiptVault.mint` is payable).
    function mint(
        uint256 shares,
        address,
        /*receiver*/
        uint256,
        /*mintMinShareRatio*/
        bytes memory /*data*/
    )
        external
        payable
        returns (uint256)
    {
        _highwater += 1;
        return shares;
    }
}
