// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {ST0xOrchestrator} from "../../../src/concrete/ST0xOrchestrator.sol";
import {IMintRecipient} from "../../../src/interface/IMintRecipient.sol";
import {IST0xVaultBeaconSet} from "../../../src/interface/IST0xVaultBeaconSet.sol";
import {
    IST0xOrchestratorV1,
    MintAuthV1,
    MintLimitV1,
    MintLimitOverrideV1,
    Digest
} from "../../../src/interface/IST0xOrchestratorV1.sol";
import {
    LEAKY_BUCKET_LEVEL_MAX,
    LeakyBucketCapacityOverflow
} from "rain-lib-leakybucket-0.1.4/src/lib/LibLeakyBucketCheckpoint.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {ICorporateActionsV1} from "../../../src/interface/ICorporateActionsV1.sol";
import {AmountNotRepresentableAsFloat} from "../../../src/error/ErrMintCapUnits.sol";
import {Float, LibDecimalFloat} from "rain-math-float-0.1.1/src/lib/LibDecimalFloat.sol";
import {Math} from "@openzeppelin-contracts-5.6.1/utils/math/Math.sol";

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
import {Mock1271} from "./Mock1271.sol";
import {MockMintRecipient} from "./MockMintRecipient.sol";
import {ReentrantMintRecipient} from "./ReentrantMintRecipient.sol";
import {ReentrantBurnVault} from "./ReentrantBurnVault.sol";
import {MockManagerRevert1155} from "./MockManagerRevert1155.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-contracts-5.6.1/utils/ReentrancyGuardTransient.sol";
import {OffchainAssetReceiptVault} from "rain-vats-0.1.6/src/concrete/vault/OffchainAssetReceiptVault.sol";
import {ReceiptVault} from "rain-vats-0.1.6/src/abstract/ReceiptVault.sol";
import {IReceiptV3} from "rain-vats-0.1.6/src/interface/IReceiptV3.sol";

/// @dev Comprehensive unit + fuzz tests for the SINGLETON `ST0xOrchestrator`.
/// All external dependencies (vault, receipt, ERC-20 shares, the production
/// beacon set) are mocked via `vm.mockCall` against fixed addresses — no
/// forking, no real vault deployment. The orchestrator is deployed behind a
/// real `UpgradeableBeacon` + `BeaconProxy`.
///
/// Each "token" in the singleton model is just a mock vault address on which
/// we mock the vault selectors (`receipt()`, `highwaterId()`, `mint`,
/// `redeem`), the ERC-20 selectors (`transfer`, `transferFrom`), and — on the
/// associated receipt address — the ERC-1155 `balanceOf` (and, for the
/// receiver-hook tests, `IReceiptV3.manager()`).
contract ST0xOrchestratorTest is Test {
    /// Canonical placeholder vault ("token") + receipt addresses. Each is a
    /// distinct, code-less address that we mock every relevant selector on.
    address internal constant TOKEN = address(0xAA17);
    address internal constant RECEIPT_ADDR = address(0xEEC1D7);

    /// A second token to prove per-token pointer independence.
    address internal constant TOKEN2 = address(0xBB28);
    address internal constant RECEIPT_ADDR2 = address(0xEEC1D8);

    /// A code-less ERC-1155 that is NOT a production receipt (no `manager()`
    /// mocked), for the foreign-sender receiver-hook tests.
    address internal constant FOREIGN_1155 = address(0xF04E16);

    /// A canonical non-orchestrator counterparty. Distinct from
    /// `address(this)` so the "transferFrom" branch is exercised.
    address internal constant BOB = address(0xB0B);

    /// Two distinct `MINT_ROLE` holders, for the mint-cap isolation tests.
    address internal constant MINTER_A = address(0x111A);
    address internal constant MINTER_B = address(0x222B);

    /// Default admin passed to `initialize`.
    address internal constant OWNER = address(0x0FFCE);

    /// The vault-version guard reads these fixed production addresses. The
    /// orchestrator's `_checkVaultLogic` reads the current-release (candidate) pins,
    /// so the mocks target the candidate deployer and impls.
    address internal constant DEPLOYER =
        LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CANDIDATE;
    address internal constant VAULT_BEACON = address(0xBEAC04);
    address internal constant RECEIPT_BEACON = address(0xBEAC12);
    address internal constant EXPECTED_VAULT_IMPL = LibProdDeployV4.STOX_RECEIPT_VAULT_CANDIDATE;
    address internal constant EXPECTED_RECEIPT_IMPL = LibProdDeployV4.STOX_RECEIPT_CANDIDATE;

    /// Storage-slot pre-image constant kept for cross-checking against source.
    bytes32 internal constant EXPECTED_MAIN_STORAGE_LOCATION =
        0x4bb94ceb743cdbfc320393e9b6fac11d883b2f90ac89bce731e459177c5be700;

    /// The widest capacity the bucket codec can enforce. Used as the
    /// "effectively unbounded" cap the shared `setUp` grants, so the mint
    /// tests that are about something OTHER than the caps are not metered by
    /// them. The mint-cap tests configure their own narrow limits, and the
    /// fail-closed ones deploy a fresh, unconfigured proxy via `_deployProxy`.
    uint256 internal constant UNBOUNDED_CAPACITY = LEAKY_BUCKET_LEVEL_MAX;

    ST0xOrchestrator internal impl;
    ST0xOrchestrator internal orchestrator;

    /// A callback recipient that authorises anything, so the mint-cap tests
    /// are about the buckets rather than the recipient authorisation (which
    /// has its own section above).
    MockMintRecipient internal capRecipient;

    function setUp() public {
        capRecipient = new MockMintRecipient(true);
        impl = new ST0xOrchestrator();
        // `initialize` runs the vault-logic guard, so the guard mocks must be
        // in place BEFORE the proxy is deployed.
        _makeGuardPass();
        orchestrator = _deployProxy(OWNER);
        _mockVaultTopology(TOKEN, RECEIPT_ADDR);
        _mockVaultTopology(TOKEN2, RECEIPT_ADDR2);
        // Mint caps fail closed, so a proxy with nothing configured mints
        // nothing at all. Grant an unbounded global limit and unbounded
        // per-token defaults so the rest of the suite exercises what it is
        // about rather than the caps.
        vm.startPrank(OWNER);
        orchestrator.setGlobalMintLimit(TOKEN, 0, UNBOUNDED_CAPACITY, 0);
        orchestrator.setTokenMintLimit(TOKEN, 0, UNBOUNDED_CAPACITY, 0);
        orchestrator.setTokenMintLimit(TOKEN2, 0, UNBOUNDED_CAPACITY, 0);
        vm.stopPrank();
    }

    // ------------------------------------------------------------------ //
    //                            Test helpers                            //
    // ------------------------------------------------------------------ //

    /// Deploy a fresh beacon + proxy pair pointing at `impl`, initialised
    /// with `owner`. The guard mocks must already pass.
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

    /// Mock a token's static vault topology: `receipt()` returns its receipt,
    /// and the corporate-actions fallback answers as a vault that has never
    /// had an action complete — cursor zero, identity multiplier. That is the
    /// state in which genesis units and current units coincide, so every test
    /// that is not about rebasing reads the same numbers it always did.
    function _mockVaultTopology(address token, address receipt_) internal {
        vm.mockCall(token, abi.encodeWithSelector(ReceiptVault.receipt.selector), abi.encode(receipt_));
        _mockCorporateActions(token, 0, LibDecimalFloat.FLOAT_ONE);
    }

    /// Mock `token`'s corporate-actions reads: the cap setters' cursor and
    /// the metering path's genesis denominator.
    function _mockCorporateActions(address token, uint256 completedActions, Float multiplier) internal {
        vm.mockCall(
            token,
            abi.encodeWithSelector(ICorporateActionsV1.completedActionCount.selector),
            abi.encode(completedActions)
        );
        vm.mockCall(
            token,
            abi.encodeWithSelector(ICorporateActionsV1.cumulativeBalanceMultiplierSinceGenesis.selector),
            abi.encode(multiplier)
        );
    }

    /// A `Float` for `numerator / denominator`, the shape a stock-split
    /// multiplier arrives in. Built from the two integers rather than a
    /// literal so the test states the ratio it means.
    /// Restrict a fuzzed token address to one `vm.mockCall` can stand in for:
    /// not a precompile, not the cheatcode or console address, and not one of
    /// the fixture contracts whose real code the test depends on.
    function _assumeMockableToken(address token) internal view {
        vm.assume(uint160(token) > 0x9);
        vm.assume(token != VM_ADDRESS);
        vm.assume(token != CONSOLE);
        vm.assume(token.code.length == 0);
    }

    /// Mock `highwaterId()` for a token (the burn walk's cap).
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

    /// Build a `MintAuthV1` from a signature + nonce.
    function _auth(bytes memory sig, bytes32 nonce) internal pure returns (MintAuthV1 memory) {
        return MintAuthV1({nonce: nonce, signature: sig});
    }

    /// The digest as a raw `bytes32` for `vm.sign` / call encoding.
    function _digest(address token, address to, uint256 amount, bytes32 nonce) internal view returns (bytes32) {
        return Digest.unwrap(orchestrator.mintAuthDigest(token, to, amount, nonce));
    }

    /// ECDSA-sign the mint-auth digest with `pk`.
    function _sign(uint256 pk, address token, address to, uint256 amount, bytes32 nonce)
        internal
        view
        returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _digest(token, to, amount, nonce));
        return abi.encodePacked(r, s, v);
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
    //                       EIP-712 domain pinning                       //
    // ------------------------------------------------------------------ //

    /// The ERC-5267 self-description must advertise exactly the documented
    /// signer domain: name "ST0xOrchestrator", version "1", the current
    /// chain, and the proxy address, with no salt or extensions. External
    /// integrations (wallets, recipients) build their digests from these
    /// values, so they are pinned as literals here.
    function testEip712DomainFields() external view {
        (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        ) = orchestrator.eip712Domain();
        assertEq(uint8(fields), 0x0f, "fields must flag name+version+chainId+verifyingContract only");
        assertEq(name, "ST0xOrchestrator", "domain name");
        assertEq(version, "1", "domain version");
        assertEq(chainId, block.chainid, "domain chainId");
        assertEq(verifyingContract, address(orchestrator), "domain verifyingContract");
        assertEq(salt, bytes32(0), "domain salt");
        assertEq(extensions.length, 0, "domain extensions");
    }

    /// `mintAuthDigest` must equal a FULLY independent EIP-712 computation:
    /// domain separator built from the literal ("ST0xOrchestrator", "1",
    /// chainid, proxy) and struct hash built from the literal MintAuth type
    /// string. This is what an external signer computes from the docs alone,
    /// so any drift in domain name/version, typehash, or field order breaks
    /// this test.
    function testMintAuthDigestMatchesIndependentComputation(address token, address to, uint256 amount, bytes32 nonce)
        external
        view
    {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ST0xOrchestrator")),
                keccak256(bytes("1")),
                block.chainid,
                address(orchestrator)
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("MintAuth(address token,address recipient,uint256 amount,bytes32 nonce)"),
                token,
                to,
                amount,
                nonce
            )
        );
        bytes32 expected = keccak256(abi.encodePacked(hex"1901", domainSeparator, structHash));
        assertEq(_digest(token, to, amount, nonce), expected, "digest vs independent EIP-712 computation");
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
        vm.expectRevert(IST0xOrchestratorV1.ZeroOwner.selector);
        new BeaconProxy(address(beacon), initData);
    }

    /// `initialize` runs the vault-logic guard, so a fresh proxy cannot be
    /// deployed against unexpected vault logic — the `BeaconProxy`
    /// constructor bubbles `VaultLogicMismatch` from the init delegatecall.
    function testInitializeVaultGuardFailReverts() external {
        _makeGuardFailVault();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), address(this));
        bytes memory initData = abi.encodeCall(ST0xOrchestrator.initialize, (OWNER));
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.VaultLogicMismatch.selector, EXPECTED_VAULT_IMPL, address(0xDEAD)
            )
        );
        new BeaconProxy(address(beacon), initData);
    }

    /// Same for the receipt leg of the guard.
    function testInitializeReceiptGuardFailReverts() external {
        _makeGuardFailReceipt();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), address(this));
        bytes memory initData = abi.encodeCall(ST0xOrchestrator.initialize, (OWNER));
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.ReceiptLogicMismatch.selector, EXPECTED_RECEIPT_IMPL, address(0xDEAD)
            )
        );
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
        orchestrator.mint(TOKEN, BOB, 1, _auth("", bytes32(0)), "");
    }

    function testFuzzBurnUnauthorized(address caller) external {
        vm.assume(!orchestrator.hasRole(orchestrator.BURN_ROLE(), caller));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, orchestrator.BURN_ROLE()
            )
        );
        vm.prank(caller);
        orchestrator.burn(TOKEN, 1, "");
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
        orchestrator.mint(TOKEN, BOB, 1, _auth("", bytes32(0)), "");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, BOB, orchestrator.BURN_ROLE()
            )
        );
        vm.prank(BOB);
        orchestrator.burn(TOKEN, 1, "");
    }

    // ------------------------------------------------------------------ //
    //                               mint()                               //
    // ------------------------------------------------------------------ //

    /// Set up the vault-side mocks for a mint of any amount forwarding `info`.
    function _prepMint(address token, bytes memory info) internal {
        _mockERC20(token);
        vm.mockCall(
            token,
            abi.encodeWithSelector(ReceiptVault.mint.selector, uint256(0), address(orchestrator), uint256(0), info),
            abi.encode(uint256(0))
        );
    }

    /// Helper: mock vault.mint for the exact `amount`.
    function _prepMintExact(address token, uint256 amount, bytes memory info) internal {
        _mockERC20(token);
        vm.mockCall(
            token,
            abi.encodeWithSelector(ReceiptVault.mint.selector, amount, address(orchestrator), uint256(0), info),
            abi.encode(amount)
        );
    }

    /// (a) ECDSA signature: `to` is an EOA whose key signs the digest.
    function testMintWithEcdsaSignature() external {
        (address eoa, uint256 pk) = makeAddrAndKey("recipient");
        _grant(orchestrator.MINT_ROLE(), address(this));
        uint256 amount = 500;
        bytes32 nonce = keccak256("n1");
        bytes memory info = hex"1234";

        _prepMintExact(TOKEN, amount, info);

        bytes memory sig = _sign(pk, TOKEN, eoa, amount, nonce);

        // vault.mint called with (amount, orchestrator, 0, info).
        vm.expectCall(
            TOKEN, abi.encodeWithSelector(ReceiptVault.mint.selector, amount, address(orchestrator), uint256(0), info)
        );
        // then token.transfer(to, amount).
        vm.expectCall(TOKEN, abi.encodeWithSelector(IERC20.transfer.selector, eoa, amount));

        vm.expectEmit(true, true, true, true, address(orchestrator));
        emit IST0xOrchestratorV1.Minted(address(this), TOKEN, eoa, amount, nonce);
        orchestrator.mint(TOKEN, eoa, amount, _auth(sig, nonce), info);
    }

    /// (b) EIP-1271: `to` is a contract returning the 1271 magic value.
    function testMintWith1271() external {
        _grant(orchestrator.MINT_ROLE(), address(this));
        uint256 amount = 100;
        bytes32 nonce = keccak256("n2");
        bytes memory info = "";

        Mock1271 recipient = new Mock1271(true);
        _prepMintExact(TOKEN, amount, info);
        // Any non-empty signature triggers the 1271 path since `to` is a contract.
        bytes memory sig = hex"deadbeef";

        vm.expectEmit(true, true, true, true, address(orchestrator));
        emit IST0xOrchestratorV1.Minted(address(this), TOKEN, address(recipient), amount, nonce);
        orchestrator.mint(TOKEN, address(recipient), amount, _auth(sig, nonce), info);
    }

    function testMint1271RejectReverts() external {
        _grant(orchestrator.MINT_ROLE(), address(this));
        Mock1271 recipient = new Mock1271(false);
        _prepMint(TOKEN, "");
        vm.expectRevert(IST0xOrchestratorV1.BadRecipientSignature.selector);
        orchestrator.mint(TOKEN, address(recipient), 100, _auth(hex"deadbeef", keccak256("x")), "");
    }

    /// (c) Callback: empty signature; `to` implements IMintRecipient.
    function testMintWithCallback() external {
        _grant(orchestrator.MINT_ROLE(), address(this));
        uint256 amount = 250;
        bytes32 nonce = keccak256("n3");
        bytes memory info = hex"abcd";

        MockMintRecipient recipient = new MockMintRecipient(true);
        _prepMintExact(TOKEN, amount, info);

        bytes32 digest = _digest(TOKEN, address(recipient), amount, nonce);
        vm.expectCall(address(recipient), abi.encodeWithSelector(IMintRecipient.authorizeMint.selector, digest));

        vm.expectEmit(true, true, true, true, address(orchestrator));
        emit IST0xOrchestratorV1.Minted(address(this), TOKEN, address(recipient), amount, nonce);
        orchestrator.mint(TOKEN, address(recipient), amount, _auth("", nonce), info);
    }

    function testMintCallbackWrongValueReverts() external {
        _grant(orchestrator.MINT_ROLE(), address(this));
        MockMintRecipient recipient = new MockMintRecipient(false);
        _prepMint(TOKEN, "");
        vm.expectRevert(
            abi.encodeWithSelector(IST0xOrchestratorV1.RecipientCallbackRejected.selector, address(recipient))
        );
        orchestrator.mint(TOKEN, address(recipient), 100, _auth("", keccak256("x")), "");
    }

    /// Signature present but recovers to a different address → BadRecipientSignature.
    function testMintBadSignatureReverts() external {
        (address eoa,) = makeAddrAndKey("recipient");
        (, uint256 wrongPk) = makeAddrAndKey("someone-else");
        _grant(orchestrator.MINT_ROLE(), address(this));
        uint256 amount = 500;
        bytes32 nonce = keccak256("n1");
        _prepMint(TOKEN, "");

        bytes memory sig = _sign(wrongPk, TOKEN, eoa, amount, nonce);

        vm.expectRevert(IST0xOrchestratorV1.BadRecipientSignature.selector);
        orchestrator.mint(TOKEN, eoa, amount, _auth(sig, nonce), "");
    }

    function testMintZeroAmountReverts() external {
        _grant(orchestrator.MINT_ROLE(), address(this));
        vm.expectRevert(IST0xOrchestratorV1.ZeroAmount.selector);
        orchestrator.mint(TOKEN, BOB, 0, _auth("", bytes32(0)), "");
    }

    /// Nonce replay: identical (token,to,amount,nonce) twice reverts.
    function testMintReplayReverts() external {
        (address eoa, uint256 pk) = makeAddrAndKey("recipient");
        _grant(orchestrator.MINT_ROLE(), address(this));
        uint256 amount = 500;
        bytes32 nonce = keccak256("n1");
        _prepMintExact(TOKEN, amount, "");

        bytes memory sig = _sign(pk, TOKEN, eoa, amount, nonce);

        orchestrator.mint(TOKEN, eoa, amount, _auth(sig, nonce), "");
        assertTrue(orchestrator.nonceUsed(eoa, nonce));

        vm.expectRevert(abi.encodeWithSelector(IST0xOrchestratorV1.NonceReplayed.selector, eoa, nonce));
        orchestrator.mint(TOKEN, eoa, amount, _auth(sig, nonce), "");
    }

    /// Replay is namespaced by (to, nonce), NOT by digest: the same nonce
    /// with a different amount reverts even with a fresh valid signature.
    function testMintSameNonceDifferentAmountReverts() external {
        (address eoa, uint256 pk) = makeAddrAndKey("recipient");
        _grant(orchestrator.MINT_ROLE(), address(this));
        bytes32 nonce = keccak256("n1");
        _mockERC20(TOKEN);
        vm.mockCall(TOKEN, abi.encodeWithSelector(ReceiptVault.mint.selector), abi.encode(uint256(500)));

        // Mint amount 500 consumes (eoa, nonce).
        orchestrator.mint(TOKEN, eoa, 500, _auth(_sign(pk, TOKEN, eoa, 500, nonce), nonce), "");

        // Same nonce, amount 600, correctly signed → still NonceReplayed.
        bytes memory sig = _sign(pk, TOKEN, eoa, 600, nonce);
        vm.expectRevert(abi.encodeWithSelector(IST0xOrchestratorV1.NonceReplayed.selector, eoa, nonce));
        orchestrator.mint(TOKEN, eoa, 600, _auth(sig, nonce), "");
    }

    /// Same for a different token: the nonce is single-use for the recipient
    /// regardless of which token it originally authorised.
    function testMintSameNonceDifferentTokenReverts() external {
        (address eoa, uint256 pk) = makeAddrAndKey("recipient");
        _grant(orchestrator.MINT_ROLE(), address(this));
        bytes32 nonce = keccak256("n1");
        _mockERC20(TOKEN);
        vm.mockCall(TOKEN, abi.encodeWithSelector(ReceiptVault.mint.selector), abi.encode(uint256(500)));

        orchestrator.mint(TOKEN, eoa, 500, _auth(_sign(pk, TOKEN, eoa, 500, nonce), nonce), "");

        bytes memory sig = _sign(pk, TOKEN2, eoa, 500, nonce);
        vm.expectRevert(abi.encodeWithSelector(IST0xOrchestratorV1.NonceReplayed.selector, eoa, nonce));
        orchestrator.mint(TOKEN2, eoa, 500, _auth(sig, nonce), "");
    }

    /// The SAME nonce for a DIFFERENT recipient is fine — no third party can
    /// consume another recipient's nonce.
    function testMintSameNonceDifferentRecipientSucceeds() external {
        (address alice, uint256 alicePk) = makeAddrAndKey("alice");
        (address carol, uint256 carolPk) = makeAddrAndKey("carol");
        _grant(orchestrator.MINT_ROLE(), address(this));
        uint256 amount = 500;
        bytes32 nonce = keccak256("shared");
        _mockERC20(TOKEN);
        vm.mockCall(TOKEN, abi.encodeWithSelector(ReceiptVault.mint.selector), abi.encode(uint256(500)));

        orchestrator.mint(TOKEN, alice, amount, _auth(_sign(alicePk, TOKEN, alice, amount, nonce), nonce), "");
        assertTrue(orchestrator.nonceUsed(alice, nonce));
        assertFalse(orchestrator.nonceUsed(carol, nonce), "alice's mint must not consume carol's nonce");

        orchestrator.mint(TOKEN, carol, amount, _auth(_sign(carolPk, TOKEN, carol, amount, nonce), nonce), "");
        assertTrue(orchestrator.nonceUsed(carol, nonce));
    }

    function testMintVaultGuardFailReverts() external {
        _grant(orchestrator.MINT_ROLE(), address(this));
        _makeGuardFailVault();
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.VaultLogicMismatch.selector, EXPECTED_VAULT_IMPL, address(0xDEAD)
            )
        );
        orchestrator.mint(TOKEN, BOB, 1, _auth("", bytes32(0)), "");
    }

    function testMintReceiptGuardFailReverts() external {
        _grant(orchestrator.MINT_ROLE(), address(this));
        _makeGuardFailReceipt();
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.ReceiptLogicMismatch.selector, EXPECTED_RECEIPT_IMPL, address(0xDEAD)
            )
        );
        orchestrator.mint(TOKEN, BOB, 1, _auth("", bytes32(0)), "");
    }

    /// Mint never touches the burn pointer — no seeding, no walk.
    function testMintLeavesBurnPointerUntouched() external {
        (address eoa, uint256 pk) = makeAddrAndKey("recipient");
        _grant(orchestrator.MINT_ROLE(), address(this));
        uint256 amount = 500;
        bytes32 nonce = keccak256("n1");
        _prepMintExact(TOKEN, amount, "");

        orchestrator.mint(TOKEN, eoa, amount, _auth(_sign(pk, TOKEN, eoa, amount, nonce), nonce), "");
        assertEq(orchestrator.nextBurnReceiptId(TOKEN), 0, "mint must not move the pointer");
    }

    // ------------------------------------------------------------------ //
    //                               burn()                               //
    // ------------------------------------------------------------------ //

    /// Position a token's pointer at `idx` via EMERGENCY setBurnIndex so walk
    /// tests can lay receipts from a known base.
    function _seedPointer(address token, uint256 idx) internal {
        _grant(orchestrator.EMERGENCY_ROLE(), address(this));
        orchestrator.setBurnIndex(token, idx);
    }

    function testBurnZeroAmountReverts() external {
        _grant(orchestrator.BURN_ROLE(), address(this));
        vm.expectRevert(IST0xOrchestratorV1.ZeroAmount.selector);
        orchestrator.burn(TOKEN, 0, "");
    }

    /// The vault reporting an assets amount != the shares requested (the
    /// ratio is 1:1 by construction) halts the mint loudly.
    function testMintVaultAmountMismatchReverts() external {
        _grant(orchestrator.MINT_ROLE(), address(this));
        uint256 amount = 100;
        (address eoa, uint256 pk) = makeAddrAndKey("vam-recipient");
        bytes memory sig = _sign(pk, TOKEN, eoa, amount, keccak256("vam-mint"));
        _mockERC20(TOKEN);
        vm.mockCall(
            TOKEN,
            abi.encodeWithSelector(ReceiptVault.mint.selector, amount, address(orchestrator), uint256(0), bytes("")),
            abi.encode(amount - 1)
        );
        vm.expectRevert(abi.encodeWithSelector(IST0xOrchestratorV1.VaultAmountMismatch.selector, amount, amount - 1));
        orchestrator.mint(TOKEN, eoa, amount, _auth(sig, keccak256("vam-mint")), "");
    }

    // ------------------------------------------------------------------ //
    //                EIP-712 digest reference vectors                    //
    // ------------------------------------------------------------------ //

    /// The canonical MintAuth EIP-712 type string, exactly as documented on
    /// `MINT_AUTH_TYPEHASH`. Offchain signers are built against this string,
    /// so the contract constant must hash it byte-for-byte.
    string internal constant MINT_AUTH_TYPE = "MintAuth(address token,address recipient,uint256 amount,bytes32 nonce)";

    /// Reconstruct the mint-auth digest fully independently of the contract:
    /// domain separator from the documented ("ST0xOrchestrator", "1") domain
    /// and struct hash from the canonical type string. This is what a
    /// spec-conformant offchain signer computes.
    function _referenceMintAuthDigest(address token, address to, uint256 amount, bytes32 nonce)
        internal
        view
        returns (bytes32)
    {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ST0xOrchestrator")),
                keccak256(bytes("1")),
                block.chainid,
                address(orchestrator)
            )
        );
        bytes32 structHash = keccak256(abi.encode(keccak256(bytes(MINT_AUTH_TYPE)), token, to, amount, nonce));
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    /// Pin the typehash constant to the documented type string so offchain
    /// signers built to the spec can never silently diverge.
    function testMintAuthTypehashPinned() external view {
        assertEq(
            orchestrator.MINT_AUTH_TYPEHASH(),
            keccak256(bytes(MINT_AUTH_TYPE)),
            "MINT_AUTH_TYPEHASH does not hash the canonical MintAuth type string"
        );
    }

    /// `mintAuthDigest` must equal the independently reconstructed EIP-712
    /// digest for distinct non-zero (token, recipient, amount, nonce), so the
    /// signed payload provably commits to every field.
    function testMintAuthDigestMatchesEip712Reference() external view {
        address token = TOKEN;
        address to = BOB;
        uint256 amount = 12345;
        bytes32 nonce = keccak256("reference-vector");
        assertEq(
            Digest.unwrap(orchestrator.mintAuthDigest(token, to, amount, nonce)),
            _referenceMintAuthDigest(token, to, amount, nonce),
            "mintAuthDigest diverges from the EIP-712 reference construction"
        );
    }

    /// Same reference check across the whole input space.
    function testFuzzMintAuthDigestMatchesEip712Reference(address token, address to, uint256 amount, bytes32 nonce)
        external
        view
    {
        assertEq(
            Digest.unwrap(orchestrator.mintAuthDigest(token, to, amount, nonce)),
            _referenceMintAuthDigest(token, to, amount, nonce),
            "mintAuthDigest diverges from the EIP-712 reference construction"
        );
    }

    /// End-to-end: an EOA signing the INDEPENDENTLY reconstructed digest (as
    /// a spec-conformant offchain signer would, never calling the contract's
    /// own view) is accepted by `mint`. Any drift between the contract digest
    /// and the documented construction turns this into BadRecipientSignature.
    function testMintWithSignatureOverReferenceDigest() external {
        (address eoa, uint256 pk) = makeAddrAndKey("reference-signer");
        _grant(orchestrator.MINT_ROLE(), address(this));
        uint256 amount = 777;
        bytes32 nonce = keccak256("reference-signed");
        bytes memory info = hex"5157";

        _prepMintExact(TOKEN, amount, info);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _referenceMintAuthDigest(TOKEN, eoa, amount, nonce));
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectEmit(true, true, true, true, address(orchestrator));
        emit IST0xOrchestratorV1.Minted(address(this), TOKEN, eoa, amount, nonce);
        orchestrator.mint(TOKEN, eoa, amount, _auth(sig, nonce), info);
    }

    // ------------------------------------------------------------------ //
    //                        Reentrancy guard                            //
    // ------------------------------------------------------------------ //

    /// A malicious callback recipient that reenters `mint` from inside its
    /// `authorizeMint` callback (holding MINT_ROLE itself) must be stopped by
    /// the reentrancy guard: the nested call reverts
    /// `ReentrancyGuardReentrantCall` and the whole outer mint unwinds, so
    /// neither nonce is consumed.
    function testMintReenteredFromCallbackReverts() external {
        _grant(orchestrator.MINT_ROLE(), address(this));
        uint256 outerAmount = 400;
        uint256 innerAmount = 5;
        bytes32 outerNonce = keccak256("outer");
        bytes32 innerNonce = keccak256("inner");

        ReentrantMintRecipient recipient = new ReentrantMintRecipient(orchestrator, TOKEN, innerAmount, innerNonce);
        _grant(orchestrator.MINT_ROLE(), address(recipient));

        // Mock the vault legs for BOTH mints so that, were the guard absent,
        // nested and outer mint would both complete instead of reverting for
        // an unrelated reason.
        _prepMintExact(TOKEN, outerAmount, "");
        _prepMintExact(TOKEN, innerAmount, "");

        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        orchestrator.mint(TOKEN, address(recipient), outerAmount, _auth("", outerNonce), "");

        assertFalse(orchestrator.nonceUsed(address(recipient), outerNonce), "outer nonce must not persist");
        assertFalse(orchestrator.nonceUsed(address(recipient), innerNonce), "inner nonce must not persist");
    }

    /// The vault reporting an assets amount != the shares redeemed halts the
    /// burn loudly.
    function testBurnVaultAmountMismatchReverts() external {
        _grant(orchestrator.BURN_ROLE(), address(this));
        _seedPointer(TOKEN, 0);
        uint256 amount = 300;
        _mockHighwater(TOKEN, 1);
        _mockERC20(TOKEN);
        _mockBalance(RECEIPT_ADDR, 0, amount);
        vm.mockCall(
            TOKEN,
            abi.encodeWithSelector(
                ReceiptVault.redeem.selector,
                amount,
                address(orchestrator),
                address(orchestrator),
                uint256(0),
                bytes("")
            ),
            abi.encode(amount - 1)
        );
        vm.expectRevert(abi.encodeWithSelector(IST0xOrchestratorV1.VaultAmountMismatch.selector, amount, amount - 1));
        orchestrator.burn(TOKEN, amount, "");
    }

    function testBurnVaultGuardFailReverts() external {
        _grant(orchestrator.BURN_ROLE(), address(this));
        _makeGuardFailVault();
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.VaultLogicMismatch.selector, EXPECTED_VAULT_IMPL, address(0xDEAD)
            )
        );
        orchestrator.burn(TOKEN, 1, "");
    }

    /// Single receipt exact drain: pointer advances by 1. The shares are
    /// pulled from the caller via transferFrom.
    function testBurnSingleReceiptExactDrain() external {
        _grant(orchestrator.BURN_ROLE(), address(this));
        _seedPointer(TOKEN, 0);
        uint256 amount = 300;
        _mockHighwater(TOKEN, 1);
        _mockERC20(TOKEN);
        _mockBalance(RECEIPT_ADDR, 0, amount);
        _mockRedeem(TOKEN, amount, 0, "");

        vm.expectCall(
            TOKEN, abi.encodeWithSelector(IERC20.transferFrom.selector, address(this), address(orchestrator), amount)
        );
        vm.expectCall(
            TOKEN,
            abi.encodeWithSelector(
                ReceiptVault.redeem.selector, amount, address(orchestrator), address(orchestrator), uint256(0), ""
            )
        );
        vm.expectEmit(true, true, true, true, address(orchestrator));
        emit IST0xOrchestratorV1.Burned(address(this), TOKEN, amount, 0, 1);
        orchestrator.burn(TOKEN, amount, "");
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
        emit IST0xOrchestratorV1.Burned(address(this), TOKEN, amount, 0, 3);
        orchestrator.burn(TOKEN, amount, "");
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
        emit IST0xOrchestratorV1.Burned(address(this), TOKEN, 300, 0, 2);
        orchestrator.burn(TOKEN, 300, "");
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
        emit IST0xOrchestratorV1.Burned(address(this), TOKEN, 200, 0, 0);
        orchestrator.burn(TOKEN, 200, "");
        assertEq(orchestrator.nextBurnReceiptId(TOKEN), 0, "pointer parked at partially-drained id");
    }

    /// Overshoot: pointer above cap → the walk cannot cover anything →
    /// revert `InsufficientReceipts(token, amount)`. No mint-on-demand.
    function testBurnOvershootReverts() external {
        _grant(orchestrator.BURN_ROLE(), address(this));
        // Position pointer at 1, cap at 0 → idx(1) > cap(0) immediately.
        _seedPointer(TOKEN, 1);
        uint256 amount = 42;
        _mockERC20(TOKEN);
        _mockHighwater(TOKEN, 0);

        vm.expectRevert(abi.encodeWithSelector(IST0xOrchestratorV1.InsufficientReceipts.selector, TOKEN, amount));
        orchestrator.burn(TOKEN, amount, "");

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

        vm.expectRevert(abi.encodeWithSelector(IST0xOrchestratorV1.InsufficientReceipts.selector, TOKEN, 20));
        orchestrator.burn(TOKEN, amount, "");

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
        orchestrator.burn(TOKEN, 100, "");

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
        emit IST0xOrchestratorV1.Burned(address(this), TOKEN, amount, startIdx, startIdx + 1);
        orchestrator.burn(TOKEN, amount, "");
        assertEq(orchestrator.nextBurnReceiptId(TOKEN), startIdx + 1);
    }

    // ------------------------------------------------------------------ //
    //                            setBurnIndex()                          //
    // ------------------------------------------------------------------ //

    function testFuzzSetBurnIndex(uint256 first, uint256 second) external {
        _grant(orchestrator.EMERGENCY_ROLE(), address(this));
        vm.expectEmit(true, false, false, true, address(orchestrator));
        emit IST0xOrchestratorV1.BurnIndexSet(TOKEN, 0, first);
        orchestrator.setBurnIndex(TOKEN, first);
        assertEq(orchestrator.nextBurnReceiptId(TOKEN), first);

        vm.expectEmit(true, false, false, true, address(orchestrator));
        emit IST0xOrchestratorV1.BurnIndexSet(TOKEN, first, second);
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
        emit IST0xOrchestratorV1.ReceiptsWithdrawn(TOKEN, to, id, amount);
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
        emit IST0xOrchestratorV1.SharesWithdrawn(TOKEN, to, amount);
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
        emit IST0xOrchestratorV1.ForeignERC1155Swept(erc1155, to, id, amount);
        orchestrator.sweepERC1155(erc1155, id, amount, to);
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

    /// Mark `erc1155` as a genuine production receipt of TOKEN: `manager()`
    /// returns TOKEN, and TOKEN's `receipt()` (mocked in setUp) round-trips
    /// back to RECEIPT_ADDR.
    function _mockManager(address erc1155, address vault) internal {
        vm.mockCall(erc1155, abi.encodeWithSelector(IReceiptV3.manager.selector), abi.encode(vault));
    }

    /// Foreign 1155s are always accepted and never touch a pointer: the
    /// `manager()` probe reverts (test contract has no such function) or
    /// returns malformed data (code-less address → empty returndata).
    function testFuzzOnERC1155ReceivedForeign(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external {
        _seedPointer(TOKEN, 10);

        // msg.sender = this test contract: the `manager()` staticcall reverts.
        assertEq(
            orchestrator.onERC1155Received(operator, from, id, value, data), IERC1155Receiver.onERC1155Received.selector
        );

        // msg.sender = code-less foreign 1155: staticcall returns empty data.
        vm.prank(FOREIGN_1155);
        assertEq(
            orchestrator.onERC1155Received(operator, from, id, value, data), IERC1155Receiver.onERC1155Received.selector
        );

        assertEq(orchestrator.nextBurnReceiptId(TOKEN), 10, "pointer untouched by foreign 1155");
        assertEq(orchestrator.nextBurnReceiptId(FOREIGN_1155), 0, "no pointer created for foreign 1155");
    }

    function testFuzzOnERC1155BatchReceivedForeign(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external {
        _seedPointer(TOKEN, 10);
        vm.prank(FOREIGN_1155);
        assertEq(
            orchestrator.onERC1155BatchReceived(operator, from, ids, values, data),
            IERC1155Receiver.onERC1155BatchReceived.selector
        );
        assertEq(orchestrator.nextBurnReceiptId(TOKEN), 10, "pointer untouched by foreign 1155");
    }

    /// A genuine receipt (manager() → vault, vault.receipt() round-trips)
    /// arriving at an id below the pointer lowers the pointer to that id.
    function testOnERC1155ReceivedGenuineLowersPointer() external {
        _seedPointer(TOKEN, 10);
        _mockManager(RECEIPT_ADDR, TOKEN);

        vm.expectEmit(true, false, false, true, address(orchestrator));
        emit IST0xOrchestratorV1.BurnIndexLowered(TOKEN, 10, 5);
        vm.prank(RECEIPT_ADDR);
        bytes4 ret = orchestrator.onERC1155Received(address(this), BOB, 5, 1, "");
        assertEq(ret, IERC1155Receiver.onERC1155Received.selector);
        assertEq(orchestrator.nextBurnReceiptId(TOKEN), 5, "pointer lowered to arriving id");
    }

    /// A genuine receipt at an id AT or ABOVE the pointer is a no-op.
    function testOnERC1155ReceivedIdAtOrAbovePointerNoOp() external {
        _seedPointer(TOKEN, 10);
        _mockManager(RECEIPT_ADDR, TOKEN);

        vm.prank(RECEIPT_ADDR);
        orchestrator.onERC1155Received(address(this), BOB, 10, 1, "");
        assertEq(orchestrator.nextBurnReceiptId(TOKEN), 10, "id == pointer must not move it");

        vm.prank(RECEIPT_ADDR);
        orchestrator.onERC1155Received(address(this), BOB, 15, 1, "");
        assertEq(orchestrator.nextBurnReceiptId(TOKEN), 10, "id > pointer must not move it");
    }

    /// A sender whose claimed vault does NOT round-trip (`vault.receipt()` is
    /// some other address) is treated as foreign: accepted, no pointer move.
    function testOnERC1155ReceivedRoundTripMismatchNoOp() external {
        _seedPointer(TOKEN, 10);
        // FOREIGN_1155 claims TOKEN as its vault, but TOKEN's receipt is
        // RECEIPT_ADDR — the round-trip fails.
        _mockManager(FOREIGN_1155, TOKEN);

        vm.prank(FOREIGN_1155);
        bytes4 ret = orchestrator.onERC1155Received(address(this), BOB, 5, 1, "");
        assertEq(ret, IERC1155Receiver.onERC1155Received.selector);
        assertEq(orchestrator.nextBurnReceiptId(TOKEN), 10, "spoofed receipt must not move the pointer");
    }

    /// The batch hook lowers the pointer to the MINIMUM qualifying id.
    function testOnERC1155BatchReceivedLowersToMin() external {
        _seedPointer(TOKEN, 10);
        _mockManager(RECEIPT_ADDR, TOKEN);

        uint256[] memory ids = new uint256[](4);
        ids[0] = 12;
        ids[1] = 7;
        ids[2] = 3;
        ids[3] = 9;
        uint256[] memory values = new uint256[](4);
        values[0] = 1;
        values[1] = 1;
        values[2] = 1;
        values[3] = 1;

        // Each qualifying id lowers in turn: 10 → 7 → 3.
        vm.expectEmit(true, false, false, true, address(orchestrator));
        emit IST0xOrchestratorV1.BurnIndexLowered(TOKEN, 10, 7);
        vm.expectEmit(true, false, false, true, address(orchestrator));
        emit IST0xOrchestratorV1.BurnIndexLowered(TOKEN, 7, 3);
        vm.prank(RECEIPT_ADDR);
        bytes4 ret = orchestrator.onERC1155BatchReceived(address(this), BOB, ids, values, "");
        assertEq(ret, IERC1155Receiver.onERC1155BatchReceived.selector);
        assertEq(orchestrator.nextBurnReceiptId(TOKEN), 3, "pointer lowered to minimum qualifying id");
    }

    /// A ZERO-value transfer of a genuine receipt at a low id must NOT lower
    /// the pointer: a zero-value transfer delivers no burnable balance, so
    /// lowering to its id would strand the pointer over an empty id. Without
    /// this gate any unprivileged account could floor the pointer for free
    /// (a zero-value transfer needs no balance) and inflate the next burn's
    /// walk to O(highwaterId) as a repeatable griefing vector.
    function testOnERC1155ReceivedZeroValueDoesNotLowerPointer() external {
        _seedPointer(TOKEN, 10);
        _mockManager(RECEIPT_ADDR, TOKEN);

        vm.recordLogs();
        vm.prank(RECEIPT_ADDR);
        bytes4 ret = orchestrator.onERC1155Received(address(this), BOB, 5, 0, "");
        assertEq(ret, IERC1155Receiver.onERC1155Received.selector);
        assertEq(orchestrator.nextBurnReceiptId(TOKEN), 10, "zero-value transfer must not move the pointer");
        assertEq(vm.getRecordedLogs().length, 0, "no BurnIndexLowered for a zero-value transfer");
    }

    /// Batch variant: only the non-zero entries lower the pointer; a zero-value
    /// entry at an even lower id is ignored.
    function testOnERC1155BatchReceivedZeroValueEntriesIgnored() external {
        _seedPointer(TOKEN, 10);
        _mockManager(RECEIPT_ADDR, TOKEN);

        uint256[] memory ids = new uint256[](2);
        ids[0] = 2; // lower id, but zero value -> ignored
        ids[1] = 6; // non-zero value -> lowers to 6
        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 1;

        vm.expectEmit(true, false, false, true, address(orchestrator));
        emit IST0xOrchestratorV1.BurnIndexLowered(TOKEN, 10, 6);
        vm.prank(RECEIPT_ADDR);
        bytes4 ret = orchestrator.onERC1155BatchReceived(address(this), BOB, ids, values, "");
        assertEq(ret, IERC1155Receiver.onERC1155BatchReceived.selector);
        assertEq(
            orchestrator.nextBurnReceiptId(TOKEN), 6, "zero-value entry ignored; pointer lowered only by non-zero entry"
        );
    }

    function testSupportsInterface() external view {
        assertTrue(orchestrator.supportsInterface(type(IERC1155Receiver).interfaceId));
        assertTrue(orchestrator.supportsInterface(type(IST0xOrchestratorV1).interfaceId));
        assertTrue(orchestrator.supportsInterface(type(IERC165).interfaceId));
        assertTrue(orchestrator.supportsInterface(type(IAccessControl).interfaceId));
        assertFalse(orchestrator.supportsInterface(0xffffffff), "erc165 sentinel");
    }

    function testFuzzSupportsInterfaceFalse(bytes4 interfaceId) external view {
        vm.assume(interfaceId != type(IERC1155Receiver).interfaceId);
        vm.assume(interfaceId != type(IST0xOrchestratorV1).interfaceId);
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

    /// `burnInfo` is forwarded VERBATIM to `vault.redeem` as the audit-trail
    /// `receiptInformation`: the interface promises it, indexers rely on it.
    function testBurnForwardsBurnInfoToRedeem() external {
        _grant(orchestrator.BURN_ROLE(), address(this));
        _seedPointer(TOKEN, 0);
        uint256 amount = 300;
        bytes memory burnInfo = hex"c0ffee0123";
        _mockHighwater(TOKEN, 1);
        _mockERC20(TOKEN);
        _mockBalance(RECEIPT_ADDR, 0, amount);
        _mockRedeem(TOKEN, amount, 0, burnInfo);

        vm.expectCall(
            TOKEN,
            abi.encodeWithSelector(
                ReceiptVault.redeem.selector, amount, address(orchestrator), address(orchestrator), uint256(0), burnInfo
            )
        );
        vm.expectEmit(true, true, true, true, address(orchestrator));
        emit IST0xOrchestratorV1.Burned(address(this), TOKEN, amount, 0, 1);
        orchestrator.burn(TOKEN, amount, burnInfo);
        assertEq(orchestrator.nextBurnReceiptId(TOKEN), 1);
    }

    /// `burn` holds the ReentrancyGuardTransient lock for the whole
    /// entrypoint: a token whose `transferFrom` reenters `burn` must see the
    /// nested call revert `ReentrancyGuardReentrantCall` (the pointer write
    /// after external calls in `_burnWalk` is only safe under this lock),
    /// while the outer burn completes normally.
    function testBurnReentrantCallReverts() external {
        ReentrantBurnVault attacker = new ReentrantBurnVault(orchestrator);
        _grant(orchestrator.BURN_ROLE(), address(this));
        // The nested call comes FROM the attacker, so it passes the role
        // check and reaches the reentrancy guard.
        _grant(orchestrator.BURN_ROLE(), address(attacker));

        vm.expectEmit(true, true, true, true, address(orchestrator));
        emit IST0xOrchestratorV1.Burned(address(this), address(attacker), 100, 0, 0);
        orchestrator.burn(address(attacker), 100, "");

        assertTrue(attacker.reentryAttempted(), "attacker must have attempted reentry");
        assertFalse(attacker.reentrySucceeded(), "nested burn must not succeed");
        assertEq(
            attacker.reentryRevertData(),
            abi.encodeWithSelector(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector),
            "nested burn must revert ReentrancyGuardReentrantCall"
        );
    }

    /// A sender whose `manager()` probe REVERTS with exactly 32 bytes of
    /// returndata (decoding to a vault whose `receipt()` round-trips back to
    /// the sender) must be treated as foreign: accepted, no pointer move, no
    /// `BurnIndexLowered`. Only the `!ok` guard on the manager() staticcall
    /// separates this revert payload from a genuine manager() answer.
    function testOnERC1155ReceivedManagerRevert32BytesNoOp() external {
        address fakeVault = address(0xFA6E);
        MockManagerRevert1155 evil = new MockManagerRevert1155(fakeVault);
        // Make the round-trip leg pass so the ONLY thing rejecting the
        // sender is the failure status of the manager() probe itself.
        vm.mockCall(fakeVault, abi.encodeWithSelector(ReceiptVault.receipt.selector), abi.encode(address(evil)));
        _seedPointer(fakeVault, 10);

        vm.recordLogs();
        vm.prank(address(evil));
        bytes4 ret = orchestrator.onERC1155Received(address(this), BOB, 5, 1, "");
        assertEq(ret, IERC1155Receiver.onERC1155Received.selector);
        assertEq(orchestrator.nextBurnReceiptId(fakeVault), 10, "reverting manager() probe must not move the pointer");
        assertEq(vm.getRecordedLogs().length, 0, "no BurnIndexLowered may be emitted for a reverting manager() probe");
    }

    /// Sibling of the manager()-probe guard: a sender whose manager() probe
    /// SUCCEEDS (returns a vault), but whose vault's receipt() probe REVERTS
    /// with exactly 32 bytes decoding to the sender itself, must still be
    /// treated as foreign: accepted, no pointer move, no BurnIndexLowered.
    /// Only the `!ok` half of the guard on the receipt() staticcall separates
    /// that revert payload from a genuine round-tripping receipt() answer that
    /// would (wrongly) lower the pointer.
    function testOnERC1155ReceivedReceiptRevert32BytesNoOp() external {
        address evil = address(0xE711);
        address fakeVault = address(0xFA6E);
        // manager() probe succeeds and points at fakeVault.
        vm.mockCall(evil, abi.encodeWithSelector(IReceiptV3.manager.selector), abi.encode(fakeVault));
        // receipt() probe REVERTS with 32 bytes that decode back to the
        // sender, so dropping the `!ok` guard would let it round-trip.
        vm.mockCallRevert(fakeVault, abi.encodeWithSelector(ReceiptVault.receipt.selector), abi.encode(evil));
        _seedPointer(fakeVault, 10);

        vm.recordLogs();
        vm.prank(evil);
        bytes4 ret = orchestrator.onERC1155Received(address(this), BOB, 5, 1, "");
        assertEq(ret, IERC1155Receiver.onERC1155Received.selector);
        assertEq(orchestrator.nextBurnReceiptId(fakeVault), 10, "reverting receipt() probe must not move the pointer");
        assertEq(vm.getRecordedLogs().length, 0, "no BurnIndexLowered may be emitted for a reverting receipt() probe");
    }

    /// A sender whose `manager()` probe succeeds but names a CODE-LESS claimed
    /// vault is treated as foreign: the `vault.receipt()` staticcall to an
    /// address with no code succeeds with EMPTY returndata, so the
    /// `ret.length != 32` half of the second-probe guard bails. Accepted, no
    /// pointer move, no `BurnIndexLowered`.
    function testOnERC1155ReceivedCodelessClaimedVaultNoOp() external {
        address codelessVault = address(0xC0DE1E55);
        _mockManager(FOREIGN_1155, codelessVault);
        _seedPointer(codelessVault, 10);

        vm.recordLogs();
        vm.prank(FOREIGN_1155);
        bytes4 ret = orchestrator.onERC1155Received(address(this), BOB, 5, 1, "");
        assertEq(ret, IERC1155Receiver.onERC1155Received.selector);
        assertEq(orchestrator.nextBurnReceiptId(codelessVault), 10, "code-less claimed vault must not move the pointer");
        assertEq(vm.getRecordedLogs().length, 0, "no BurnIndexLowered for a code-less claimed vault");
    }

    /// A sender whose `manager()` probe succeeds but whose claimed vault
    /// REVERTS on `receipt()` is treated as foreign: the `!ok` half of the
    /// second-probe guard bails. Accepted, no pointer move, no
    /// `BurnIndexLowered`.
    function testOnERC1155ReceivedRevertingClaimedVaultNoOp() external {
        address claimedVault = address(0xDEAD5EA7);
        _mockManager(FOREIGN_1155, claimedVault);
        vm.mockCallRevert(claimedVault, abi.encodeWithSelector(ReceiptVault.receipt.selector), "");
        _seedPointer(claimedVault, 10);

        vm.recordLogs();
        vm.prank(FOREIGN_1155);
        bytes4 ret = orchestrator.onERC1155Received(address(this), BOB, 5, 1, "");
        assertEq(ret, IERC1155Receiver.onERC1155Received.selector);
        assertEq(orchestrator.nextBurnReceiptId(claimedVault), 10, "reverting claimed vault must not move the pointer");
        assertEq(vm.getRecordedLogs().length, 0, "no BurnIndexLowered for a reverting claimed vault");
    }

    // ------------------------------------------------------------------ //
    //                             Mint caps                              //
    // ------------------------------------------------------------------ //

    /// Grant `minter` `MINT_ROLE` on `o`. The role is read BEFORE the prank so
    /// the view call doesn't consume it.
    function _grantMintOn(ST0xOrchestrator o, address minter) internal {
        bytes32 mintRole = o.MINT_ROLE();
        vm.prank(OWNER);
        o.grantRole(mintRole, minter);
    }

    /// Mock the vault side of a mint of EXACTLY `amount` on `token` into `o`:
    /// `vault.mint` returns matching assets and the share transfer succeeds.
    /// Everything vault-side being mocked is what leaves the cap path as the
    /// only thing these tests can fail on.
    function _mockCapMint(ST0xOrchestrator o, address token, uint256 amount) internal {
        vm.mockCall(token, abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
        vm.mockCall(
            token,
            abi.encodeWithSelector(ReceiptVault.mint.selector, amount, address(o), uint256(0), ""),
            abi.encode(amount)
        );
    }

    /// Mint `amount` of `token` from `minter` through `o` to `capRecipient`.
    function _capMint(ST0xOrchestrator o, address minter, address token, uint256 amount, bytes32 nonce) internal {
        _mockCapMint(o, token, amount);
        vm.prank(minter);
        o.mint(token, address(capRecipient), amount, _auth("", nonce), "");
    }

    /// A proxy with NOTHING configured: every limit is zero, so it mints
    /// nothing at all until a test sets the one limit it is about.
    function _unconfiguredOrchestrator() internal returns (ST0xOrchestrator) {
        return _deployProxy(OWNER);
    }

    /// Level 1 of "unset ⇒ 0 ⇒ rejected": with the global limit never set, no
    /// mint succeeds for anyone, however wide the per-token default and the
    /// per-minter override are.
    function testMintGlobalLimitUnsetReverts() external {
        ST0xOrchestrator fresh = _unconfiguredOrchestrator();
        _grantMintOn(fresh, MINTER_A);
        vm.startPrank(OWNER);
        fresh.setTokenMintLimit(TOKEN, 0, 100e18, 1e18);
        fresh.setMinterMintLimit(MINTER_A, TOKEN, 0, 100e18, 1e18);
        vm.stopPrank();

        assertEq(fresh.globalMintLimit().capacity, 0, "global capacity must start at zero");
        assertEq(fresh.mintHeadroom(MINTER_A, TOKEN), 0, "global zero must floor the headroom");

        _mockCapMint(fresh, TOKEN, 1e18);
        vm.expectRevert(abi.encodeWithSelector(IST0xOrchestratorV1.GlobalMintLimitUnset.selector));
        vm.prank(MINTER_A);
        fresh.mint(TOKEN, address(capRecipient), 1e18, _auth("", keccak256("global-unset")), "");
    }

    /// Level 2 of "unset ⇒ 0 ⇒ rejected": a token with no default, and a
    /// minter with no override for it, cannot mint that token even with the
    /// global limit wide open.
    function testMintTokenLimitUnsetReverts() external {
        ST0xOrchestrator fresh = _unconfiguredOrchestrator();
        _grantMintOn(fresh, MINTER_A);
        vm.prank(OWNER);
        fresh.setGlobalMintLimit(TOKEN, 0, UNBOUNDED_CAPACITY, 0);

        assertEq(fresh.tokenMintLimit(TOKEN).capacity, 0, "token default must start at zero");
        assertFalse(fresh.minterMintLimitOverride(MINTER_A, TOKEN).set, "no override may be set");
        assertEq(fresh.mintLimit(MINTER_A, TOKEN).capacity, 0, "resolved capacity must be zero");

        _mockCapMint(fresh, TOKEN, 1e18);
        vm.expectRevert(abi.encodeWithSelector(IST0xOrchestratorV1.MinterMintLimitUnset.selector, MINTER_A, TOKEN));
        vm.prank(MINTER_A);
        fresh.mint(TOKEN, address(capRecipient), 1e18, _auth("", keccak256("token-unset")), "");
    }

    /// Level 3 of "unset ⇒ 0 ⇒ rejected", and the explicit-zero override in
    /// one test: a minter pinned to zero for ONE token cannot mint it, while
    /// the token's non-zero default still serves every other minter AND that
    /// same minter can still mint every other token. That is what the `set`
    /// marker buys — a zero override is distinct from no override, and is
    /// narrower than revoking `MINT_ROLE`.
    function testMintZeroOverrideBlocksOnePairOnly() external {
        _grantMintOn(orchestrator, MINTER_A);
        _grantMintOn(orchestrator, MINTER_B);
        vm.prank(OWNER);
        orchestrator.setMinterMintLimit(MINTER_A, TOKEN, 0, 0, 0);

        MintLimitOverrideV1 memory pinned = orchestrator.minterMintLimitOverride(MINTER_A, TOKEN);
        assertTrue(pinned.set, "a deliberate zero must read back as SET");
        assertEq(pinned.limit.capacity, 0, "pinned capacity");
        assertEq(orchestrator.mintHeadroom(MINTER_A, TOKEN), 0, "pinned pair has no headroom");

        _mockCapMint(orchestrator, TOKEN, 1e18);
        vm.expectRevert(
            abi.encodeWithSelector(IST0xOrchestratorV1.MinterMintCapExceeded.selector, MINTER_A, TOKEN, 0, 0, 1e18)
        );
        vm.prank(MINTER_A);
        orchestrator.mint(TOKEN, address(capRecipient), 1e18, _auth("", keccak256("pinned")), "");

        // The token's default is untouched for a minter without an override.
        _capMint(orchestrator, MINTER_B, TOKEN, 1e18, keccak256("other-minter"));
        // And the pinned minter is only pinned for THAT token.
        _capMint(orchestrator, MINTER_A, TOKEN2, 1e18, keccak256("other-token"));
    }

    /// The override, when set, replaces the token default in both directions:
    /// wider than the default lifts the pair above it, narrower binds below
    /// it. It is a replacement, never a minimum or a maximum of the two.
    function testMintOverrideReplacesTokenDefaultBothWays() external {
        _grantMintOn(orchestrator, MINTER_A);
        _grantMintOn(orchestrator, MINTER_B);
        vm.startPrank(OWNER);
        orchestrator.setTokenMintLimit(TOKEN, 0, 10e18, 0);
        orchestrator.setMinterMintLimit(MINTER_A, TOKEN, 0, 50e18, 0);
        orchestrator.setMinterMintLimit(MINTER_B, TOKEN, 0, 1e18, 0);
        vm.stopPrank();

        assertEq(orchestrator.mintLimit(MINTER_A, TOKEN).capacity, 50e18, "wider override resolves");
        assertEq(orchestrator.mintLimit(MINTER_B, TOKEN).capacity, 1e18, "narrower override resolves");

        // A above the token default: allowed by its own wider override.
        _capMint(orchestrator, MINTER_A, TOKEN, 50e18, keccak256("wide"));

        // B below the token default: its narrower override binds.
        _mockCapMint(orchestrator, TOKEN, 2e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.MinterMintCapExceeded.selector, MINTER_B, TOKEN, 1e18, 1e18, 2e18
            )
        );
        vm.prank(MINTER_B);
        orchestrator.mint(TOKEN, address(capRecipient), 2e18, _auth("", keccak256("narrow")), "");
    }

    /// The boundary: `mintHeadroom` names exactly what fits, that amount
    /// succeeds, and one unit more reverts — before the mint and again after
    /// it, when the bucket is spent.
    function testMintBoundaryExactAmountFitsOneMoreReverts() external {
        uint256 capacity = 10e18;
        _grantMintOn(orchestrator, MINTER_A);
        vm.prank(OWNER);
        orchestrator.setTokenMintLimit(TOKEN, 0, capacity, 0);

        assertEq(orchestrator.mintHeadroom(MINTER_A, TOKEN), capacity, "a fresh bucket offers one capacity");

        _mockCapMint(orchestrator, TOKEN, capacity + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.MinterMintCapExceeded.selector, MINTER_A, TOKEN, capacity, capacity, capacity + 1
            )
        );
        vm.prank(MINTER_A);
        orchestrator.mint(TOKEN, address(capRecipient), capacity + 1, _auth("", keccak256("over")), "");

        // Exactly the headroom fits.
        _capMint(orchestrator, MINTER_A, TOKEN, capacity, keccak256("exact"));

        // And the bucket is spent at that same second, with no leak rate to
        // refill it.
        assertEq(orchestrator.mintHeadroom(MINTER_A, TOKEN), 0, "a spent bucket offers nothing");
        _mockCapMint(orchestrator, TOKEN, 1);
        vm.expectRevert(
            abi.encodeWithSelector(IST0xOrchestratorV1.MinterMintCapExceeded.selector, MINTER_A, TOKEN, capacity, 0, 1)
        );
        vm.prank(MINTER_A);
        orchestrator.mint(TOKEN, address(capRecipient), 1, _auth("", keccak256("spent")), "");
    }

    /// Per-minter isolation: one minter exhausting its bucket for a token
    /// leaves another minter's bucket for the SAME token untouched.
    function testMintPerMinterIsolation() external {
        uint256 capacity = 10e18;
        _grantMintOn(orchestrator, MINTER_A);
        _grantMintOn(orchestrator, MINTER_B);
        vm.prank(OWNER);
        orchestrator.setTokenMintLimit(TOKEN, 0, capacity, 0);

        _capMint(orchestrator, MINTER_A, TOKEN, capacity, keccak256("a-drain"));
        assertEq(orchestrator.mintHeadroom(MINTER_A, TOKEN), 0, "A's bucket is spent");
        assertEq(orchestrator.mintHeadroom(MINTER_B, TOKEN), capacity, "B's bucket is untouched");

        _capMint(orchestrator, MINTER_B, TOKEN, capacity, keccak256("b-full"));
    }

    /// Per-token isolation: one minter exhausting its bucket for one token
    /// leaves its OWN bucket for another token untouched.
    function testMintPerTokenIsolation() external {
        uint256 capacity = 10e18;
        _grantMintOn(orchestrator, MINTER_A);
        vm.startPrank(OWNER);
        orchestrator.setTokenMintLimit(TOKEN, 0, capacity, 0);
        orchestrator.setTokenMintLimit(TOKEN2, 0, capacity, 0);
        vm.stopPrank();

        _capMint(orchestrator, MINTER_A, TOKEN, capacity, keccak256("token-drain"));
        assertEq(orchestrator.mintHeadroom(MINTER_A, TOKEN), 0, "TOKEN's bucket is spent");
        assertEq(orchestrator.mintHeadroom(MINTER_A, TOKEN2), capacity, "TOKEN2's bucket is untouched");

        _capMint(orchestrator, MINTER_A, TOKEN2, capacity, keccak256("token2-full"));
    }

    /// The global bucket binds independently of the per-pair one: with the
    /// per-pair capacity left unbounded, the global bucket alone rejects the
    /// mint, and the revert names the GLOBAL cap rather than the pair's.
    function testMintGlobalBucketBindsIndependently() external {
        uint256 globalCapacity = 10e18;
        _grantMintOn(orchestrator, MINTER_A);
        _grantMintOn(orchestrator, MINTER_B);
        // setUp leaves TOKEN's default unbounded; only the global is narrowed.
        vm.prank(OWNER);
        orchestrator.setGlobalMintLimit(TOKEN, 0, globalCapacity, 0);

        _capMint(orchestrator, MINTER_A, TOKEN, globalCapacity, keccak256("global-drain"));

        // B's own bucket is untouched and unbounded; the global one is spent.
        assertEq(orchestrator.mintLimit(MINTER_B, TOKEN).capacity, UNBOUNDED_CAPACITY, "B's pair capacity is unbounded");
        assertEq(orchestrator.mintHeadroom(MINTER_B, TOKEN), 0, "the global bucket floors B's headroom");

        _mockCapMint(orchestrator, TOKEN, 1);
        vm.expectRevert(
            abi.encodeWithSelector(IST0xOrchestratorV1.GlobalMintCapExceeded.selector, globalCapacity, 0, 1)
        );
        vm.prank(MINTER_B);
        orchestrator.mint(TOKEN, address(capRecipient), 1, _auth("", keccak256("global-bound")), "");
    }

    /// The per-pair bucket drains over time at `leakRate`: after being spent,
    /// exactly `elapsed * leakRate` comes back, and one unit more does not.
    function testMintPairBucketDrainsOverTime() external {
        uint256 capacity = 10e18;
        uint256 leakRate = 1e18;
        _grantMintOn(orchestrator, MINTER_A);
        vm.prank(OWNER);
        orchestrator.setTokenMintLimit(TOKEN, 0, capacity, leakRate);

        _capMint(orchestrator, MINTER_A, TOKEN, capacity, keccak256("drain"));
        assertEq(orchestrator.mintHeadroom(MINTER_A, TOKEN), 0, "spent at the filling second");

        vm.warp(block.timestamp + 4);
        uint256 leaked = 4 * leakRate;
        assertEq(orchestrator.mintHeadroom(MINTER_A, TOKEN), leaked, "four seconds of leak");

        _mockCapMint(orchestrator, TOKEN, leaked + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.MinterMintCapExceeded.selector, MINTER_A, TOKEN, capacity, leaked, leaked + 1
            )
        );
        vm.prank(MINTER_A);
        orchestrator.mint(TOKEN, address(capRecipient), leaked + 1, _auth("", keccak256("too-soon")), "");

        _capMint(orchestrator, MINTER_A, TOKEN, leaked, keccak256("after-leak"));
    }

    /// The global bucket drains on the same terms — it is a second bucket,
    /// not a shared reading of the first.
    function testMintGlobalBucketDrainsOverTime() external {
        uint256 globalCapacity = 10e18;
        uint256 leakRate = 1e18;
        _grantMintOn(orchestrator, MINTER_A);
        vm.prank(OWNER);
        orchestrator.setGlobalMintLimit(TOKEN, 0, globalCapacity, leakRate);

        _capMint(orchestrator, MINTER_A, TOKEN, globalCapacity, keccak256("global-drain"));
        assertEq(orchestrator.mintHeadroom(MINTER_A, TOKEN), 0, "global spent at the filling second");

        vm.warp(block.timestamp + 3);
        uint256 leaked = 3 * leakRate;
        assertEq(orchestrator.mintHeadroom(MINTER_A, TOKEN), leaked, "three seconds of global leak");

        _mockCapMint(orchestrator, TOKEN, leaked + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.GlobalMintCapExceeded.selector, globalCapacity, leaked, leaked + 1
            )
        );
        vm.prank(MINTER_A);
        orchestrator.mint(TOKEN, address(capRecipient), leaked + 1, _auth("", keccak256("global-too-soon")), "");

        _capMint(orchestrator, MINTER_A, TOKEN, leaked, keccak256("global-after-leak"));
    }

    /// Idling banks no credit: however long a bucket sits untouched, the most
    /// a single mint can take is one `capacity`, never the leak that would
    /// have accrued over the idle time.
    function testMintIdlingNeverExceedsCapacity() external {
        uint256 capacity = 10e18;
        uint256 leakRate = 1e18;
        _grantMintOn(orchestrator, MINTER_A);
        vm.prank(OWNER);
        orchestrator.setTokenMintLimit(TOKEN, 0, capacity, leakRate);

        // A million seconds at one token per second is 1e6 tokens of leak,
        // five orders of magnitude above the capacity.
        vm.warp(block.timestamp + 1_000_000);
        assertEq(orchestrator.mintHeadroom(MINTER_A, TOKEN), capacity, "idling cannot enlarge a burst");

        _mockCapMint(orchestrator, TOKEN, capacity + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.MinterMintCapExceeded.selector, MINTER_A, TOKEN, capacity, capacity, capacity + 1
            )
        );
        vm.prank(MINTER_A);
        orchestrator.mint(TOKEN, address(capRecipient), capacity + 1, _auth("", keccak256("idle")), "");
    }

    /// Clearing an override changes the POLICY, not the credit already
    /// consumed: the pair falls back to the token default with its bucket
    /// still where the earlier mints left it.
    function testClearMinterMintLimitKeepsBucketLevel() external {
        _grantMintOn(orchestrator, MINTER_A);
        vm.startPrank(OWNER);
        orchestrator.setTokenMintLimit(TOKEN, 0, 10e18, 0);
        orchestrator.setMinterMintLimit(MINTER_A, TOKEN, 0, 6e18, 0);
        vm.stopPrank();

        _capMint(orchestrator, MINTER_A, TOKEN, 6e18, keccak256("under-override"));

        vm.expectEmit(true, true, true, true, address(orchestrator));
        emit IST0xOrchestratorV1.MinterMintLimitCleared(MINTER_A, TOKEN);
        vm.prank(OWNER);
        orchestrator.clearMinterMintLimit(MINTER_A, TOKEN);

        assertFalse(orchestrator.minterMintLimitOverride(MINTER_A, TOKEN).set, "override must be gone");
        assertEq(orchestrator.mintLimit(MINTER_A, TOKEN).capacity, 10e18, "falls back to the token default");
        // The level is still 6e18, so the 10e18 default leaves 4e18, not 10e18.
        assertEq(orchestrator.mintHeadroom(MINTER_A, TOKEN), 4e18, "the consumed level survives the clear");
    }

    /// Lowering a capacity below the outstanding level binds immediately: the
    /// headroom reads zero and the next mint is refused, with no migration and
    /// no window to front-run the change.
    function testLoweringCapacityBelowLevelBindsImmediately() external {
        _grantMintOn(orchestrator, MINTER_A);
        vm.prank(OWNER);
        orchestrator.setTokenMintLimit(TOKEN, 0, 10e18, 0);
        _capMint(orchestrator, MINTER_A, TOKEN, 8e18, keccak256("before-lowering"));

        vm.prank(OWNER);
        orchestrator.setTokenMintLimit(TOKEN, 0, 2e18, 0);

        assertEq(orchestrator.mintHeadroom(MINTER_A, TOKEN), 0, "a level above the new capacity leaves no headroom");
        _mockCapMint(orchestrator, TOKEN, 1);
        vm.expectRevert(
            abi.encodeWithSelector(IST0xOrchestratorV1.MinterMintCapExceeded.selector, MINTER_A, TOKEN, 2e18, 0, 1)
        );
        vm.prank(MINTER_A);
        orchestrator.mint(TOKEN, address(capRecipient), 1, _auth("", keccak256("after-lowering")), "");
    }

    // ------------------------------------------------------------------ //
    //                        Mint-cap setters                            //
    // ------------------------------------------------------------------ //

    function testFuzzSetGlobalMintLimitUnauthorized(address caller, uint256 capacity, uint256 leakRate) external {
        vm.assume(!orchestrator.hasRole(orchestrator.DEFAULT_ADMIN_ROLE(), caller));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, orchestrator.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(caller);
        orchestrator.setGlobalMintLimit(TOKEN, 0, capacity, leakRate);
    }

    function testFuzzSetTokenMintLimitUnauthorized(address caller, address token, uint256 capacity, uint256 leakRate)
        external
    {
        vm.assume(!orchestrator.hasRole(orchestrator.DEFAULT_ADMIN_ROLE(), caller));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, orchestrator.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(caller);
        orchestrator.setTokenMintLimit(token, 0, capacity, leakRate);
    }

    function testFuzzSetMinterMintLimitUnauthorized(address caller, address minter, address token, uint256 capacity)
        external
    {
        vm.assume(!orchestrator.hasRole(orchestrator.DEFAULT_ADMIN_ROLE(), caller));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, orchestrator.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(caller);
        orchestrator.setMinterMintLimit(minter, token, 0, capacity, 0);
    }

    function testFuzzClearMinterMintLimitUnauthorized(address caller, address minter, address token) external {
        vm.assume(!orchestrator.hasRole(orchestrator.DEFAULT_ADMIN_ROLE(), caller));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, orchestrator.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(caller);
        orchestrator.clearMinterMintLimit(minter, token);
    }

    /// `MINT_ROLE` is not `DEFAULT_ADMIN_ROLE`: the key the cap exists to
    /// bound cannot raise its own cap.
    function testMintRoleCannotSetItsOwnCap() external {
        _grantMintOn(orchestrator, MINTER_A);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, MINTER_A, orchestrator.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(MINTER_A);
        orchestrator.setMinterMintLimit(MINTER_A, TOKEN, 0, type(uint128).max, 0);
    }

    function testFuzzSetGlobalMintLimitEmitsAndReads(uint256 capacity, uint256 leakRate) external {
        capacity = bound(capacity, 0, LEAKY_BUCKET_LEVEL_MAX);
        vm.expectEmit(true, true, true, true, address(orchestrator));
        emit IST0xOrchestratorV1.GlobalMintLimitSet(TOKEN, 0, capacity, leakRate);
        vm.prank(OWNER);
        orchestrator.setGlobalMintLimit(TOKEN, 0, capacity, leakRate);

        MintLimitV1 memory limit = orchestrator.globalMintLimit();
        assertEq(limit.capacity, capacity, "global capacity");
        assertEq(limit.leakRate, leakRate, "global leak rate");
    }

    function testFuzzSetTokenMintLimitEmitsAndReads(address token, uint256 capacity, uint256 leakRate) external {
        _assumeMockableToken(token);
        _mockCorporateActions(token, 0, LibDecimalFloat.FLOAT_ONE);
        capacity = bound(capacity, 0, LEAKY_BUCKET_LEVEL_MAX);
        vm.expectEmit(true, true, true, true, address(orchestrator));
        emit IST0xOrchestratorV1.TokenMintLimitSet(token, 0, capacity, leakRate);
        vm.prank(OWNER);
        orchestrator.setTokenMintLimit(token, 0, capacity, leakRate);

        MintLimitV1 memory limit = orchestrator.tokenMintLimit(token);
        assertEq(limit.capacity, capacity, "token capacity");
        assertEq(limit.leakRate, leakRate, "token leak rate");
        // With no override for the pair, the token default is what resolves.
        MintLimitV1 memory resolved = orchestrator.mintLimit(MINTER_A, token);
        assertEq(resolved.capacity, capacity, "resolved capacity");
        assertEq(resolved.leakRate, leakRate, "resolved leak rate");
    }

    function testFuzzSetMinterMintLimitEmitsAndReads(address minter, address token, uint256 capacity, uint256 leakRate)
        external
    {
        _assumeMockableToken(token);
        _mockCorporateActions(token, 0, LibDecimalFloat.FLOAT_ONE);
        capacity = bound(capacity, 0, LEAKY_BUCKET_LEVEL_MAX);
        vm.expectEmit(true, true, true, true, address(orchestrator));
        emit IST0xOrchestratorV1.MinterMintLimitSet(minter, token, 0, capacity, leakRate);
        vm.prank(OWNER);
        orchestrator.setMinterMintLimit(minter, token, 0, capacity, leakRate);

        MintLimitOverrideV1 memory pairOverride = orchestrator.minterMintLimitOverride(minter, token);
        assertTrue(pairOverride.set, "override must read back as set");
        assertEq(pairOverride.limit.capacity, capacity, "override capacity");
        assertEq(pairOverride.limit.leakRate, leakRate, "override leak rate");
        // The override, not the (still unset) token default, is what resolves.
        MintLimitV1 memory resolved = orchestrator.mintLimit(minter, token);
        assertEq(resolved.capacity, capacity, "resolved capacity");
        assertEq(resolved.leakRate, leakRate, "resolved leak rate");
    }

    /// A capacity the packed bucket codec cannot enforce is refused where it
    /// is WRITTEN, on every setter, rather than surfacing later as a mint that
    /// can never succeed.
    function testFuzzSetMintLimitCapacityOverflowReverts(uint256 capacity) external {
        capacity = bound(capacity, LEAKY_BUCKET_LEVEL_MAX + 1, type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(LeakyBucketCapacityOverflow.selector, capacity));
        vm.prank(OWNER);
        orchestrator.setGlobalMintLimit(TOKEN, 0, capacity, 0);

        vm.expectRevert(abi.encodeWithSelector(LeakyBucketCapacityOverflow.selector, capacity));
        vm.prank(OWNER);
        orchestrator.setTokenMintLimit(TOKEN, 0, capacity, 0);

        vm.expectRevert(abi.encodeWithSelector(LeakyBucketCapacityOverflow.selector, capacity));
        vm.prank(OWNER);
        orchestrator.setMinterMintLimit(MINTER_A, TOKEN, 0, capacity, 0);
    }

    // ------------------------------------------------------------------ //
    //              Mint caps — genesis denomination and cursor            //
    // ------------------------------------------------------------------ //

    /// A rebase rescales the cap by construction. The cap is written once, in
    /// genesis units, and nobody touches it again: after a 2-for-1 split the
    /// same stored `100e18` admits exactly `200e18` current units and refuses
    /// one more. There is no admin transaction to sequence behind the action,
    /// and therefore no window between the action and a re-pricing.
    function testForwardSplitRescalesTheCapWithNoAdminWrite() external {
        _grantMintOn(orchestrator, MINTER_A);
        vm.prank(OWNER);
        orchestrator.setTokenMintLimit(TOKEN, 0, 100e18, 0);
        assertEq(orchestrator.mintHeadroom(MINTER_A, TOKEN), 100e18, "genesis and current coincide before an action");

        // The split completes. Nothing writes to the orchestrator.
        _mockCorporateActions(TOKEN, 1, LibDecimalFloat.packLossless(2, 0));

        assertEq(orchestrator.tokenMintLimit(TOKEN).capacity, 100e18, "the stored cap is untouched");
        assertEq(orchestrator.mintHeadroom(MINTER_A, TOKEN), 200e18, "the same cap admits twice the units");

        // One current unit past it is `100e18 + 1` genesis units (the half
        // unit rounds up), against `100e18` of genesis headroom.
        _mockCapMint(orchestrator, TOKEN, 200e18 + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.MinterMintCapExceeded.selector, MINTER_A, TOKEN, 100e18, 100e18, 100e18 + 1
            )
        );
        vm.prank(MINTER_A);
        orchestrator.mint(TOKEN, address(capRecipient), 200e18 + 1, _auth("", keccak256("split-over")), "");

        _capMint(orchestrator, MINTER_A, TOKEN, 200e18, keccak256("split-exact"));
        assertEq(orchestrator.mintHeadroom(MINTER_A, TOKEN), 0, "the rescaled burst is spent exactly");
    }

    /// The direction a current-unit denomination got dangerously wrong. A
    /// 1-for-10 consolidation makes each current unit worth ten pre-action
    /// units, so a cap left in current units would have authorised ten times
    /// the value it was approved for. In genesis units the same stored
    /// `100e18` admits `10e18` current units — the same economic size as
    /// before the action — and refuses one more.
    function testConsolidationTightensTheCapInCurrentUnits() external {
        _grantMintOn(orchestrator, MINTER_A);
        vm.prank(OWNER);
        orchestrator.setTokenMintLimit(TOKEN, 0, 100e18, 0);

        _mockCorporateActions(TOKEN, 1, LibDecimalFloat.packLossless(1, -1));

        assertEq(orchestrator.tokenMintLimit(TOKEN).capacity, 100e18, "the stored cap is untouched");
        assertEq(orchestrator.mintHeadroom(MINTER_A, TOKEN), 10e18, "one tenth the units, the same value");

        _mockCapMint(orchestrator, TOKEN, 10e18 + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.MinterMintCapExceeded.selector, MINTER_A, TOKEN, 100e18, 100e18, 100e18 + 10
            )
        );
        vm.prank(MINTER_A);
        orchestrator.mint(TOKEN, address(capRecipient), 10e18 + 1, _auth("", keccak256("consolidation-over")), "");

        _capMint(orchestrator, MINTER_A, TOKEN, 10e18, keccak256("consolidation-exact"));
        assertEq(orchestrator.mintHeadroom(MINTER_A, TOKEN), 0, "the rescaled burst is spent exactly");
    }

    /// The rounding that is security-relevant, in the direction it was chosen.
    /// With a multiplier of three, one current wei is a third of a genesis
    /// wei. Rounded DOWN it would cost nothing and a minter could drain any
    /// bucket one wei at a time forever; rounded UP each such mint costs a
    /// whole genesis wei, so a two-wei bucket takes exactly two of them.
    function testConsumedAmountRoundsUpSoDustIsNeverFree() external {
        _grantMintOn(orchestrator, MINTER_A);
        vm.prank(OWNER);
        orchestrator.setTokenMintLimit(TOKEN, 0, 2, 0);
        _mockCorporateActions(TOKEN, 1, LibDecimalFloat.packLossless(3, 0));

        assertEq(orchestrator.mintHeadroom(MINTER_A, TOKEN), 6, "two genesis wei is six current wei");
        _capMint(orchestrator, MINTER_A, TOKEN, 1, keccak256("dust-1"));
        assertEq(orchestrator.mintHeadroom(MINTER_A, TOKEN), 3, "a third of a wei still cost a whole one");
        _capMint(orchestrator, MINTER_A, TOKEN, 1, keccak256("dust-2"));
        assertEq(orchestrator.mintHeadroom(MINTER_A, TOKEN), 0, "and so did the second");

        _mockCapMint(orchestrator, TOKEN, 1);
        vm.expectRevert(
            abi.encodeWithSelector(IST0xOrchestratorV1.MinterMintCapExceeded.selector, MINTER_A, TOKEN, 2, 0, 1)
        );
        vm.prank(MINTER_A);
        orchestrator.mint(TOKEN, address(capRecipient), 1, _auth("", keccak256("dust-3")), "");
    }

    /// The headroom view rounds the other way, and for the same reason: it
    /// answers "what may I pass as `amount`", so it must never name an amount
    /// that is then refused. Six current wei is the whole of a two-wei genesis
    /// bucket and one more does not fit.
    function testMintHeadroomNamesAnAmountThatFits() external {
        _grantMintOn(orchestrator, MINTER_A);
        vm.prank(OWNER);
        orchestrator.setTokenMintLimit(TOKEN, 0, 2, 0);
        _mockCorporateActions(TOKEN, 1, LibDecimalFloat.packLossless(3, 0));

        uint256 headroom = orchestrator.mintHeadroom(MINTER_A, TOKEN);
        assertEq(headroom, 6, "the largest amount the bucket takes");

        _mockCapMint(orchestrator, TOKEN, headroom + 1);
        vm.expectRevert(
            abi.encodeWithSelector(IST0xOrchestratorV1.MinterMintCapExceeded.selector, MINTER_A, TOKEN, 2, 2, 3)
        );
        vm.prank(MINTER_A);
        orchestrator.mint(TOKEN, address(capRecipient), headroom + 1, _auth("", keccak256("headroom-over")), "");

        _capMint(orchestrator, MINTER_A, TOKEN, headroom, keccak256("headroom-exact"));
    }

    /// The global bucket is a sum across tokens, and what it sums is genesis
    /// units: `200e18` of a token that has doubled charges it the same
    /// `100e18` as `100e18` of a token that has not. That is the property a
    /// cross-token cap needs and current units do not have.
    function testGlobalBucketSumsGenesisUnitsAcrossTokens() external {
        _grantMintOn(orchestrator, MINTER_A);
        vm.prank(OWNER);
        orchestrator.setGlobalMintLimit(TOKEN, 0, 200e18, 0);
        _mockCorporateActions(TOKEN, 1, LibDecimalFloat.packLossless(2, 0));

        _capMint(orchestrator, MINTER_A, TOKEN, 200e18, keccak256("global-doubled"));
        _capMint(orchestrator, MINTER_A, TOKEN2, 100e18, keccak256("global-plain"));

        _mockCapMint(orchestrator, TOKEN2, 1);
        vm.expectRevert(abi.encodeWithSelector(IST0xOrchestratorV1.GlobalMintCapExceeded.selector, 200e18, 0, 1));
        vm.prank(MINTER_A);
        orchestrator.mint(TOKEN2, address(capRecipient), 1, _auth("", keccak256("global-full")), "");
    }

    /// The window INSIDE the timelock, which the genesis denomination does not
    /// close on its own. The admin prices a cap in current units at proposal
    /// time and converts it with the multiplier they can see; the transaction
    /// executes after the delay. A split completing in between changes that
    /// conversion, so the queued genesis number would now enact `200e18`
    /// current units where `100e18` was approved. The cursor makes it a
    /// revert, and the re-proposal enacts what was actually approved.
    function testActionCompletingInsideTheTimelockWindowRevertsTheSet() external {
        _grantMintOn(orchestrator, MINTER_A);

        // Proposal time: cursor zero. The admin approves 100e18 and that is
        // the number the transaction carries — there is nothing for them to
        // convert.
        uint256 pricedAtCursor = ICorporateActionsV1(TOKEN).completedActionCount();
        assertEq(pricedAtCursor, 0, "priced against a token with no completed action");

        // The delay elapses, and a 2-for-1 split completes inside it.
        vm.warp(block.timestamp + 2 days);
        _mockCorporateActions(TOKEN, 1, LibDecimalFloat.packLossless(2, 0));

        vm.expectRevert(abi.encodeWithSelector(IST0xOrchestratorV1.MintLimitCursorMoved.selector, TOKEN, 0, 1));
        vm.prank(OWNER);
        orchestrator.setTokenMintLimit(TOKEN, pricedAtCursor, 100e18, 0);
        assertEq(orchestrator.tokenMintLimit(TOKEN).capacity, UNBOUNDED_CAPACITY, "nothing was written");

        // Re-proposed at the cursor the admin can now see, carrying the SAME
        // approved number. A stale set reverts; it never silently enacts a
        // different cap.
        vm.prank(OWNER);
        orchestrator.setTokenMintLimit(TOKEN, 1, 100e18, 0);
        assertEq(orchestrator.tokenMintLimit(TOKEN).capacity, 100e18, "stored as approved");
        assertEq(orchestrator.mintHeadroom(MINTER_A, TOKEN), 100e18, "the approved cap, enacted");
    }

    /// Same pin on the per-pair override, which is priced against the same
    /// token's denomination as the default it replaces.
    function testSetMinterMintLimitRevertsWhenTheCursorMoved() external {
        _mockCorporateActions(TOKEN, 4, LibDecimalFloat.packLossless(2, 0));

        vm.expectRevert(abi.encodeWithSelector(IST0xOrchestratorV1.MintLimitCursorMoved.selector, TOKEN, 3, 4));
        vm.prank(OWNER);
        orchestrator.setMinterMintLimit(MINTER_A, TOKEN, 3, 5e18, 0);
        assertFalse(orchestrator.minterMintLimitOverride(MINTER_A, TOKEN).set, "nothing was written");

        vm.prank(OWNER);
        orchestrator.setMinterMintLimit(MINTER_A, TOKEN, 4, 5e18, 0);
        assertEq(orchestrator.minterMintLimitOverride(MINTER_A, TOKEN).limit.capacity, 5e18, "the pinned set lands");
    }

    /// The ruling on the one open question the design left: the global limit
    /// is not per-token, so it is checked against the cursor of the
    /// DENOMINATION TOKEN the setter is given — the token whose current units
    /// the admin priced the cap in. Per-token cursors disagree, and the
    /// setter is told which one was used rather than guessing.
    function testGlobalMintLimitIsPinnedToItsDenominationTokensCursor() external {
        // TOKEN2 has had an action; TOKEN has not.
        _mockCorporateActions(TOKEN2, 1, LibDecimalFloat.packLossless(2, 0));

        // Priced against TOKEN2, a stale cursor is refused.
        vm.expectRevert(abi.encodeWithSelector(IST0xOrchestratorV1.MintLimitCursorMoved.selector, TOKEN2, 0, 1));
        vm.prank(OWNER);
        orchestrator.setGlobalMintLimit(TOKEN2, 0, 100e18, 0);
        assertEq(orchestrator.globalMintLimit().capacity, UNBOUNDED_CAPACITY, "nothing was written");

        // The SAME cursor value against TOKEN, which has not moved, goes
        // through — the two tokens disagree and only the named one governs.
        vm.expectEmit(true, true, true, true, address(orchestrator));
        emit IST0xOrchestratorV1.GlobalMintLimitSet(TOKEN, 0, 100e18, 0);
        vm.prank(OWNER);
        orchestrator.setGlobalMintLimit(TOKEN, 0, 100e18, 0);
        assertEq(orchestrator.globalMintLimit().capacity, 100e18, "the global cap is stored");

        // And against TOKEN2 at its real cursor it goes through too.
        vm.prank(OWNER);
        orchestrator.setGlobalMintLimit(TOKEN2, 1, 200e18, 0);
        assertEq(orchestrator.globalMintLimit().capacity, 200e18, "re-priced against the moved token");
    }

    /// `clearMinterMintLimit` takes no cursor, and this is what that means:
    /// it writes no converted number — it names no capacity, and the default
    /// it falls back to is already in genesis units — so an action completing
    /// inside the timelock cannot change what it does.
    function testClearMinterMintLimitIsNotPinnedToACursor() external {
        vm.prank(OWNER);
        orchestrator.setMinterMintLimit(MINTER_A, TOKEN, 0, 5e18, 0);

        _mockCorporateActions(TOKEN, 3, LibDecimalFloat.packLossless(2, 0));

        vm.expectEmit(true, true, true, true, address(orchestrator));
        emit IST0xOrchestratorV1.MinterMintLimitCleared(MINTER_A, TOKEN);
        vm.prank(OWNER);
        orchestrator.clearMinterMintLimit(MINTER_A, TOKEN);
        assertFalse(orchestrator.minterMintLimitOverride(MINTER_A, TOKEN).set, "the override is gone");
        assertEq(orchestrator.mintLimit(MINTER_A, TOKEN).capacity, UNBOUNDED_CAPACITY, "back to the token default");
    }

    /// The genesis denominator comes from the token, so a token that cannot
    /// answer cannot be metered — and an amount whose denomination cannot be
    /// established is refused, not metered at par. Fail closed, the same
    /// direction as every other unset value in the cap path.
    function testMintRevertsWhenTheTokenCannotAnswerItsDenomination() external {
        _grantMintOn(orchestrator, MINTER_A);
        bytes memory failure = abi.encodeWithSignature("FacetMustBeDelegatecalled()");
        vm.mockCallRevert(
            TOKEN, abi.encodeWithSelector(ICorporateActionsV1.cumulativeBalanceMultiplierSinceGenesis.selector), failure
        );

        _mockCapMint(orchestrator, TOKEN, 1e18);
        vm.expectRevert(failure);
        vm.prank(MINTER_A);
        orchestrator.mint(TOKEN, address(capRecipient), 1e18, _auth("", keccak256("mute-token")), "");
    }

    /// Same fail-closed rule on the setters' half: a token that cannot answer
    /// its cursor cannot have a cap priced against it at all.
    function testSetTokenMintLimitRevertsWhenTheTokenCannotAnswerItsCursor() external {
        bytes memory failure = abi.encodeWithSignature("FacetMustBeDelegatecalled()");
        vm.mockCallRevert(TOKEN, abi.encodeWithSelector(ICorporateActionsV1.completedActionCount.selector), failure);

        vm.expectRevert(failure);
        vm.prank(OWNER);
        orchestrator.setTokenMintLimit(TOKEN, 0, 5e18, 0);
    }

    /// An `amount` too wide for a `Float` coefficient is refused rather than
    /// converted from a value that was already truncated on the way in. It is
    /// ~2.7e49 whole tokens, far above any enforceable capacity, so refusing
    /// it costs nothing and converting a silently shrunk amount would be a
    /// discount.
    function testMintAmountTooWideForTheFloatCoefficientReverts() external {
        _grantMintOn(orchestrator, MINTER_A);
        uint256 amount = uint256(uint224(type(int224).max)) + 1;

        _mockCapMint(orchestrator, TOKEN, amount);
        vm.expectRevert(abi.encodeWithSelector(AmountNotRepresentableAsFloat.selector, amount));
        vm.prank(MINTER_A);
        orchestrator.mint(TOKEN, address(capRecipient), amount, _auth("", keccak256("too-wide")), "");
    }

    /// The whole point, as a property over a fuzzed domain rather than at
    /// three chosen multipliers: a capacity of `G` genesis units admits at
    /// most `G × multiplier` current units in a burst, whatever the
    /// multiplier is. The expectation is derived here from the integer ratio
    /// the multiplier was built from — plain `mulDiv` — rather than read back
    /// off the float path under test.
    function testFuzzCapAdmitsExactlyWhatItIsWorthAndNoMore(uint256 genesisCapacity, uint256 multiplierUnits) external {
        // A multiplier of `multiplierUnits / 1e6`, i.e. 1e-6 through 1e6.
        multiplierUnits = bound(multiplierUnits, 1, 1e12);
        genesisCapacity = bound(genesisCapacity, 1, 1e40);
        // Bounded by the caller, far inside int256, so this cannot truncate.
        // forge-lint: disable-next-line(unsafe-typecast)
        Float multiplier = LibDecimalFloat.packLossless(int256(multiplierUnits), -6);

        _grantMintOn(orchestrator, MINTER_A);
        vm.prank(OWNER);
        orchestrator.setTokenMintLimit(TOKEN, 0, genesisCapacity, 0);
        _mockCorporateActions(TOKEN, 1, multiplier);

        uint256 worth = Math.mulDiv(genesisCapacity, multiplierUnits, 1e6);
        assertEq(orchestrator.mintHeadroom(MINTER_A, TOKEN), worth, "the cap is worth exactly this many units");

        // One current unit past what the cap is worth costs strictly more
        // genesis credit than the cap holds, so it can never fit.
        uint256 overage = Math.mulDiv(worth + 1, 1e6, multiplierUnits, Math.Rounding.Ceil);
        _mockCapMint(orchestrator, TOKEN, worth + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.MinterMintCapExceeded.selector,
                MINTER_A,
                TOKEN,
                genesisCapacity,
                genesisCapacity,
                overage
            )
        );
        vm.prank(MINTER_A);
        orchestrator.mint(TOKEN, address(capRecipient), worth + 1, _auth("", keccak256("worth-over")), "");

        // And exactly what it is worth does fit, when there is any to mint.
        if (worth > 0) {
            _capMint(orchestrator, MINTER_A, TOKEN, worth, keccak256("worth-exact"));
        }
    }
}
