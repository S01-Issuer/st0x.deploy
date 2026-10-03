// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {
    ST0xOrchestrator,
    ST0X_TOKEN_OWNER_SAFE_NAME,
    ST0X_MIGRATION_NAMESPACE,
    ST0X_ORCHESTRATOR_MIGRATION_ADMIN_ROLES
} from "../../../src/concrete/ST0xOrchestrator.sol";
import {St0xAttestSubParserTest} from "./St0xAttestSubParserTest.sol";
import {IMintRecipient} from "../../../src/interface/IMintRecipient.sol";
import {IST0xVaultBeaconSet} from "../../../src/interface/IST0xVaultBeaconSet.sol";
import {IST0xOrchestratorV1, MintAuthV1, MintLimitV1, Digest} from "../../../src/interface/IST0xOrchestratorV1.sol";
import {Float, LibDecimalFloat} from "rain-math-float-0.2.4/src/lib/LibDecimalFloat.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {ICorporateActionsV1} from "../../../src/interface/ICorporateActionsV1.sol";

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
import {PreMintAdminOrchestrator} from "./PreMintAdminOrchestrator.sol";
import {LibTestAddressRegistry} from "../lib/LibTestAddressRegistry.sol";
import {LibTestMigrationRegistry} from "../lib/LibTestMigrationRegistry.sol";
import {IMigrationRegistryV2, MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.11/src/interface/IMigrationRegistryV2.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.11/src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.11/src/lib/LibMigrationRegistryDeploy.sol";
import {IAddressRegistryV1} from "rain-deploy-0.1.11/src/interface/IAddressRegistryV1.sol";
import {LibAddressRegistry} from "rain-deploy-0.1.11/src/lib/LibAddressRegistry.sol";
import {LibAddressRegistryDeploy} from "rain-deploy-0.1.11/src/lib/LibAddressRegistryDeploy.sol";
import {ReentrantMintRecipient} from "./ReentrantMintRecipient.sol";
import {ReentrantBurnVault} from "./ReentrantBurnVault.sol";
import {MockManagerRevert1155} from "./MockManagerRevert1155.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-contracts-5.6.1/utils/ReentrancyGuardTransient.sol";
import {OffchainAssetReceiptVault} from "rain-vats-0.2.1/src/concrete/vault/OffchainAssetReceiptVault.sol";
import {ReceiptVault} from "rain-vats-0.2.1/src/abstract/ReceiptVault.sol";
import {IReceiptV3} from "rain-vats-0.2.1/src/interface/IReceiptV3.sol";
import {SignedContextV1, EvaluableV4} from "rainlang-interface-0.2.9/src/interface/IInterpreterCallerV4.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.6.1/token/ERC20/extensions/IERC20Metadata.sol";

/// @dev Unit and fuzz tests for the singleton `ST0xOrchestrator`. The vault,
/// receipt, ERC-20 shares and the production beacon set are mocked via
/// `vm.mockCall` against fixed addresses; the orchestrator is deployed behind
/// a real `UpgradeableBeacon` + `BeaconProxy`.
///
/// Each "token" is a mock vault address on which the vault selectors
/// (`receipt()`, `highwaterId()`, `mint`, `redeem`), the ERC-20 selectors
/// (`transfer`, `transferFrom`) and, on the associated receipt address, the
/// ERC-1155 `balanceOf` (and `IReceiptV3.manager()` for the receiver-hook
/// tests) are mocked.
///
/// The mint weighting is real: the test Rainlang `St0xAttestSubParserTest`
/// binds, with the attest subparser beside it. The shared `setUp` installs
/// the identity weighting (`_: mint-amount();`) on tokens mocked at zero
/// decimals, so every mint here is charged `_f(amount)`. The weighting has
/// its own suite in `ST0xOrchestrator.mintWeighting.t.sol`.
contract ST0xOrchestratorTest is St0xAttestSubParserTest {
    using LibDecimalFloat for Float;

    /// Canonical placeholder vault ("token") + receipt addresses. Each is a
    /// distinct, code-less address that we mock every relevant selector on.
    address internal constant TOKEN = address(0xAA17);
    address internal constant RECEIPT_ADDR = address(0xEEC1D7);

    /// A second token to prove per-token pointer independence.
    address internal constant TOKEN2 = address(0xBB28);
    address internal constant RECEIPT_ADDR2 = address(0xEEC1D8);

    /// A code-less ERC-1155 that is not a production receipt (no `manager()`
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

    /// A capacity no amount in this suite comes near. `setUp` grants it so
    /// the tests that are not about the caps are not metered by them; the
    /// mint-cap tests set their own limits, and the fail-closed ones deploy a
    /// fresh, unconfigured proxy via `_deployProxy`.
    Float internal immutable UNBOUNDED_CAPACITY = LibDecimalFloat.packLossless(1, 60);

    /// A zero leak rate, so a spent bucket stays spent unless a test says
    /// otherwise.
    Float internal constant NO_LEAK = LibDecimalFloat.FLOAT_ZERO;

    /// Zero as a capacity, a level or a headroom: the same word as `NO_LEAK`,
    /// named for what it is compared against.
    Float internal constant ZERO = LibDecimalFloat.FLOAT_ZERO;
    ST0xOrchestrator internal impl;
    ST0xOrchestrator internal orchestrator;

    /// Callback recipients that authorise anything, so the mint-cap tests
    /// are about the buckets rather than the recipient authorisation (which
    /// has its own section above). Two of them, for the per-recipient
    /// isolation tests.
    MockMintRecipient internal capRecipient;
    MockMintRecipient internal capRecipient2;

    function setUp() public {
        capRecipient = new MockMintRecipient(true);
        capRecipient2 = new MockMintRecipient(true);
        impl = new ST0xOrchestrator();
        // `initialize` runs the vault-logic guard, so the guard mocks must be
        // in place before the proxy is deployed.
        _makeGuardPass();
        orchestrator = _deployProxy(OWNER);
        _setIdentityWeighting(orchestrator);
        _mockVaultTopology(TOKEN, RECEIPT_ADDR, "tAA17");
        _mockVaultTopology(TOKEN2, RECEIPT_ADDR2, "tBB28");
        // Mint caps fail closed, so a proxy with nothing configured mints
        // nothing at all. Grant both minters an unbounded minter limit, and
        // the shared recipients an unbounded limit, so the rest of the suite
        // exercises what it is about rather than the caps. Tests that mint to
        // a recipient of their own allow it with `_allowRecipient`.
        vm.startPrank(OWNER);
        orchestrator.setMinterMintLimit(MINTER_A, UNBOUNDED_CAPACITY, NO_LEAK);
        orchestrator.setMinterMintLimit(MINTER_B, UNBOUNDED_CAPACITY, NO_LEAK);
        // The test contract mints directly in the signature and callback tests.
        orchestrator.setMinterMintLimit(address(this), UNBOUNDED_CAPACITY, NO_LEAK);
        orchestrator.setRecipientMintLimit(BOB, UNBOUNDED_CAPACITY, NO_LEAK);
        orchestrator.setRecipientMintLimit(address(capRecipient), UNBOUNDED_CAPACITY, NO_LEAK);
        orchestrator.setRecipientMintLimit(address(capRecipient2), UNBOUNDED_CAPACITY, NO_LEAK);
        vm.stopPrank();
    }

    /// `n` as a `Float` at exponent zero: the same packing the identity
    /// weighting charges `amount` with on a zero-decimals token, so a limit
    /// written through this is in the units a mint here is metered in.
    function _f(uint256 n) internal pure returns (Float) {
        return LibDecimalFloat.fromFixedDecimalLosslessPacked(n, 0);
    }

    /// `coefficient * 10 ** exponent`, for the values `_f` cannot spell: a
    /// negative, or a magnitude past `uint256`.
    function _f(int256 coefficient, int256 exponent) internal pure returns (Float) {
        return LibDecimalFloat.packLossless(coefficient, exponent);
    }

    /// Numeric `Float` equality: one value has many spellings, so an
    /// arithmetic result is compared as a number, never as bytes.
    function _assertFloatEq(Float actual, Float expected, string memory err) internal pure {
        assertTrue(actual.eq(expected), string.concat(err, ": got ", _str(actual), ", want ", _str(expected)));
    }

    function _str(Float float) internal pure returns (string memory) {
        (int256 coefficient, int256 exponent) = float.unpack();
        return string.concat(vm.toString(coefficient), "e", vm.toString(exponent));
    }

    // ------------------------------------------------------------------ //
    //                            Test helpers                            //
    // ------------------------------------------------------------------ //

    /// Deploy a fresh beacon + proxy pair pointing at `impl`, initialised
    /// with `owner`. The guard mocks must already pass.
    /// `initialize` resolves its owner from the address registry, so `owner`
    /// is bound there rather than passed in. The binding is rewritten per
    /// call so a test can deploy proxies under different owners.
    function _deployProxy(address owner) internal returns (ST0xOrchestrator) {
        LibTestAddressRegistry.etchAndBind(vm, ST0X_TOKEN_OWNER_SAFE_NAME, owner);
        LibTestMigrationRegistry.etch(vm);
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), address(this));
        bytes memory initData = abi.encodeCall(ST0xOrchestrator.initialize, ());
        BeaconProxy proxy = new BeaconProxy(address(beacon), initData);
        return ST0xOrchestrator(payable(address(proxy)));
    }

    /// Install the identity weighting on `o` as OWNER: `_: mint-amount();`,
    /// evaluated by the test interpreter. The bytecode is parsed before the
    /// prank, since `parse2` is an external call the prank would land on.
    function _setIdentityWeighting(ST0xOrchestrator o) internal {
        bytes memory bytecode = I_DEPLOYER.parse2(bytes(string.concat(usingWords(), "_: mint-amount();")));
        EvaluableV4 memory identity = EvaluableV4({interpreter: I_INTERPRETER, store: I_STORE, bytecode: bytecode});
        vm.prank(OWNER);
        o.setMintWeighting(identity);
    }

    /// Make the vault-logic version guard pass: the deployer resolves each
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
    /// `symbol()` its symbol, and `decimals()` zero. With zero decimals the
    /// identity weighting's `mint-amount()` is `amount` packed at exponent
    /// zero, byte for byte what `_f(amount)` spells, so a cap test can compare
    /// the reverts as bytes. Nothing on the token's corporate-action surface
    /// is mocked.
    function _mockVaultTopology(address token, address receipt_, string memory symbol_) internal {
        vm.mockCall(token, abi.encodeWithSelector(ReceiptVault.receipt.selector), abi.encode(receipt_));
        vm.mockCall(token, abi.encodeWithSelector(IERC20Metadata.symbol.selector), abi.encode(symbol_));
        vm.mockCall(token, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(uint8(0)));
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

    /// Give `to` an unbounded recipient limit on the shared orchestrator, so a
    /// test about something other than the caps can mint to it.
    function _allowRecipient(address to) internal {
        vm.prank(OWNER);
        orchestrator.setRecipientMintLimit(to, UNBOUNDED_CAPACITY, NO_LEAK);
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

    /// The ERC-5267 self-description advertises the signer domain: name
    /// "ST0xOrchestrator", version "1", the current chain, and the proxy
    /// address, with no salt or extensions.
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

    /// `mintAuthDigest` equals an independent EIP-712 computation: domain
    /// separator from the literal ("ST0xOrchestrator", "1", chainid, proxy)
    /// and struct hash from the literal MintAuth type string, so any drift in
    /// domain name/version, typehash, or field order breaks this test.
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
        raw.initialize();
    }

    function testInitializeGrantsAdmin() external view {
        assertTrue(orchestrator.hasRole(orchestrator.DEFAULT_ADMIN_ROLE(), OWNER), "owner missing admin role");
    }

    /// The zero-owner check is gone because a zero owner is no longer
    /// reachable: the registry refuses to bind the zero address and its read
    /// reverts on an unbound name, so the two ways to arrive at one are both
    /// refused before `initialize` has an owner at all. Both are pinned here
    /// rather than left as an argument about the dependency's behaviour.
    function testInitializeUnboundNameReverts() external {
        LibTestAddressRegistry.unbind(vm, ST0X_TOKEN_OWNER_SAFE_NAME);
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), address(this));
        bytes memory initData = abi.encodeCall(ST0xOrchestrator.initialize, ());
        vm.expectRevert(
            abi.encodeWithSelector(IAddressRegistryV1.NameNotRegistered.selector, ST0X_TOKEN_OWNER_SAFE_NAME)
        );
        new BeaconProxy(address(beacon), initData);
    }

    /// Root cannot bind the zero address in the first place.
    function testRegistryRefusesAZeroOwner() external {
        LibTestAddressRegistry.etch(vm);
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.ZeroAccount.selector, ST0X_TOKEN_OWNER_SAFE_NAME));
        LibTestAddressRegistry.bind(vm, ST0X_TOKEN_OWNER_SAFE_NAME, address(0));
    }

    /// A chain with no registry at the pinned address fails loudly on the
    /// code hash rather than calling into whatever is there.
    function testInitializeWithoutARegistryReverts() external {
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), address(this));
        bytes memory initData = abi.encodeCall(ST0xOrchestrator.initialize, ());
        vm.etch(LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS, hex"");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibAddressRegistry.UnexpectedAddressRegistryCodeHash.selector,
                LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        new BeaconProxy(address(beacon), initData);
    }

    /// `initialize` runs the vault-logic guard, so a fresh proxy cannot be
    /// deployed against unexpected vault logic — the `BeaconProxy`
    /// constructor bubbles `VaultLogicMismatch` from the init delegatecall.
    function testInitializeVaultGuardFailReverts() external {
        _makeGuardFailVault();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), address(this));
        bytes memory initData = abi.encodeCall(ST0xOrchestrator.initialize, ());
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
        bytes memory initData = abi.encodeCall(ST0xOrchestrator.initialize, ());
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.ReceiptLogicMismatch.selector, EXPECTED_RECEIPT_IMPL, address(0xDEAD)
            )
        );
        new BeaconProxy(address(beacon), initData);
    }

    function testDoubleInitializeReverts() external {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        orchestrator.initialize();
    }

    function testFuzzInitializeGrantsAdmin(address owner) external {
        vm.assume(owner != address(0));
        ST0xOrchestrator o = _deployProxy(owner);
        assertTrue(o.hasRole(o.DEFAULT_ADMIN_ROLE(), owner));
    }

    // ------------------------------------------------------------------ //
    //                           migrate                             //
    // ------------------------------------------------------------------ //

    /// A proxy as a live one stands: initialised against the implementation
    /// that had no `MINT_ADMIN_ROLE`, then rolled onto this one by a beacon
    /// upgrade. The beacon is owned by the test contract, so the upgrade
    /// needs no prank.
    function _deployUpgradedPreMintAdminProxy(address owner) internal returns (ST0xOrchestrator) {
        PreMintAdminOrchestrator legacy = new PreMintAdminOrchestrator();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(legacy), address(this));
        bytes memory initData = abi.encodeCall(PreMintAdminOrchestrator.initialize, (owner));
        BeaconProxy proxy = new BeaconProxy(address(beacon), initData);
        beacon.upgradeTo(address(impl));
        return ST0xOrchestrator(payable(address(proxy)));
    }

    /// The upgrade alone leaves the role split uninstalled, and
    /// `migrate` installs both halves of it. The pre-call assertions are
    /// what separate "the call worked" from "the state was already right".
    function testMigrateInstallsMintAdminAndDelegation() external {
        ST0xOrchestrator o = _deployUpgradedPreMintAdminProxy(OWNER);

        assertFalse(o.hasRole(o.MINT_ADMIN_ROLE(), OWNER), "mint admin granted before the call");
        assertEq(o.getRoleAdmin(o.MINT_ROLE()), o.DEFAULT_ADMIN_ROLE(), "mint role already delegated");

        vm.prank(OWNER);
        o.migrate(OWNER);

        assertTrue(o.hasRole(o.MINT_ADMIN_ROLE(), OWNER), "mint admin not granted");
        assertEq(o.getRoleAdmin(o.MINT_ROLE()), o.MINT_ADMIN_ROLE(), "mint role not delegated");
    }

    /// The burn half of the same reconcile. Separate from the mint half so a
    /// call that installed only one is not reported as a pass.
    function testMigrateInstallsBurnAdminAndDelegation() external {
        ST0xOrchestrator o = _deployUpgradedPreMintAdminProxy(OWNER);

        assertFalse(o.hasRole(o.BURN_ADMIN_ROLE(), OWNER), "burn admin granted before the call");
        assertEq(o.getRoleAdmin(o.BURN_ROLE()), o.DEFAULT_ADMIN_ROLE(), "burn role already delegated");

        vm.prank(OWNER);
        o.migrate(OWNER);

        assertTrue(o.hasRole(o.BURN_ADMIN_ROLE(), OWNER), "burn admin not granted");
        assertEq(o.getRoleAdmin(o.BURN_ROLE()), o.BURN_ADMIN_ROLE(), "burn role not delegated");
    }

    /// The burn delegation by its effect: `BURN_ADMIN_ROLE` can add a burner
    /// afterwards, where before only `DEFAULT_ADMIN_ROLE` could.
    function testMigrateMovesBurnGrantingToBurnAdmin() external {
        ST0xOrchestrator o = _deployUpgradedPreMintAdminProxy(OWNER);
        bytes32 burnAdminRole = o.BURN_ADMIN_ROLE();
        bytes32 burnRole = o.BURN_ROLE();

        vm.startPrank(OWNER);
        o.migrate(OWNER);
        o.grantRole(burnAdminRole, BOB);
        o.revokeRole(burnAdminRole, OWNER);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, OWNER, burnAdminRole)
        );
        vm.prank(OWNER);
        o.grantRole(burnRole, MINTER_A);

        vm.prank(BOB);
        o.grantRole(burnRole, MINTER_A);
        assertTrue(o.hasRole(burnRole, MINTER_A), "burn admin could not add a burner");
    }

    /// The emergency half of the same reconcile.
    function testMigrateInstallsEmergencyAdminAndDelegation() external {
        ST0xOrchestrator o = _deployUpgradedPreMintAdminProxy(OWNER);

        assertFalse(o.hasRole(o.EMERGENCY_ADMIN_ROLE(), OWNER), "emergency admin granted before the call");
        assertEq(o.getRoleAdmin(o.EMERGENCY_ROLE()), o.DEFAULT_ADMIN_ROLE(), "emergency already delegated");

        vm.prank(OWNER);
        o.migrate(OWNER);

        assertTrue(o.hasRole(o.EMERGENCY_ADMIN_ROLE(), OWNER), "emergency admin not granted");
        assertEq(o.getRoleAdmin(o.EMERGENCY_ROLE()), o.EMERGENCY_ADMIN_ROLE(), "emergency not delegated");
    }

    /// The emergency delegation by its effect: `EMERGENCY_ADMIN_ROLE` can
    /// hand out the recovery key afterwards, where before only
    /// `DEFAULT_ADMIN_ROLE` could — and holding the admin role is still not
    /// holding the key.
    function testMigrateMovesEmergencyGrantingToEmergencyAdmin() external {
        ST0xOrchestrator o = _deployUpgradedPreMintAdminProxy(OWNER);
        bytes32 emergencyAdminRole = o.EMERGENCY_ADMIN_ROLE();
        bytes32 emergencyRole = o.EMERGENCY_ROLE();

        vm.startPrank(OWNER);
        o.migrate(OWNER);
        o.grantRole(emergencyAdminRole, BOB);
        o.revokeRole(emergencyAdminRole, OWNER);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, OWNER, emergencyAdminRole)
        );
        vm.prank(OWNER);
        o.grantRole(emergencyRole, MINTER_A);

        assertFalse(o.hasRole(emergencyRole, BOB), "emergency admin holds the key itself");
        vm.prank(BOB);
        o.grantRole(emergencyRole, MINTER_A);
        assertTrue(o.hasRole(emergencyRole, MINTER_A), "emergency admin could not hand out the key");
    }

    /// What the grant is for: the mint caps are unsettable on an upgraded
    /// proxy until `migrate` runs, and settable after. Reads the limit
    /// back rather than trusting the call not to revert.
    function testMigrateMakesMintLimitsSettable() external {
        ST0xOrchestrator o = _deployUpgradedPreMintAdminProxy(OWNER);
        // Read ahead of the prank: a role getter is an external call, so
        // reading it inside the `expectRevert` argument would spend the prank.
        bytes32 mintAdminRole = o.MINT_ADMIN_ROLE();

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, OWNER, mintAdminRole)
        );
        vm.prank(OWNER);
        o.setMinterMintLimit(MINTER_A, UNBOUNDED_CAPACITY, NO_LEAK);

        vm.prank(OWNER);
        o.migrate(OWNER);

        vm.prank(OWNER);
        o.setMinterMintLimit(MINTER_A, UNBOUNDED_CAPACITY, NO_LEAK);
        assertTrue(o.minterMintLimit(MINTER_A).set, "limit not written");
    }

    /// The delegation is the half that governance cannot reach without this
    /// call, so it is pinned by its effect too: `MINT_ADMIN_ROLE` can add a
    /// minter afterwards, where before only `DEFAULT_ADMIN_ROLE` could.
    function testMigrateMovesMinterGrantingToMintAdmin() external {
        ST0xOrchestrator o = _deployUpgradedPreMintAdminProxy(OWNER);
        bytes32 mintAdminRole = o.MINT_ADMIN_ROLE();
        bytes32 mintRole = o.MINT_ROLE();

        vm.startPrank(OWNER);
        o.migrate(OWNER);
        o.grantRole(mintAdminRole, BOB);
        o.revokeRole(mintAdminRole, OWNER);
        vm.stopPrank();

        // OWNER keeps DEFAULT_ADMIN_ROLE and has lost the authority to add a
        // minter; BOB holds only MINT_ADMIN_ROLE and has it.
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, OWNER, mintAdminRole)
        );
        vm.prank(OWNER);
        o.grantRole(mintRole, MINTER_A);

        vm.prank(BOB);
        o.grantRole(mintRole, MINTER_A);
        assertTrue(o.hasRole(mintRole, MINTER_A), "mint admin could not add a minter");
    }

    /// The admin is the argument, not the caller. OWNER holds
    /// `DEFAULT_ADMIN_ROLE` and so may make the call, but the roles land on
    /// BOB — which is what distinguishes a parameter from `msg.sender`.
    function testMigrateInstallsTheArgumentNotTheCaller() external {
        ST0xOrchestrator o = _deployUpgradedPreMintAdminProxy(OWNER);

        vm.prank(OWNER);
        o.migrate(BOB);

        assertTrue(o.hasRole(o.MINT_ADMIN_ROLE(), BOB), "argument did not take mint admin");
        assertTrue(o.hasRole(o.BURN_ADMIN_ROLE(), BOB), "argument did not take burn admin");
        assertTrue(o.hasRole(o.EMERGENCY_ADMIN_ROLE(), BOB), "argument did not take emergency admin");
        assertFalse(o.hasRole(o.MINT_ADMIN_ROLE(), OWNER), "caller took mint admin");
        assertFalse(o.hasRole(o.BURN_ADMIN_ROLE(), OWNER), "caller took burn admin");
        assertFalse(o.hasRole(o.EMERGENCY_ADMIN_ROLE(), OWNER), "caller took emergency admin");
    }

    /// A zero admin would burn the proxy's one shot while granting the admin
    /// roles to nobody, leaving the operating roles delegated to a role no
    /// account holds — unrecoverable without another upgrade. Refused.
    function testMigrateZeroAdminReverts() external {
        ST0xOrchestrator o = _deployUpgradedPreMintAdminProxy(OWNER);

        vm.expectRevert(IST0xOrchestratorV1.ZeroOwner.selector);
        vm.prank(OWNER);
        o.migrate(address(0));

        // The refused call left the shot intact.
        vm.prank(OWNER);
        o.migrate(OWNER);
        assertTrue(o.hasRole(o.MINT_ADMIN_ROLE(), OWNER), "the refused call consumed the shot");
    }

    /// A second run is refused by the registry, on the head rather than on a
    /// local guard: the line has moved to the migration id, so a call still
    /// naming genesis is told where the line actually is. The registry checks
    /// the list before the record, which is why this is
    /// `UnexpectedMigrationHead` and not `MigrationAlreadyApplied`.
    function testMigrateTwiceReverts() external {
        ST0xOrchestrator o = _deployUpgradedPreMintAdminProxy(OWNER);
        vm.prank(OWNER);
        o.migrate(OWNER);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                address(o),
                ST0X_MIGRATION_NAMESPACE,
                ST0X_MIGRATION_NAMESPACE,
                MIGRATION_HEAD_GENESIS,
                ST0X_ORCHESTRATOR_MIGRATION_ADMIN_ROLES
            )
        );
        vm.prank(OWNER);
        o.migrate(OWNER);
    }

    /// The record is written under the proxy, not under the caller. That is
    /// what makes the line one only this proxy can write, and therefore worth
    /// reading.
    function testMigrateRecordsUnderTheProxy() external {
        ST0xOrchestrator o = _deployUpgradedPreMintAdminProxy(OWNER);
        IMigrationRegistryV2 registry =
            IMigrationRegistryV2(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);

        assertEq(
            registry.applied(address(o), ST0X_MIGRATION_NAMESPACE, ST0X_ORCHESTRATOR_MIGRATION_ADMIN_ROLES),
            0,
            "recorded before the call"
        );

        vm.prank(OWNER);
        o.migrate(OWNER);

        assertEq(
            registry.applied(address(o), ST0X_MIGRATION_NAMESPACE, ST0X_ORCHESTRATOR_MIGRATION_ADMIN_ROLES),
            block.timestamp,
            "not recorded under the proxy"
        );
        assertEq(
            registry.applied(OWNER, ST0X_MIGRATION_NAMESPACE, ST0X_ORCHESTRATOR_MIGRATION_ADMIN_ROLES),
            0,
            "recorded under the caller"
        );
        assertEq(
            registry.head(address(o), ST0X_MIGRATION_NAMESPACE),
            ST0X_ORCHESTRATOR_MIGRATION_ADMIN_ROLES,
            "head did not move"
        );
    }

    /// A chain without the registry cannot migrate, and fails on the code
    /// hash rather than calling into whatever occupies the address.
    function testMigrateWithoutARegistryReverts() external {
        ST0xOrchestrator o = _deployUpgradedPreMintAdminProxy(OWNER);
        LibTestMigrationRegistry.unEtch(vm);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        vm.prank(OWNER);
        o.migrate(OWNER);
    }

    /// Only `DEFAULT_ADMIN_ROLE` migrates, and a refused call records
    /// nothing, so the work is still pending afterwards.
    function testMigrateNonAdminRevertsWithoutRecording() external {
        ST0xOrchestrator o = _deployUpgradedPreMintAdminProxy(OWNER);
        bytes32 adminRole = o.DEFAULT_ADMIN_ROLE();
        bytes32 mintAdminRole = o.MINT_ADMIN_ROLE();

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, BOB, adminRole)
        );
        vm.prank(BOB);
        o.migrate(OWNER);

        vm.prank(OWNER);
        o.migrate(OWNER);
        assertTrue(o.hasRole(mintAdminRole, OWNER), "the refused call recorded the migration");
    }

    /// Catching up is one call however far behind the proxy is, and it runs
    /// every missing step rather than only the newest. Here the proxy is at
    /// zero and both steps have to land.
    function testMigrateRunsEveryMissingStep() external {
        ST0xOrchestrator o = _deployUpgradedPreMintAdminProxy(OWNER);

        vm.prank(OWNER);
        o.migrate(OWNER);

        // Step 1's state.
        assertTrue(o.hasRole(o.DEFAULT_ADMIN_ROLE(), OWNER), "step 1 did not run");
        // Step 2's state, on all three legs.
        assertEq(o.getRoleAdmin(o.MINT_ROLE()), o.MINT_ADMIN_ROLE(), "step 2 mint leg did not run");
        assertEq(o.getRoleAdmin(o.BURN_ROLE()), o.BURN_ADMIN_ROLE(), "step 2 burn leg did not run");
        assertEq(o.getRoleAdmin(o.EMERGENCY_ROLE()), o.EMERGENCY_ADMIN_ROLE(), "step 2 emergency leg did not run");
    }

    /// A proxy that `initialize` built has already had the step installed and
    /// recorded, so its line is at the migration and a `migrate` naming
    /// genesis is refused. `initialize` recording is what makes a later step
    /// able to name this one as its predecessor on every proxy, new or
    /// migrated.
    function testMigrateOnFreshProxyReverts() external {
        ST0xOrchestrator o = _deployProxy(OWNER);
        IMigrationRegistryV2 registry =
            IMigrationRegistryV2(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);

        assertEq(
            registry.head(address(o), ST0X_MIGRATION_NAMESPACE),
            ST0X_ORCHESTRATOR_MIGRATION_ADMIN_ROLES,
            "initialize did not record the step"
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                address(o),
                ST0X_MIGRATION_NAMESPACE,
                ST0X_MIGRATION_NAMESPACE,
                MIGRATION_HEAD_GENESIS,
                ST0X_ORCHESTRATOR_MIGRATION_ADMIN_ROLES
            )
        );
        vm.prank(OWNER);
        o.migrate(OWNER);
    }

    /// Unreachable on the raw implementation. The role check is the first
    /// modifier, so the implementation — where nobody holds any role —
    /// refuses on authorisation rather than on the version.
    function testMigrateOnImplementationReverts() external {
        ST0xOrchestrator raw = new ST0xOrchestrator();
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), bytes32(0))
        );
        raw.migrate(OWNER);
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
        assertEq(orchestrator.MINT_ADMIN_ROLE(), keccak256("MINT_ADMIN"));
        assertEq(orchestrator.BURN_ADMIN_ROLE(), keccak256("BURN_ADMIN"));
        assertTrue(orchestrator.MINT_ADMIN_ROLE() != orchestrator.BURN_ADMIN_ROLE());
        assertTrue(orchestrator.MINT_ADMIN_ROLE() != orchestrator.MINT_ROLE());
        assertTrue(orchestrator.BURN_ADMIN_ROLE() != orchestrator.BURN_ROLE());
        assertTrue(orchestrator.BURN_ADMIN_ROLE() != orchestrator.EMERGENCY_ROLE());
        assertEq(orchestrator.EMERGENCY_ADMIN_ROLE(), keccak256("EMERGENCY_ADMIN"));
        assertTrue(orchestrator.EMERGENCY_ADMIN_ROLE() != orchestrator.EMERGENCY_ROLE());
        assertTrue(orchestrator.EMERGENCY_ADMIN_ROLE() != orchestrator.MINT_ADMIN_ROLE());
        assertTrue(orchestrator.EMERGENCY_ADMIN_ROLE() != orchestrator.BURN_ADMIN_ROLE());
    }

    /// Every operating role answers to its own admin role, and every admin
    /// role answers to ITSELF, which is what
    /// `OffchainAssetReceiptVaultAuthorizerV1` in `rain-vats` and this repo's
    /// own corporate-actions authorizer both do for every permission they
    /// carry.
    ///
    /// Self-administering is the difference between an authority and a
    /// delegation. Under OpenZeppelin's default an admin role's admin is
    /// `DEFAULT_ADMIN_ROLE`, so a mint admin could appoint minters but could
    /// not appoint a second mint admin, rotate itself out, or revoke a
    /// compromised peer — every one of those would go back through the root,
    /// which makes the root an operational key rather than a rare one.
    function testEveryAdminRoleAdministersItself() external view {
        assertEq(
            orchestrator.getRoleAdmin(orchestrator.MINT_ADMIN_ROLE()),
            orchestrator.MINT_ADMIN_ROLE(),
            "mint admin not self-administering"
        );
        assertEq(
            orchestrator.getRoleAdmin(orchestrator.BURN_ADMIN_ROLE()),
            orchestrator.BURN_ADMIN_ROLE(),
            "burn admin not self-administering"
        );
        assertEq(
            orchestrator.getRoleAdmin(orchestrator.EMERGENCY_ADMIN_ROLE()),
            orchestrator.EMERGENCY_ADMIN_ROLE(),
            "emergency admin not self-administering"
        );
    }

    /// Every operating role answers to its own admin role.
    function testRoleAdminsOnAFreshProxy() external view {
        assertEq(orchestrator.getRoleAdmin(orchestrator.MINT_ROLE()), orchestrator.MINT_ADMIN_ROLE());
        assertEq(orchestrator.getRoleAdmin(orchestrator.BURN_ROLE()), orchestrator.BURN_ADMIN_ROLE());
        assertEq(orchestrator.getRoleAdmin(orchestrator.EMERGENCY_ROLE()), orchestrator.EMERGENCY_ADMIN_ROLE());
    }

    /// Self-administration by its effect rather than by `getRoleAdmin`: a mint
    /// admin seats a second mint admin without the root being involved.
    ///
    /// This is the capability the default `DEFAULT_ADMIN_ROLE` admin denies,
    /// so it fails if the self-administering `_setRoleAdmin` is dropped.
    function testMintAdminCanSeatAnotherMintAdmin() external {
        bytes32 mintAdminRole = orchestrator.MINT_ADMIN_ROLE();
        address secondAdmin = address(0xA11CE);

        vm.prank(OWNER);
        orchestrator.grantRole(mintAdminRole, secondAdmin);
        assertTrue(orchestrator.hasRole(mintAdminRole, secondAdmin), "second mint admin not seated");

        // And the seat is a real one: the new admin can seat minters.
        bytes32 mintRole = orchestrator.MINT_ROLE();
        address minter = address(0xB0B);
        vm.prank(secondAdmin);
        orchestrator.grantRole(mintRole, minter);
        assertTrue(orchestrator.hasRole(mintRole, minter), "minter not seated by the second admin");
    }

    /// A mint admin can revoke a peer, which is what makes a compromised
    /// co-admin recoverable without the root.
    function testMintAdminCanRevokeAPeer() external {
        bytes32 mintAdminRole = orchestrator.MINT_ADMIN_ROLE();
        address peer = address(0xA11CE);

        vm.prank(OWNER);
        orchestrator.grantRole(mintAdminRole, peer);

        vm.prank(peer);
        orchestrator.revokeRole(mintAdminRole, OWNER);
        assertFalse(orchestrator.hasRole(mintAdminRole, OWNER), "peer could not revoke the original admin");
    }

    /// `DEFAULT_ADMIN_ROLE` can no longer grant an admin role, because it is
    /// no longer that role's admin.
    ///
    /// This is the cost of self-administration and is asserted rather than
    /// left implicit: the root seats the first holder through the internal
    /// `_grantRole` in `initialize`, and after that the admin line manages
    /// itself. A root that could still grant would mean the admin role was
    /// never self-administering.
    function testDefaultAdminCannotGrantAnAdminRole() external {
        bytes32 mintAdminRole = orchestrator.MINT_ADMIN_ROLE();
        bytes32 defaultAdminRole = orchestrator.DEFAULT_ADMIN_ROLE();
        address rootHolder = OWNER;
        assertTrue(orchestrator.hasRole(defaultAdminRole, rootHolder), "owner is not the root");

        // The root holds `MINT_ADMIN_ROLE` too, from `initialize`, so revoke
        // that first: otherwise this would pass through the self-administering
        // path and say nothing about `DEFAULT_ADMIN_ROLE`.
        vm.prank(rootHolder);
        orchestrator.renounceRole(mintAdminRole, rootHolder);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, rootHolder, mintAdminRole)
        );
        vm.prank(rootHolder);
        orchestrator.grantRole(mintAdminRole, address(0xA11CE));
    }

    /// `initialize` hands the owner all three admin roles.
    function testInitializeGrantsEveryAdminRole() external view {
        assertTrue(orchestrator.hasRole(orchestrator.MINT_ADMIN_ROLE(), OWNER), "owner missing mint admin");
        assertTrue(orchestrator.hasRole(orchestrator.BURN_ADMIN_ROLE(), OWNER), "owner missing burn admin");
        assertTrue(orchestrator.hasRole(orchestrator.EMERGENCY_ADMIN_ROLE(), OWNER), "owner missing emergency admin");
    }

    /// Holding an admin role is not holding the role it administers.
    function testInitializeGrantsNoOperatingRole() external view {
        assertFalse(orchestrator.hasRole(orchestrator.MINT_ROLE(), OWNER), "owner holds mint");
        assertFalse(orchestrator.hasRole(orchestrator.BURN_ROLE(), OWNER), "owner holds burn");
        assertFalse(orchestrator.hasRole(orchestrator.EMERGENCY_ROLE(), OWNER), "owner holds emergency");
    }

    function testFuzzMintUnauthorized(address caller) external {
        vm.assume(!orchestrator.hasRole(orchestrator.MINT_ROLE(), caller));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, orchestrator.MINT_ROLE()
            )
        );
        vm.prank(caller);
        orchestrator.mint(TOKEN, BOB, 1, _auth("", bytes32(0)), "", new SignedContextV1[](0));
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

    /// A MINT_ROLE holder cannot setBurnIndex or withdraw (EMERGENCY-gated).
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
        orchestrator.mint(TOKEN, BOB, 1, _auth("", bytes32(0)), "", new SignedContextV1[](0));

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
        _allowRecipient(eoa);
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
        orchestrator.mint(TOKEN, eoa, amount, _auth(sig, nonce), info, new SignedContextV1[](0));
    }

    /// (b) EIP-1271: `to` is a contract returning the 1271 magic value.
    function testMintWith1271() external {
        _grant(orchestrator.MINT_ROLE(), address(this));
        uint256 amount = 100;
        bytes32 nonce = keccak256("n2");
        bytes memory info = "";

        Mock1271 recipient = new Mock1271(true);
        _allowRecipient(address(recipient));
        _prepMintExact(TOKEN, amount, info);
        // Any non-empty signature triggers the 1271 path since `to` is a contract.
        bytes memory sig = hex"deadbeef";

        vm.expectEmit(true, true, true, true, address(orchestrator));
        emit IST0xOrchestratorV1.Minted(address(this), TOKEN, address(recipient), amount, nonce);
        orchestrator.mint(TOKEN, address(recipient), amount, _auth(sig, nonce), info, new SignedContextV1[](0));
    }

    function testMint1271RejectReverts() external {
        _grant(orchestrator.MINT_ROLE(), address(this));
        Mock1271 recipient = new Mock1271(false);
        _allowRecipient(address(recipient));
        _prepMint(TOKEN, "");
        vm.expectRevert(IST0xOrchestratorV1.BadRecipientSignature.selector);
        orchestrator.mint(
            TOKEN, address(recipient), 100, _auth(hex"deadbeef", keccak256("x")), "", new SignedContextV1[](0)
        );
    }

    /// (c) Callback: empty signature; `to` implements IMintRecipient.
    function testMintWithCallback() external {
        _grant(orchestrator.MINT_ROLE(), address(this));
        uint256 amount = 250;
        bytes32 nonce = keccak256("n3");
        bytes memory info = hex"abcd";

        MockMintRecipient recipient = new MockMintRecipient(true);
        _allowRecipient(address(recipient));
        _prepMintExact(TOKEN, amount, info);

        bytes32 digest = _digest(TOKEN, address(recipient), amount, nonce);
        vm.expectCall(address(recipient), abi.encodeWithSelector(IMintRecipient.authorizeMint.selector, digest));

        vm.expectEmit(true, true, true, true, address(orchestrator));
        emit IST0xOrchestratorV1.Minted(address(this), TOKEN, address(recipient), amount, nonce);
        orchestrator.mint(TOKEN, address(recipient), amount, _auth("", nonce), info, new SignedContextV1[](0));
    }

    function testMintCallbackWrongValueReverts() external {
        _grant(orchestrator.MINT_ROLE(), address(this));
        MockMintRecipient recipient = new MockMintRecipient(false);
        _allowRecipient(address(recipient));
        _prepMint(TOKEN, "");
        vm.expectRevert(
            abi.encodeWithSelector(IST0xOrchestratorV1.RecipientCallbackRejected.selector, address(recipient))
        );
        orchestrator.mint(TOKEN, address(recipient), 100, _auth("", keccak256("x")), "", new SignedContextV1[](0));
    }

    /// Signature present but recovers to a different address → BadRecipientSignature.
    function testMintBadSignatureReverts() external {
        (address eoa,) = makeAddrAndKey("recipient");
        (, uint256 wrongPk) = makeAddrAndKey("someone-else");
        _grant(orchestrator.MINT_ROLE(), address(this));
        _allowRecipient(eoa);
        uint256 amount = 500;
        bytes32 nonce = keccak256("n1");
        _prepMint(TOKEN, "");

        bytes memory sig = _sign(wrongPk, TOKEN, eoa, amount, nonce);

        vm.expectRevert(IST0xOrchestratorV1.BadRecipientSignature.selector);
        orchestrator.mint(TOKEN, eoa, amount, _auth(sig, nonce), "", new SignedContextV1[](0));
    }

    function testMintZeroAmountReverts() external {
        _grant(orchestrator.MINT_ROLE(), address(this));
        vm.expectRevert(IST0xOrchestratorV1.ZeroAmount.selector);
        orchestrator.mint(TOKEN, BOB, 0, _auth("", bytes32(0)), "", new SignedContextV1[](0));
    }

    /// The sender and the recipient can never be the same. The minter here is
    /// a callback recipient that authorises anything, with unbounded caps and
    /// the vault side mocked, so only the guard stands between it and a mint
    /// to itself: the same minter minting to a different recipient in the
    /// same conditions goes through.
    function testMintSenderIsRecipientReverts() external {
        address minter = address(capRecipient);
        uint256 amount = 100;
        _grantMintOn(orchestrator, minter);
        // The minter gets a recipient limit as well as its minter one, so
        // an unset recipient cap is not what rejects the self-mint: the
        // guard is.
        vm.startPrank(OWNER);
        orchestrator.setMinterMintLimit(minter, UNBOUNDED_CAPACITY, NO_LEAK);
        orchestrator.setRecipientMintLimit(minter, UNBOUNDED_CAPACITY, NO_LEAK);
        vm.stopPrank();
        _mockCapMint(orchestrator, TOKEN, amount);

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IST0xOrchestratorV1.SenderIsRecipient.selector, minter));
        orchestrator.mint(TOKEN, minter, amount, _auth("", keccak256("self")), "", new SignedContextV1[](0));
        assertFalse(orchestrator.nonceUsed(minter, keccak256("self")), "self-mint must not consume the nonce");

        // Control: the same minter, caps and mocks, to someone else, succeeds.
        MockMintRecipient other = new MockMintRecipient(true);
        vm.prank(OWNER);
        orchestrator.setRecipientMintLimit(address(other), UNBOUNDED_CAPACITY, NO_LEAK);
        vm.prank(minter);
        vm.expectEmit(true, true, true, true, address(orchestrator));
        emit IST0xOrchestratorV1.Minted(minter, TOKEN, address(other), amount, keccak256("other"));
        orchestrator.mint(TOKEN, address(other), amount, _auth("", keccak256("other")), "", new SignedContextV1[](0));
    }

    /// Nonce replay: identical (token,to,amount,nonce) twice reverts.
    function testMintReplayReverts() external {
        (address eoa, uint256 pk) = makeAddrAndKey("recipient");
        _grant(orchestrator.MINT_ROLE(), address(this));
        _allowRecipient(eoa);
        uint256 amount = 500;
        bytes32 nonce = keccak256("n1");
        _prepMintExact(TOKEN, amount, "");

        bytes memory sig = _sign(pk, TOKEN, eoa, amount, nonce);

        orchestrator.mint(TOKEN, eoa, amount, _auth(sig, nonce), "", new SignedContextV1[](0));
        assertTrue(orchestrator.nonceUsed(eoa, nonce));

        vm.expectRevert(abi.encodeWithSelector(IST0xOrchestratorV1.NonceReplayed.selector, eoa, nonce));
        orchestrator.mint(TOKEN, eoa, amount, _auth(sig, nonce), "", new SignedContextV1[](0));
    }

    /// Replay is namespaced by (to, nonce), not by digest: the same nonce
    /// with a different amount reverts even with a fresh valid signature.
    function testMintSameNonceDifferentAmountReverts() external {
        (address eoa, uint256 pk) = makeAddrAndKey("recipient");
        _grant(orchestrator.MINT_ROLE(), address(this));
        _allowRecipient(eoa);
        bytes32 nonce = keccak256("n1");
        _mockERC20(TOKEN);
        vm.mockCall(TOKEN, abi.encodeWithSelector(ReceiptVault.mint.selector), abi.encode(uint256(500)));

        // Mint amount 500 consumes (eoa, nonce).
        orchestrator.mint(
            TOKEN, eoa, 500, _auth(_sign(pk, TOKEN, eoa, 500, nonce), nonce), "", new SignedContextV1[](0)
        );

        // Same nonce, amount 600, correctly signed → still NonceReplayed.
        bytes memory sig = _sign(pk, TOKEN, eoa, 600, nonce);
        vm.expectRevert(abi.encodeWithSelector(IST0xOrchestratorV1.NonceReplayed.selector, eoa, nonce));
        orchestrator.mint(TOKEN, eoa, 600, _auth(sig, nonce), "", new SignedContextV1[](0));
    }

    /// Same for a different token: the nonce is single-use for the recipient
    /// regardless of which token it originally authorised.
    function testMintSameNonceDifferentTokenReverts() external {
        (address eoa, uint256 pk) = makeAddrAndKey("recipient");
        _grant(orchestrator.MINT_ROLE(), address(this));
        _allowRecipient(eoa);
        bytes32 nonce = keccak256("n1");
        _mockERC20(TOKEN);
        vm.mockCall(TOKEN, abi.encodeWithSelector(ReceiptVault.mint.selector), abi.encode(uint256(500)));

        orchestrator.mint(
            TOKEN, eoa, 500, _auth(_sign(pk, TOKEN, eoa, 500, nonce), nonce), "", new SignedContextV1[](0)
        );

        bytes memory sig = _sign(pk, TOKEN2, eoa, 500, nonce);
        vm.expectRevert(abi.encodeWithSelector(IST0xOrchestratorV1.NonceReplayed.selector, eoa, nonce));
        orchestrator.mint(TOKEN2, eoa, 500, _auth(sig, nonce), "", new SignedContextV1[](0));
    }

    /// The same nonce for a different recipient is fine — no third party can
    /// consume another recipient's nonce.
    function testMintSameNonceDifferentRecipientSucceeds() external {
        (address alice, uint256 alicePk) = makeAddrAndKey("alice");
        (address carol, uint256 carolPk) = makeAddrAndKey("carol");
        _grant(orchestrator.MINT_ROLE(), address(this));
        _allowRecipient(alice);
        _allowRecipient(carol);
        uint256 amount = 500;
        bytes32 nonce = keccak256("shared");
        _mockERC20(TOKEN);
        vm.mockCall(TOKEN, abi.encodeWithSelector(ReceiptVault.mint.selector), abi.encode(uint256(500)));

        orchestrator.mint(
            TOKEN,
            alice,
            amount,
            _auth(_sign(alicePk, TOKEN, alice, amount, nonce), nonce),
            "",
            new SignedContextV1[](0)
        );
        assertTrue(orchestrator.nonceUsed(alice, nonce));
        assertFalse(orchestrator.nonceUsed(carol, nonce), "alice's mint must not consume carol's nonce");

        orchestrator.mint(
            TOKEN,
            carol,
            amount,
            _auth(_sign(carolPk, TOKEN, carol, amount, nonce), nonce),
            "",
            new SignedContextV1[](0)
        );
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
        orchestrator.mint(TOKEN, BOB, 1, _auth("", bytes32(0)), "", new SignedContextV1[](0));
    }

    function testMintReceiptGuardFailReverts() external {
        _grant(orchestrator.MINT_ROLE(), address(this));
        _makeGuardFailReceipt();
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.ReceiptLogicMismatch.selector, EXPECTED_RECEIPT_IMPL, address(0xDEAD)
            )
        );
        orchestrator.mint(TOKEN, BOB, 1, _auth("", bytes32(0)), "", new SignedContextV1[](0));
    }

    /// Mint never touches the burn pointer — no seeding, no walk.
    function testMintLeavesBurnPointerUntouched() external {
        (address eoa, uint256 pk) = makeAddrAndKey("recipient");
        _grant(orchestrator.MINT_ROLE(), address(this));
        _allowRecipient(eoa);
        uint256 amount = 500;
        bytes32 nonce = keccak256("n1");
        _prepMintExact(TOKEN, amount, "");

        orchestrator.mint(
            TOKEN, eoa, amount, _auth(_sign(pk, TOKEN, eoa, amount, nonce), nonce), "", new SignedContextV1[](0)
        );
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
    /// ratio is 1:1 by construction) reverts the mint.
    function testMintVaultAmountMismatchReverts() external {
        _grant(orchestrator.MINT_ROLE(), address(this));
        uint256 amount = 100;
        (address eoa, uint256 pk) = makeAddrAndKey("vam-recipient");
        _allowRecipient(eoa);
        bytes memory sig = _sign(pk, TOKEN, eoa, amount, keccak256("vam-mint"));
        _mockERC20(TOKEN);
        vm.mockCall(
            TOKEN,
            abi.encodeWithSelector(ReceiptVault.mint.selector, amount, address(orchestrator), uint256(0), bytes("")),
            abi.encode(amount - 1)
        );
        vm.expectRevert(abi.encodeWithSelector(IST0xOrchestratorV1.VaultAmountMismatch.selector, amount, amount - 1));
        orchestrator.mint(TOKEN, eoa, amount, _auth(sig, keccak256("vam-mint")), "", new SignedContextV1[](0));
    }

    // ------------------------------------------------------------------ //
    //                EIP-712 digest reference vectors                    //
    // ------------------------------------------------------------------ //

    /// The canonical MintAuth EIP-712 type string, as documented on
    /// `MINT_AUTH_TYPEHASH`. The contract constant hashes it byte-for-byte.
    string internal constant MINT_AUTH_TYPE = "MintAuth(address token,address recipient,uint256 amount,bytes32 nonce)";

    /// Reconstruct the mint-auth digest independently of the contract: domain
    /// separator from the documented ("ST0xOrchestrator", "1") domain and
    /// struct hash from the canonical type string, as an offchain signer
    /// computes it.
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

    /// Pin the typehash constant to the documented type string.
    function testMintAuthTypehashPinned() external view {
        assertEq(
            orchestrator.MINT_AUTH_TYPEHASH(),
            keccak256(bytes(MINT_AUTH_TYPE)),
            "MINT_AUTH_TYPEHASH does not hash the canonical MintAuth type string"
        );
    }

    /// `mintAuthDigest` equals the independently reconstructed EIP-712 digest
    /// for distinct non-zero (token, recipient, amount, nonce), so the signed
    /// payload commits to every field.
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

    /// End-to-end: an EOA signing the independently reconstructed digest,
    /// never calling the contract's own view, is accepted by `mint`. Any drift
    /// between the contract digest and the documented construction turns this
    /// into BadRecipientSignature.
    function testMintWithSignatureOverReferenceDigest() external {
        (address eoa, uint256 pk) = makeAddrAndKey("reference-signer");
        _grant(orchestrator.MINT_ROLE(), address(this));
        _allowRecipient(eoa);
        uint256 amount = 777;
        bytes32 nonce = keccak256("reference-signed");
        bytes memory info = hex"5157";

        _prepMintExact(TOKEN, amount, info);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _referenceMintAuthDigest(TOKEN, eoa, amount, nonce));
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectEmit(true, true, true, true, address(orchestrator));
        emit IST0xOrchestratorV1.Minted(address(this), TOKEN, eoa, amount, nonce);
        orchestrator.mint(TOKEN, eoa, amount, _auth(sig, nonce), info, new SignedContextV1[](0));
    }

    // ------------------------------------------------------------------ //
    //                        Reentrancy guard                            //
    // ------------------------------------------------------------------ //

    /// A callback recipient that reenters `mint` from inside its
    /// `authorizeMint` callback (holding MINT_ROLE itself) is stopped by the
    /// reentrancy guard: the nested call reverts
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

        // Mock the vault legs for both mints, and cap neither the recipient
        // nor its own minting, so that, were the guard absent, nested and
        // outer mint would both complete instead of reverting for an
        // unrelated reason.
        _allowRecipient(address(recipient));
        vm.prank(OWNER);
        orchestrator.setMinterMintLimit(address(recipient), UNBOUNDED_CAPACITY, NO_LEAK);
        _prepMintExact(TOKEN, outerAmount, "");
        _prepMintExact(TOKEN, innerAmount, "");

        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        orchestrator.mint(TOKEN, address(recipient), outerAmount, _auth("", outerNonce), "", new SignedContextV1[](0));

        assertFalse(orchestrator.nonceUsed(address(recipient), outerNonce), "outer nonce must not persist");
        assertFalse(orchestrator.nonceUsed(address(recipient), innerNonce), "inner nonce must not persist");
    }

    /// The vault reporting an assets amount != the shares redeemed reverts
    /// the burn.
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

    /// Partial drain parks the pointer at the id (does not advance).
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
    /// with 20 still unburned → the whole burn reverts `InsufficientReceipts`
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

    /// A genuine receipt at an id at or above the pointer is a no-op.
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

    /// A sender whose claimed vault does not round-trip (`vault.receipt()` is
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

    /// The batch hook lowers the pointer to the minimum qualifying id.
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

    /// A zero-value transfer of a genuine receipt at a low id does not lower
    /// the pointer: it delivers no burnable balance, so lowering to its id
    /// would strand the pointer over an empty id.
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

    /// `burnInfo` is forwarded verbatim to `vault.redeem` as
    /// `receiptInformation`.
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
    /// entrypoint: a token whose `transferFrom` reenters `burn` sees the
    /// nested call revert `ReentrancyGuardReentrantCall`, while the outer
    /// burn completes normally.
    function testBurnReentrantCallReverts() external {
        ReentrantBurnVault attacker = new ReentrantBurnVault(orchestrator);
        _grant(orchestrator.BURN_ROLE(), address(this));
        // The nested call comes from the attacker, so it passes the role
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

    /// A sender whose `manager()` probe reverts with exactly 32 bytes of
    /// returndata (decoding to a vault whose `receipt()` round-trips back to
    /// the sender) is treated as foreign: accepted, no pointer move, no
    /// `BurnIndexLowered`. Only the `!ok` guard on the manager() staticcall
    /// separates this revert payload from a genuine manager() answer.
    function testOnERC1155ReceivedManagerRevert32BytesNoOp() external {
        address fakeVault = address(0xFA6E);
        MockManagerRevert1155 evil = new MockManagerRevert1155(fakeVault);
        // Make the round-trip leg pass so the only thing rejecting the
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

    /// A sender whose manager() probe succeeds (returns a vault), but whose
    /// vault's receipt() probe reverts with exactly 32 bytes decoding to the
    /// sender itself, is treated as foreign: accepted, no pointer move, no
    /// BurnIndexLowered. Only the `!ok` half of the guard on the receipt()
    /// staticcall separates that revert payload from a genuine round-tripping
    /// receipt() answer.
    function testOnERC1155ReceivedReceiptRevert32BytesNoOp() external {
        address evil = address(0xE711);
        address fakeVault = address(0xFA6E);
        // manager() probe succeeds and points at fakeVault.
        vm.mockCall(evil, abi.encodeWithSelector(IReceiptV3.manager.selector), abi.encode(fakeVault));
        // receipt() probe reverts with 32 bytes that decode back to the
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

    /// A sender whose `manager()` probe succeeds but names a code-less claimed
    /// vault is treated as foreign: the `vault.receipt()` staticcall to an
    /// address with no code succeeds with empty returndata, so the
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
    /// reverts on `receipt()` is treated as foreign: the `!ok` half of the
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

    /// Grant `minter` `MINT_ROLE` on `o`. The role is read before the prank so
    /// the view call doesn't consume it.
    function _grantMintOn(ST0xOrchestrator o, address minter) internal {
        bytes32 mintRole = o.MINT_ROLE();
        vm.prank(OWNER);
        o.grantRole(mintRole, minter);
    }

    /// Mock the vault side of a mint of exactly `amount` on `token` into `o`:
    /// `vault.mint` returns matching assets and the share transfer succeeds,
    /// leaving the cap path as the only thing these tests can fail on.
    function _mockCapMint(ST0xOrchestrator o, address token, uint256 amount) internal {
        vm.mockCall(token, abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
        vm.mockCall(
            token,
            abi.encodeWithSelector(ReceiptVault.mint.selector, amount, address(o), uint256(0), ""),
            abi.encode(amount)
        );
    }

    /// Mint `amount` of `token` from `minter` through `o` to `to`.
    function _capMintTo(ST0xOrchestrator o, address minter, address token, address to, uint256 amount, bytes32 nonce)
        internal
    {
        _mockCapMint(o, token, amount);
        vm.prank(minter);
        o.mint(token, to, amount, _auth("", nonce), "", new SignedContextV1[](0));
    }

    /// Mint `amount` of `token` from `minter` through `o` to `capRecipient`.
    function _capMint(ST0xOrchestrator o, address minter, address token, uint256 amount, bytes32 nonce) internal {
        _capMintTo(o, minter, token, address(capRecipient), amount, nonce);
    }

    /// A proxy with no limits configured: every limit is zero, so it mints
    /// nothing until a test sets the one limit it is about. It carries the
    /// identity weighting, since the cap-exceeded checks run after the
    /// weighting is evaluated.
    function _unconfiguredOrchestrator() internal returns (ST0xOrchestrator) {
        ST0xOrchestrator fresh = _deployProxy(OWNER);
        _setIdentityWeighting(fresh);
        return fresh;
    }

    /// Level 1 of "unset ⇒ 0 ⇒ rejected": with the minter's limit
    /// never set, no mint succeeds for that minter, however wide the
    /// recipient's limit is.
    function testMintMinterLimitUnsetReverts() external {
        ST0xOrchestrator fresh = _unconfiguredOrchestrator();
        _grantMintOn(fresh, MINTER_A);
        vm.prank(OWNER);
        fresh.setRecipientMintLimit(address(capRecipient), UNBOUNDED_CAPACITY, NO_LEAK);

        _assertFloatEq(fresh.minterMintLimit(MINTER_A).capacity, ZERO, "minter capacity must start at zero");
        assertFalse(fresh.minterMintLimit(MINTER_A).set, "minter limit must start unset");
        _assertFloatEq(
            fresh.mintHeadroom(MINTER_A, address(capRecipient)), ZERO, "unset minter limit must floor the headroom"
        );

        _mockCapMint(fresh, TOKEN, 1e18);
        vm.expectRevert(abi.encodeWithSelector(IST0xOrchestratorV1.MinterMintLimitUnset.selector, MINTER_A));
        vm.prank(MINTER_A);
        fresh.mint(
            TOKEN, address(capRecipient), 1e18, _auth("", keccak256("minter-unset")), "", new SignedContextV1[](0)
        );
    }

    /// Level 2 of "unset ⇒ 0 ⇒ rejected": a recipient with no limit cannot be
    /// minted to, even by a minter whose own limit is wide open.
    function testMintRecipientLimitUnsetReverts() external {
        ST0xOrchestrator fresh = _unconfiguredOrchestrator();
        _grantMintOn(fresh, MINTER_A);
        vm.prank(OWNER);
        fresh.setMinterMintLimit(MINTER_A, UNBOUNDED_CAPACITY, NO_LEAK);

        _assertFloatEq(
            fresh.recipientMintLimit(address(capRecipient)).capacity, ZERO, "recipient capacity must start at zero"
        );
        assertFalse(fresh.recipientMintLimit(address(capRecipient)).set, "recipient limit must start unset");
        _assertFloatEq(
            fresh.mintHeadroom(MINTER_A, address(capRecipient)), ZERO, "recipient zero must floor the headroom"
        );

        _mockCapMint(fresh, TOKEN, 1e18);
        vm.expectRevert(
            abi.encodeWithSelector(IST0xOrchestratorV1.RecipientMintLimitUnset.selector, address(capRecipient))
        );
        vm.prank(MINTER_A);
        fresh.mint(
            TOKEN, address(capRecipient), 1e18, _auth("", keccak256("recipient-unset")), "", new SignedContextV1[](0)
        );
    }

    /// Level 3 of "unset ⇒ 0 ⇒ rejected", and the explicit zero in one test:
    /// a recipient pinned to zero cannot be minted to by any minter, on any
    /// token, while every other recipient still serves those same minters. A
    /// zero limit is distinct from no limit, and reverts naming the figures
    /// that were approved.
    function testMintZeroRecipientLimitBlocksOneRecipientOnly() external {
        _grantMintOn(orchestrator, MINTER_A);
        _grantMintOn(orchestrator, MINTER_B);
        vm.prank(OWNER);
        orchestrator.setRecipientMintLimit(address(capRecipient), ZERO, NO_LEAK);

        MintLimitV1 memory pinned = orchestrator.recipientMintLimit(address(capRecipient));
        assertTrue(pinned.set, "a deliberate zero must read back as SET");
        _assertFloatEq(pinned.capacity, ZERO, "pinned capacity");
        Float headroom = orchestrator.mintHeadroom(MINTER_A, address(capRecipient));
        _assertFloatEq(headroom, ZERO, "pinned recipient has no headroom");

        _mockCapMint(orchestrator, TOKEN, 1e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.RecipientMintCapExceeded.selector, address(capRecipient), ZERO, headroom, _f(1e18)
            )
        );
        vm.prank(MINTER_A);
        orchestrator.mint(
            TOKEN, address(capRecipient), 1e18, _auth("", keccak256("pinned-a")), "", new SignedContextV1[](0)
        );

        _mockCapMint(orchestrator, TOKEN2, 1e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.RecipientMintCapExceeded.selector, address(capRecipient), ZERO, headroom, _f(1e18)
            )
        );
        vm.prank(MINTER_B);
        orchestrator.mint(
            TOKEN2, address(capRecipient), 1e18, _auth("", keccak256("pinned-b")), "", new SignedContextV1[](0)
        );

        // Both minters still mint to any other recipient.
        _capMintTo(orchestrator, MINTER_A, TOKEN, address(capRecipient2), 1e18, keccak256("other-recipient-a"));
        _capMintTo(orchestrator, MINTER_B, TOKEN2, address(capRecipient2), 1e18, keccak256("other-recipient-b"));
    }

    /// The boundary on the recipient's bucket: `mintHeadroom` names what
    /// fits, that amount succeeds, and one unit more reverts — before the
    /// mint and again after it, when the bucket is spent.
    function testMintBoundaryExactAmountFitsOneMoreReverts() external {
        uint256 capacity = 10e18;
        _grantMintOn(orchestrator, MINTER_A);
        vm.prank(OWNER);
        orchestrator.setRecipientMintLimit(address(capRecipient), _f(capacity), NO_LEAK);

        Float headroom = orchestrator.mintHeadroom(MINTER_A, address(capRecipient));
        _assertFloatEq(headroom, _f(capacity), "a fresh bucket offers one capacity");

        _mockCapMint(orchestrator, TOKEN, capacity + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.RecipientMintCapExceeded.selector,
                address(capRecipient),
                _f(capacity),
                headroom,
                _f(capacity + 1)
            )
        );
        vm.prank(MINTER_A);
        orchestrator.mint(
            TOKEN, address(capRecipient), capacity + 1, _auth("", keccak256("over")), "", new SignedContextV1[](0)
        );

        // Exactly the headroom fits.
        _capMint(orchestrator, MINTER_A, TOKEN, capacity, keccak256("exact"));

        // And the bucket is spent at that same second, with no leak rate to
        // refill it.
        headroom = orchestrator.mintHeadroom(MINTER_A, address(capRecipient));
        _assertFloatEq(headroom, ZERO, "a spent bucket offers nothing");
        _mockCapMint(orchestrator, TOKEN, 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.RecipientMintCapExceeded.selector,
                address(capRecipient),
                _f(capacity),
                headroom,
                _f(1)
            )
        );
        vm.prank(MINTER_A);
        orchestrator.mint(TOKEN, address(capRecipient), 1, _auth("", keccak256("spent")), "", new SignedContextV1[](0));
    }

    /// Per-minter isolation: one minter exhausting its minter bucket leaves
    /// another minter's bucket untouched, for the same recipient and token.
    function testMintPerMinterIsolation() external {
        uint256 capacity = 10e18;
        _grantMintOn(orchestrator, MINTER_A);
        _grantMintOn(orchestrator, MINTER_B);
        vm.startPrank(OWNER);
        orchestrator.setMinterMintLimit(MINTER_A, _f(capacity), NO_LEAK);
        orchestrator.setMinterMintLimit(MINTER_B, _f(capacity), NO_LEAK);
        vm.stopPrank();

        _capMint(orchestrator, MINTER_A, TOKEN, capacity, keccak256("a-drain"));
        _assertFloatEq(orchestrator.mintHeadroom(MINTER_A, address(capRecipient)), ZERO, "A's bucket is spent");
        _assertFloatEq(
            orchestrator.mintHeadroom(MINTER_B, address(capRecipient)), _f(capacity), "B's bucket is untouched"
        );

        _capMint(orchestrator, MINTER_B, TOKEN, capacity, keccak256("b-full"));
    }

    /// Per-recipient isolation: one recipient's bucket being exhausted leaves
    /// another recipient's bucket untouched, for the same minter and token.
    function testMintPerRecipientIsolation() external {
        uint256 capacity = 10e18;
        _grantMintOn(orchestrator, MINTER_A);
        vm.startPrank(OWNER);
        orchestrator.setRecipientMintLimit(address(capRecipient), _f(capacity), NO_LEAK);
        orchestrator.setRecipientMintLimit(address(capRecipient2), _f(capacity), NO_LEAK);
        vm.stopPrank();

        _capMint(orchestrator, MINTER_A, TOKEN, capacity, keccak256("recipient-drain"));
        _assertFloatEq(
            orchestrator.mintHeadroom(MINTER_A, address(capRecipient)), ZERO, "capRecipient's bucket is spent"
        );
        _assertFloatEq(
            orchestrator.mintHeadroom(MINTER_A, address(capRecipient2)),
            _f(capacity),
            "capRecipient2's bucket is untouched"
        );

        _capMintTo(orchestrator, MINTER_A, TOKEN, address(capRecipient2), capacity, keccak256("recipient2-full"));
    }

    /// Nothing is metered per token: a recipient's one bucket is a plain sum
    /// of amounts across tokens. `6e18` of one token and `4e18` of another
    /// spend a `10e18` recipient cap exactly, and the next unit of either is
    /// refused.
    function testRecipientBucketSumsAmountsAcrossTokens() external {
        _grantMintOn(orchestrator, MINTER_A);
        vm.prank(OWNER);
        orchestrator.setRecipientMintLimit(address(capRecipient), _f(10e18), NO_LEAK);

        _capMint(orchestrator, MINTER_A, TOKEN, 6e18, keccak256("recipient-token"));
        _capMint(orchestrator, MINTER_A, TOKEN2, 4e18, keccak256("recipient-token2"));
        Float headroom = orchestrator.mintHeadroom(MINTER_A, address(capRecipient));
        _assertFloatEq(headroom, ZERO, "the recipient bucket is spent");

        _mockCapMint(orchestrator, TOKEN, 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.RecipientMintCapExceeded.selector, address(capRecipient), _f(10e18), headroom, _f(1)
            )
        );
        vm.prank(MINTER_A);
        orchestrator.mint(
            TOKEN, address(capRecipient), 1, _auth("", keccak256("recipient-full-token")), "", new SignedContextV1[](0)
        );

        _mockCapMint(orchestrator, TOKEN2, 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.RecipientMintCapExceeded.selector, address(capRecipient), _f(10e18), headroom, _f(1)
            )
        );
        vm.prank(MINTER_A);
        orchestrator.mint(
            TOKEN2,
            address(capRecipient),
            1,
            _auth("", keccak256("recipient-full-token2")),
            "",
            new SignedContextV1[](0)
        );
    }

    /// The recipient's bucket is also shared across minters: two minters
    /// each minting to the same recipient spend that recipient's one cap
    /// between them, and once it is spent neither can add a unit — while
    /// each minter's own minter bucket, left unbounded, is not what bound.
    function testRecipientBucketSumsAmountsAcrossMinters() external {
        _grantMintOn(orchestrator, MINTER_A);
        _grantMintOn(orchestrator, MINTER_B);
        vm.prank(OWNER);
        orchestrator.setRecipientMintLimit(address(capRecipient), _f(10e18), NO_LEAK);

        _capMint(orchestrator, MINTER_A, TOKEN, 6e18, keccak256("recipient-minter-a"));
        _capMint(orchestrator, MINTER_B, TOKEN, 4e18, keccak256("recipient-minter-b"));
        Float headroomA = orchestrator.mintHeadroom(MINTER_A, address(capRecipient));
        Float headroomB = orchestrator.mintHeadroom(MINTER_B, address(capRecipient));
        _assertFloatEq(headroomA, ZERO, "spent for A");
        _assertFloatEq(headroomB, ZERO, "spent for B");

        _mockCapMint(orchestrator, TOKEN, 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.RecipientMintCapExceeded.selector,
                address(capRecipient),
                _f(10e18),
                headroomA,
                _f(1)
            )
        );
        vm.prank(MINTER_A);
        orchestrator.mint(
            TOKEN, address(capRecipient), 1, _auth("", keccak256("recipient-full-a")), "", new SignedContextV1[](0)
        );

        _mockCapMint(orchestrator, TOKEN, 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.RecipientMintCapExceeded.selector,
                address(capRecipient),
                _f(10e18),
                headroomB,
                _f(1)
            )
        );
        vm.prank(MINTER_B);
        orchestrator.mint(
            TOKEN, address(capRecipient), 1, _auth("", keccak256("recipient-full-b")), "", new SignedContextV1[](0)
        );
    }

    /// A minter's bucket binds independently of the recipient's: with
    /// the recipient's capacity left unbounded, the minter bucket alone
    /// rejects the mint, the revert names the minter's cap rather than the
    /// recipient's, and another minter's bucket is untouched.
    function testMintMinterBucketBindsIndependently() external {
        uint256 minterCapacity = 10e18;
        _grantMintOn(orchestrator, MINTER_A);
        _grantMintOn(orchestrator, MINTER_B);
        // setUp leaves capRecipient unbounded; only A's minter limit is narrowed.
        vm.prank(OWNER);
        orchestrator.setMinterMintLimit(MINTER_A, _f(minterCapacity), NO_LEAK);

        _capMint(orchestrator, MINTER_A, TOKEN, minterCapacity, keccak256("minter-drain"));

        _assertFloatEq(
            orchestrator.recipientMintLimit(address(capRecipient)).capacity,
            UNBOUNDED_CAPACITY,
            "the recipient's capacity is unbounded"
        );
        Float headroom = orchestrator.mintHeadroom(MINTER_A, address(capRecipient));
        _assertFloatEq(headroom, ZERO, "A's minter bucket floors A's headroom");
        // B's minter bucket is B's own: to a recipient A never minted to, B
        // still has the whole unbounded capacity. (To capRecipient it has
        // less, but that is capRecipient's bucket, which A did spend from.)
        _assertFloatEq(
            orchestrator.mintHeadroom(MINTER_B, address(capRecipient2)),
            UNBOUNDED_CAPACITY,
            "B's minter bucket is B's own"
        );
        _assertFloatEq(
            orchestrator.mintHeadroom(MINTER_B, address(capRecipient)),
            UNBOUNDED_CAPACITY.sub(_f(minterCapacity)),
            "what B lacks at capRecipient is the recipient's bucket, not B's"
        );

        _mockCapMint(orchestrator, TOKEN, 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.MinterMintCapExceeded.selector, MINTER_A, _f(minterCapacity), headroom, _f(1)
            )
        );
        vm.prank(MINTER_A);
        orchestrator.mint(
            TOKEN, address(capRecipient), 1, _auth("", keccak256("minter-bound")), "", new SignedContextV1[](0)
        );
    }

    /// The recipient's bucket drains over time at `leakRate`: after being
    /// spent, exactly `elapsed * leakRate` comes back, and one unit more does
    /// not.
    function testMintRecipientBucketDrainsOverTime() external {
        uint256 capacity = 10e18;
        uint256 leakRate = 1e18;
        _grantMintOn(orchestrator, MINTER_A);
        vm.prank(OWNER);
        orchestrator.setRecipientMintLimit(address(capRecipient), _f(capacity), _f(leakRate));

        _capMint(orchestrator, MINTER_A, TOKEN, capacity, keccak256("drain"));
        _assertFloatEq(orchestrator.mintHeadroom(MINTER_A, address(capRecipient)), ZERO, "spent at the filling second");

        vm.warp(block.timestamp + 4);
        uint256 leaked = 4 * leakRate;
        Float headroom = orchestrator.mintHeadroom(MINTER_A, address(capRecipient));
        _assertFloatEq(headroom, _f(leaked), "four seconds of leak");

        _mockCapMint(orchestrator, TOKEN, leaked + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.RecipientMintCapExceeded.selector,
                address(capRecipient),
                _f(capacity),
                headroom,
                _f(leaked + 1)
            )
        );
        vm.prank(MINTER_A);
        orchestrator.mint(
            TOKEN, address(capRecipient), leaked + 1, _auth("", keccak256("too-soon")), "", new SignedContextV1[](0)
        );

        _capMint(orchestrator, MINTER_A, TOKEN, leaked, keccak256("after-leak"));
    }

    /// The minter bucket drains on the same terms — it is a second bucket,
    /// not a shared reading of the first.
    function testMintMinterBucketDrainsOverTime() external {
        uint256 minterCapacity = 10e18;
        uint256 leakRate = 1e18;
        _grantMintOn(orchestrator, MINTER_A);
        vm.prank(OWNER);
        orchestrator.setMinterMintLimit(MINTER_A, _f(minterCapacity), _f(leakRate));

        _capMint(orchestrator, MINTER_A, TOKEN, minterCapacity, keccak256("minter-drain"));
        _assertFloatEq(
            orchestrator.mintHeadroom(MINTER_A, address(capRecipient)),
            ZERO,
            "minter bucket spent at the filling second"
        );

        vm.warp(block.timestamp + 3);
        uint256 leaked = 3 * leakRate;
        Float headroom = orchestrator.mintHeadroom(MINTER_A, address(capRecipient));
        _assertFloatEq(headroom, _f(leaked), "three seconds of global leak");

        _mockCapMint(orchestrator, TOKEN, leaked + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.MinterMintCapExceeded.selector,
                MINTER_A,
                _f(minterCapacity),
                headroom,
                _f(leaked + 1)
            )
        );
        vm.prank(MINTER_A);
        orchestrator.mint(
            TOKEN,
            address(capRecipient),
            leaked + 1,
            _auth("", keccak256("minter-too-soon")),
            "",
            new SignedContextV1[](0)
        );

        _capMint(orchestrator, MINTER_A, TOKEN, leaked, keccak256("minter-after-leak"));
    }

    /// A bucket is two words and a fill writes both. Filling at a clock far
    /// from the epoch and reading one second later credits one second of
    /// leak: a level stored without its checkpoint would be leaked forward
    /// from the epoch instead.
    function testMintStoresTheCheckpointWithTheLevel() external {
        uint256 capacity = 10e18;
        uint256 leakRate = 1e18;
        _grantMintOn(orchestrator, MINTER_A);
        vm.prank(OWNER);
        orchestrator.setRecipientMintLimit(address(capRecipient), _f(capacity), _f(leakRate));

        vm.warp(1_000_000);
        _capMint(orchestrator, MINTER_A, TOKEN, capacity, keccak256("late-fill"));
        _assertFloatEq(orchestrator.mintHeadroom(MINTER_A, address(capRecipient)), ZERO, "spent at the filling second");

        vm.warp(1_000_001);
        _assertFloatEq(
            orchestrator.mintHeadroom(MINTER_A, address(capRecipient)),
            _f(leakRate),
            "one second of leak, not a million"
        );
    }

    /// Idling banks no credit: however long a bucket sits untouched, the most
    /// a single mint can take is one `capacity`, never the leak that would
    /// have accrued over the idle time.
    function testMintIdlingNeverExceedsCapacity() external {
        uint256 capacity = 10e18;
        uint256 leakRate = 1e18;
        _grantMintOn(orchestrator, MINTER_A);
        vm.prank(OWNER);
        orchestrator.setRecipientMintLimit(address(capRecipient), _f(capacity), _f(leakRate));

        // A million seconds at one token per second is 1e6 tokens of leak,
        // five orders of magnitude above the capacity.
        vm.warp(block.timestamp + 1_000_000);
        Float headroom = orchestrator.mintHeadroom(MINTER_A, address(capRecipient));
        _assertFloatEq(headroom, _f(capacity), "idling cannot enlarge a burst");

        _mockCapMint(orchestrator, TOKEN, capacity + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.RecipientMintCapExceeded.selector,
                address(capRecipient),
                _f(capacity),
                headroom,
                _f(capacity + 1)
            )
        );
        vm.prank(MINTER_A);
        orchestrator.mint(
            TOKEN, address(capRecipient), capacity + 1, _auth("", keccak256("idle")), "", new SignedContextV1[](0)
        );
    }

    /// Rewriting a recipient's limit changes the policy, not the credit
    /// already consumed: the bucket stays where the earlier mints left it, so
    /// a raised capacity offers only the difference.
    function testSetRecipientMintLimitKeepsBucketLevel() external {
        _grantMintOn(orchestrator, MINTER_A);
        vm.prank(OWNER);
        orchestrator.setRecipientMintLimit(address(capRecipient), _f(6e18), NO_LEAK);

        _capMint(orchestrator, MINTER_A, TOKEN, 6e18, keccak256("under-first-limit"));
        _assertFloatEq(orchestrator.mintHeadroom(MINTER_A, address(capRecipient)), ZERO, "spent under the first limit");

        vm.prank(OWNER);
        orchestrator.setRecipientMintLimit(address(capRecipient), _f(10e18), NO_LEAK);

        // The level is still 6e18, so the 10e18 limit leaves 4e18, not 10e18.
        _assertFloatEq(
            orchestrator.mintHeadroom(MINTER_A, address(capRecipient)),
            _f(4e18),
            "the consumed level survives the rewrite"
        );
    }

    /// Lowering a recipient's capacity below the outstanding level binds
    /// immediately: the headroom reads zero and the next mint is refused,
    /// with no migration and no window to front-run the change.
    function testLoweringRecipientCapacityBelowLevelBindsImmediately() external {
        _grantMintOn(orchestrator, MINTER_A);
        vm.prank(OWNER);
        orchestrator.setRecipientMintLimit(address(capRecipient), _f(10e18), NO_LEAK);
        _capMint(orchestrator, MINTER_A, TOKEN, 8e18, keccak256("before-lowering"));

        vm.prank(OWNER);
        orchestrator.setRecipientMintLimit(address(capRecipient), _f(2e18), NO_LEAK);

        Float headroom = orchestrator.mintHeadroom(MINTER_A, address(capRecipient));
        _assertFloatEq(headroom, ZERO, "a level above the new capacity leaves no headroom");
        _mockCapMint(orchestrator, TOKEN, 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.RecipientMintCapExceeded.selector, address(capRecipient), _f(2e18), headroom, _f(1)
            )
        );
        vm.prank(MINTER_A);
        orchestrator.mint(
            TOKEN, address(capRecipient), 1, _auth("", keccak256("after-lowering")), "", new SignedContextV1[](0)
        );
    }

    /// The same for the minter's capacity.
    function testLoweringMinterCapacityBelowLevelBindsImmediately() external {
        _grantMintOn(orchestrator, MINTER_A);
        vm.prank(OWNER);
        orchestrator.setMinterMintLimit(MINTER_A, _f(10e18), NO_LEAK);
        _capMint(orchestrator, MINTER_A, TOKEN, 8e18, keccak256("before-lowering"));

        vm.prank(OWNER);
        orchestrator.setMinterMintLimit(MINTER_A, _f(2e18), NO_LEAK);

        Float headroom = orchestrator.mintHeadroom(MINTER_A, address(capRecipient));
        _assertFloatEq(headroom, ZERO, "a level above the new capacity leaves no headroom");
        _mockCapMint(orchestrator, TOKEN, 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.MinterMintCapExceeded.selector, MINTER_A, _f(2e18), headroom, _f(1)
            )
        );
        vm.prank(MINTER_A);
        orchestrator.mint(
            TOKEN, address(capRecipient), 1, _auth("", keccak256("after-lowering")), "", new SignedContextV1[](0)
        );
    }

    /// A `Float` capacity has no ceiling the bucket cannot enforce: `1e60`
    /// fills to the last unit and refuses the unit after it, in both buckets.
    function testMintCapacityBeyondTheOldWordIsEnforcedToTheUnit() external {
        uint256 capacity = 1e60;
        _grantMintOn(orchestrator, MINTER_A);
        vm.startPrank(OWNER);
        orchestrator.setMinterMintLimit(MINTER_A, _f(capacity), NO_LEAK);
        orchestrator.setRecipientMintLimit(address(capRecipient), _f(capacity), NO_LEAK);
        vm.stopPrank();

        _capMint(orchestrator, MINTER_A, TOKEN, capacity, keccak256("to-the-brim"));
        Float headroom = orchestrator.mintHeadroom(MINTER_A, address(capRecipient));
        _assertFloatEq(headroom, ZERO, "full to the unit");

        _mockCapMint(orchestrator, TOKEN, 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.MinterMintCapExceeded.selector, MINTER_A, _f(capacity), headroom, _f(1)
            )
        );
        vm.prank(MINTER_A);
        orchestrator.mint(
            TOKEN, address(capRecipient), 1, _auth("", keccak256("one-over")), "", new SignedContextV1[](0)
        );
    }

    function _negative(int224 coefficient, int32 exponent) internal pure returns (Float) {
        return _f(bound(int256(coefficient), type(int224).min, -1), exponent);
    }

    function _nonNegative(int224 coefficient, int32 exponent) internal pure returns (Float) {
        return _f(bound(int256(coefficient), 0, type(int224).max), exponent);
    }

    function testFuzzSetMinterMintLimitNegativeCapacity(int224 coefficient, int32 exponent, bytes32 leakRateWord)
        external
    {
        Float capacity = _negative(coefficient, exponent);
        MintLimitV1 memory before = orchestrator.minterMintLimit(MINTER_A);
        vm.expectRevert(abi.encodeWithSelector(IST0xOrchestratorV1.NegativeMintLimitCapacity.selector, capacity));
        vm.prank(OWNER);
        orchestrator.setMinterMintLimit(MINTER_A, capacity, Float.wrap(leakRateWord));
        assertEq(abi.encode(orchestrator.minterMintLimit(MINTER_A)), abi.encode(before), "minter limit unchanged");
    }

    function testFuzzSetMinterMintLimitNegativeLeakRate(
        int224 capacityCoefficient,
        int32 capacityExponent,
        int224 coefficient,
        int32 exponent
    ) external {
        Float leakRate = _negative(coefficient, exponent);
        MintLimitV1 memory before = orchestrator.minterMintLimit(MINTER_A);
        vm.expectRevert(abi.encodeWithSelector(IST0xOrchestratorV1.NegativeMintLimitLeakRate.selector, leakRate));
        vm.prank(OWNER);
        orchestrator.setMinterMintLimit(MINTER_A, _nonNegative(capacityCoefficient, capacityExponent), leakRate);
        assertEq(abi.encode(orchestrator.minterMintLimit(MINTER_A)), abi.encode(before), "minter limit unchanged");
    }

    function testFuzzSetRecipientMintLimitNegativeCapacity(int224 coefficient, int32 exponent, bytes32 leakRateWord)
        external
    {
        Float capacity = _negative(coefficient, exponent);
        MintLimitV1 memory before = orchestrator.recipientMintLimit(address(capRecipient));
        vm.expectRevert(abi.encodeWithSelector(IST0xOrchestratorV1.NegativeMintLimitCapacity.selector, capacity));
        vm.prank(OWNER);
        orchestrator.setRecipientMintLimit(address(capRecipient), capacity, Float.wrap(leakRateWord));
        assertEq(
            abi.encode(orchestrator.recipientMintLimit(address(capRecipient))),
            abi.encode(before),
            "recipient limit unchanged"
        );
    }

    function testFuzzSetRecipientMintLimitNegativeLeakRate(
        int224 capacityCoefficient,
        int32 capacityExponent,
        int224 coefficient,
        int32 exponent
    ) external {
        Float leakRate = _negative(coefficient, exponent);
        MintLimitV1 memory before = orchestrator.recipientMintLimit(address(capRecipient));
        vm.expectRevert(abi.encodeWithSelector(IST0xOrchestratorV1.NegativeMintLimitLeakRate.selector, leakRate));
        vm.prank(OWNER);
        orchestrator.setRecipientMintLimit(
            address(capRecipient), _nonNegative(capacityCoefficient, capacityExponent), leakRate
        );
        assertEq(
            abi.encode(orchestrator.recipientMintLimit(address(capRecipient))),
            abi.encode(before),
            "recipient limit unchanged"
        );
    }

    function testSetMintLimitsAcceptZero() external {
        vm.startPrank(OWNER);
        orchestrator.setMinterMintLimit(MINTER_A, ZERO, ZERO);
        orchestrator.setRecipientMintLimit(address(capRecipient), ZERO, ZERO);
        vm.stopPrank();
        assertTrue(orchestrator.minterMintLimit(MINTER_A).set, "minter limit set");
        assertTrue(orchestrator.recipientMintLimit(address(capRecipient)).set, "recipient limit set");
    }

    // ------------------------------------------------------------------ //
    //                        Mint-cap setters                            //
    // ------------------------------------------------------------------ //

    function testFuzzSetMinterMintLimitUnauthorized(address caller, bytes32 capacity, bytes32 leakRate) external {
        vm.assume(!orchestrator.hasRole(orchestrator.MINT_ADMIN_ROLE(), caller));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, orchestrator.MINT_ADMIN_ROLE()
            )
        );
        vm.prank(caller);
        orchestrator.setMinterMintLimit(MINTER_A, Float.wrap(capacity), Float.wrap(leakRate));
    }

    function testFuzzSetRecipientMintLimitUnauthorized(
        address caller,
        address recipient,
        bytes32 capacity,
        bytes32 leakRate
    ) external {
        vm.assume(!orchestrator.hasRole(orchestrator.MINT_ADMIN_ROLE(), caller));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, orchestrator.MINT_ADMIN_ROLE()
            )
        );
        vm.prank(caller);
        orchestrator.setRecipientMintLimit(recipient, Float.wrap(capacity), Float.wrap(leakRate));
    }

    /// `MINT_ROLE` is not `MINT_ADMIN_ROLE`: the key the caps exist to bound
    /// can raise neither its own cap nor a recipient's.
    function testMintRoleCannotSetItsOwnCap() external {
        _grantMintOn(orchestrator, MINTER_A);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, MINTER_A, orchestrator.MINT_ADMIN_ROLE()
            )
        );
        vm.prank(MINTER_A);
        orchestrator.setMinterMintLimit(MINTER_A, UNBOUNDED_CAPACITY, NO_LEAK);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, MINTER_A, orchestrator.MINT_ADMIN_ROLE()
            )
        );
        vm.prank(MINTER_A);
        orchestrator.setRecipientMintLimit(address(capRecipient), UNBOUNDED_CAPACITY, NO_LEAK);
    }

    function testFuzzSetMinterMintLimitEmitsAndReads(
        int224 capacityCoefficient,
        int32 capacityExponent,
        int224 leakRateCoefficient,
        int32 leakRateExponent
    ) external {
        Float capacity = _nonNegative(capacityCoefficient, capacityExponent);
        Float leakRate = _nonNegative(leakRateCoefficient, leakRateExponent);
        vm.expectEmit(true, true, true, true, address(orchestrator));
        emit IST0xOrchestratorV1.MinterMintLimitSet(MINTER_A, capacity, leakRate);
        vm.prank(OWNER);
        orchestrator.setMinterMintLimit(MINTER_A, capacity, leakRate);

        MintLimitV1 memory limit = orchestrator.minterMintLimit(MINTER_A);
        assertTrue(limit.set, "minter limit reads back as set");
        assertEq(Float.unwrap(limit.capacity), Float.unwrap(capacity), "minter capacity");
        assertEq(Float.unwrap(limit.leakRate), Float.unwrap(leakRate), "minter leak rate");
    }

    function testFuzzSetRecipientMintLimitEmitsAndReads(
        address recipient,
        int224 capacityCoefficient,
        int32 capacityExponent,
        int224 leakRateCoefficient,
        int32 leakRateExponent
    ) external {
        Float capacity = _nonNegative(capacityCoefficient, capacityExponent);
        Float leakRate = _nonNegative(leakRateCoefficient, leakRateExponent);
        vm.expectEmit(true, true, true, true, address(orchestrator));
        emit IST0xOrchestratorV1.RecipientMintLimitSet(recipient, capacity, leakRate);
        vm.prank(OWNER);
        orchestrator.setRecipientMintLimit(recipient, capacity, leakRate);

        MintLimitV1 memory limit = orchestrator.recipientMintLimit(recipient);
        assertTrue(limit.set, "recipient limit reads back as set");
        assertEq(Float.unwrap(limit.capacity), Float.unwrap(capacity), "recipient capacity");
        assertEq(Float.unwrap(limit.leakRate), Float.unwrap(leakRate), "recipient leak rate");
    }

    /// Every non-negative capacity is a policy the bucket enforces, whatever
    /// its magnitude and scale: a fresh bucket under it offers that capacity
    /// as headroom.
    function testFuzzAnyNonNegativeCapacityIsEnforceable(int224 coefficient, int32 exponent) external {
        coefficient = int224(bound(int256(coefficient), 0, type(int224).max));
        exponent = int32(bound(int256(exponent), -1000, 1000));
        Float capacity = _f(coefficient, exponent);

        // Both buckets, so the headroom is this capacity and not the floor
        // of setUp's `UNBOUNDED_CAPACITY` on the other once the fuzz goes
        // past it.
        vm.startPrank(OWNER);
        orchestrator.setMinterMintLimit(MINTER_A, capacity, NO_LEAK);
        orchestrator.setRecipientMintLimit(address(capRecipient), capacity, NO_LEAK);
        vm.stopPrank();

        _assertFloatEq(
            orchestrator.mintHeadroom(MINTER_A, address(capRecipient)), capacity, "a fresh bucket offers one capacity"
        );
    }

    // ------------------------------------------------------------------ //
    //             Mint caps — no corporate-action dependency              //
    // ------------------------------------------------------------------ //

    /// The caps are value-based and read nothing from the token. A token whose
    /// whole corporate-action surface reverts can still have both limits
    /// written, still answers a headroom, and still mints under those limits:
    /// any setter that pinned a cursor, or any metering that read a
    /// multiplier, would fail here.
    function testMintCapsNeverReadTheTokensCorporateActions() external {
        bytes memory failure = abi.encodeWithSignature("FacetMustBeDelegatecalled()");
        vm.mockCallRevert(TOKEN, abi.encodeWithSelector(ICorporateActionsV1.completedActionCount.selector), failure);
        vm.mockCallRevert(
            TOKEN, abi.encodeWithSelector(ICorporateActionsV1.cumulativeBalanceMultiplierSinceGenesis.selector), failure
        );

        _grantMintOn(orchestrator, MINTER_A);
        vm.startPrank(OWNER);
        orchestrator.setMinterMintLimit(MINTER_A, _f(100e18), NO_LEAK);
        orchestrator.setRecipientMintLimit(address(capRecipient), _f(100e18), NO_LEAK);
        vm.stopPrank();

        _assertFloatEq(
            orchestrator.mintHeadroom(MINTER_A, address(capRecipient)),
            _f(100e18),
            "the headroom is answered from storage alone"
        );
        _capMint(orchestrator, MINTER_A, TOKEN, 100e18, keccak256("mute-token"));
        _assertFloatEq(
            orchestrator.mintHeadroom(MINTER_A, address(capRecipient)), ZERO, "the mint was metered as passed"
        );
    }

    /// The minter bucket is a plain sum of amounts across tokens: `100e18` of
    /// one token and `100e18` of another spend a `200e18` minter cap exactly,
    /// and the next unit of either is refused.
    function testMinterBucketSumsAmountsAcrossTokens() external {
        _grantMintOn(orchestrator, MINTER_A);
        vm.prank(OWNER);
        orchestrator.setMinterMintLimit(MINTER_A, _f(200e18), NO_LEAK);

        _capMint(orchestrator, MINTER_A, TOKEN, 100e18, keccak256("minter-token"));
        _capMint(orchestrator, MINTER_A, TOKEN2, 100e18, keccak256("minter-token2"));
        Float headroom = orchestrator.mintHeadroom(MINTER_A, address(capRecipient));
        _assertFloatEq(headroom, ZERO, "the minter bucket is spent");

        _mockCapMint(orchestrator, TOKEN2, 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.MinterMintCapExceeded.selector, MINTER_A, _f(200e18), headroom, _f(1)
            )
        );
        vm.prank(MINTER_A);
        orchestrator.mint(
            TOKEN2, address(capRecipient), 1, _auth("", keccak256("minter-full")), "", new SignedContextV1[](0)
        );
    }

    /// The `set` marker is what separates a deliberate zero from never set: a
    /// minter limit written as zero reverts `MinterMintCapExceeded` with
    /// the approved figures, not `MinterMintLimitUnset`.
    function testDeliberateZeroMinterLimitIsSetNotUnset() external {
        ST0xOrchestrator fresh = _unconfiguredOrchestrator();
        _grantMintOn(fresh, MINTER_A);
        assertFalse(fresh.minterMintLimit(MINTER_A).set, "never set");

        vm.startPrank(OWNER);
        fresh.setMinterMintLimit(MINTER_A, ZERO, NO_LEAK);
        fresh.setRecipientMintLimit(address(capRecipient), _f(100e18), NO_LEAK);
        vm.stopPrank();
        assertTrue(fresh.minterMintLimit(MINTER_A).set, "a deliberate zero reads back as SET");

        Float headroom = fresh.mintHeadroom(MINTER_A, address(capRecipient));
        _assertFloatEq(headroom, ZERO, "a zero capacity offers nothing");
        _mockCapMint(fresh, TOKEN, 1);
        vm.expectRevert(
            abi.encodeWithSelector(IST0xOrchestratorV1.MinterMintCapExceeded.selector, MINTER_A, ZERO, headroom, _f(1))
        );
        vm.prank(MINTER_A);
        fresh.mint(TOKEN, address(capRecipient), 1, _auth("", keccak256("zero-minter")), "", new SignedContextV1[](0));
    }

    /// And the same on the recipient side: a recipient limit written as zero
    /// reverts `RecipientMintCapExceeded` with the approved figures, not
    /// `RecipientMintLimitUnset`.
    function testDeliberateZeroRecipientLimitIsSetNotUnset() external {
        ST0xOrchestrator fresh = _unconfiguredOrchestrator();
        _grantMintOn(fresh, MINTER_A);
        assertFalse(fresh.recipientMintLimit(address(capRecipient)).set, "never set");

        vm.startPrank(OWNER);
        fresh.setMinterMintLimit(MINTER_A, _f(100e18), NO_LEAK);
        fresh.setRecipientMintLimit(address(capRecipient), ZERO, NO_LEAK);
        vm.stopPrank();
        assertTrue(fresh.recipientMintLimit(address(capRecipient)).set, "a deliberate zero reads back as SET");

        Float headroom = fresh.mintHeadroom(MINTER_A, address(capRecipient));
        _assertFloatEq(headroom, ZERO, "a zero capacity offers nothing");
        _mockCapMint(fresh, TOKEN, 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IST0xOrchestratorV1.RecipientMintCapExceeded.selector, address(capRecipient), ZERO, headroom, _f(1)
            )
        );
        vm.prank(MINTER_A);
        fresh.mint(
            TOKEN, address(capRecipient), 1, _auth("", keccak256("zero-recipient")), "", new SignedContextV1[](0)
        );
    }
}
