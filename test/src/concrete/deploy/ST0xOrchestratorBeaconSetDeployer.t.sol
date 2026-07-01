// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.16.1/src/Test.sol";

import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/UpgradeableBeacon.sol";
import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";
import {ERC1967Utils} from "@openzeppelin-contracts-5.6.1/proxy/ERC1967/ERC1967Utils.sol";
import {IERC165} from "@openzeppelin-contracts-5.6.1/utils/introspection/IERC165.sol";

import {OffchainAssetReceiptVault} from "rain-vats-0.1.6/src/concrete/vault/OffchainAssetReceiptVault.sol";
import {IReceiptVaultV3} from "rain-vats-0.1.6/src/interface/IReceiptVaultV3.sol";

import {
    ST0xOrchestratorBeaconSetDeployer,
    ST0xOrchestratorBeaconSetDeployerConfig,
    ZeroInitialOwner,
    ZeroOrchestratorImplementation,
    ZeroVault,
    ZeroOwner
} from "../../../../src/concrete/deploy/ST0xOrchestratorBeaconSetDeployer.sol";
import {ST0xOrchestrator} from "../../../../src/concrete/ST0xOrchestrator.sol";

/// A trivial contract used to give a fuzzed address `code.length > 0` for
/// constructor paths that only need the implementation to be a contract (the
/// beacon merely checks `code.length != 0`).
contract DummyImpl {
    uint256 public constant TAG = 0xDEAD;
}

/// A second trivial contract used to prove that beacon upgrades take effect on
/// existing clones — we deploy a clone against a real orchestrator impl, then
/// upgrade the beacon to point at this stub and observe the clone's view of
/// `implementation()` change.
contract UpgradedImpl {
    uint256 public constant TAG = 0xBEEF;
}

contract ST0xOrchestratorBeaconSetDeployerTest is Test {
    /// Storage slot the `BeaconProxy` writes its beacon address to on
    /// construction (ERC-1967). We probe this rather than the immutable
    /// because the immutable isn't accessible from outside the proxy.
    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    /// keccak256(abi.encode(uint256(keccak256("st0x.orchestrator.main")) - 1)) & ~bytes32(uint256(0xff))
    /// The ERC-7201 base slot for `ST0xOrchestrator`'s `MainStorage`. First
    /// field is `vault`, so `vm.load` at this slot reads the vault address.
    bytes32 internal constant MAIN_STORAGE_LOCATION =
        0x4bb94ceb743cdbfc320393e9b6fac11d883b2f90ac89bce731e459177c5be700;

    /// A freshly deployed real orchestrator implementation reused across the
    /// tests that need the beacon-proxy `initialize` delegatecall to succeed.
    ST0xOrchestrator internal orchestratorImpl;

    function setUp() external {
        orchestratorImpl = new ST0xOrchestrator();
    }

    // ---------------------------------------------------------------- //
    //                          Helpers                                 //
    // ---------------------------------------------------------------- //

    /// Build a deployer with the given owner and a real orchestrator impl.
    function _deployerWithOwner(address initialOwner) internal returns (ST0xOrchestratorBeaconSetDeployer) {
        return new ST0xOrchestratorBeaconSetDeployer(
            ST0xOrchestratorBeaconSetDeployerConfig({
                initialOwner: initialOwner, initialOrchestratorImplementation: address(orchestratorImpl)
            })
        );
    }

    /// Prepare a vault address so that `ST0xOrchestrator.initialize(vault_,
    /// owner)` succeeds against it: give it non-zero code so external calls
    /// route to the runtime, then mock the two views the initializer reads —
    /// `receipt()` and `highwaterId()` (pointer seeding).
    function _prepareVault(address vault_, address receiptAddr) internal {
        // Etch INVALID (0xfe) — unlike STOP, any un-mocked call reverts
        // loudly instead of silently succeeding with empty returndata.
        vm.etch(vault_, hex"fe");
        vm.mockCall(vault_, abi.encodeWithSelector(IReceiptVaultV3.receipt.selector), abi.encode(receiptAddr));
        vm.mockCall(vault_, abi.encodeWithSelector(OffchainAssetReceiptVault.highwaterId.selector), abi.encode(0));
    }

    /// Basic sanity guard for a fuzzed address that must be a plausible
    /// "user" EOA — non-zero, no code, not a precompile.
    function _assumeUsable(address a) internal view {
        vm.assume(a != address(0));
        vm.assume(a.code.length == 0);
        // Precompiles + a bit of headroom.
        vm.assume(uint160(a) > 0x100);
        // Avoid the test contract itself, the VM, and the created deployer's
        // typical CREATE range. We don't need surgical precision — just keep
        // fuzz mocks from clobbering something meaningful.
        vm.assume(a != address(this));
        vm.assume(a != address(vm));
        vm.assume(a != CONSOLE);
    }

    // ---------------------------------------------------------------- //
    //                        Constructor                               //
    // ---------------------------------------------------------------- //

    /// Constructor reverts with `ZeroInitialOwner` when `initialOwner` is
    /// zero, regardless of the impl passed (fuzzed to a valid contract).
    function testFuzzConstructorRevertsZeroInitialOwner(address impl) external {
        vm.assume(impl != address(0));
        // The beacon will require `impl.code.length != 0` if we get past the
        // owner check — but we shouldn't. Ensure the owner check fires first
        // by leaving the impl code state alone.
        vm.expectRevert(abi.encodeWithSelector(ZeroInitialOwner.selector));
        new ST0xOrchestratorBeaconSetDeployer(
            ST0xOrchestratorBeaconSetDeployerConfig({initialOwner: address(0), initialOrchestratorImplementation: impl})
        );
    }

    /// Constructor reverts with `ZeroOrchestratorImplementation` when the
    /// impl is zero and owner is non-zero.
    function testFuzzConstructorRevertsZeroOrchestratorImplementation(address initialOwner) external {
        vm.assume(initialOwner != address(0));
        vm.expectRevert(abi.encodeWithSelector(ZeroOrchestratorImplementation.selector));
        new ST0xOrchestratorBeaconSetDeployer(
            ST0xOrchestratorBeaconSetDeployerConfig({
                initialOwner: initialOwner, initialOrchestratorImplementation: address(0)
            })
        );
    }

    /// On success: beacon exists, its `implementation()` and `owner()`
    /// match the config, and the beacon address is non-zero.
    function testFuzzConstructorSuccess(address initialOwner, address impl) external {
        vm.assume(initialOwner != address(0));
        _assumeUsable(impl);
        // The UpgradeableBeacon constructor requires the impl to have code.
        vm.etch(impl, type(DummyImpl).runtimeCode);

        ST0xOrchestratorBeaconSetDeployer deployer = new ST0xOrchestratorBeaconSetDeployer(
            ST0xOrchestratorBeaconSetDeployerConfig({
                initialOwner: initialOwner, initialOrchestratorImplementation: impl
            })
        );

        IBeacon beacon = deployer.iOrchestratorBeacon();
        assertTrue(address(beacon) != address(0), "beacon must exist");
        assertGt(address(beacon).code.length, 0, "beacon must have code");
        assertEq(beacon.implementation(), impl, "beacon impl must match config");
        assertEq(Ownable(address(beacon)).owner(), initialOwner, "beacon owner must match config");
    }

    // ---------------------------------------------------------------- //
    //                          deploy                                  //
    // ---------------------------------------------------------------- //

    /// `deploy` reverts with `ZeroVault` when `vault_` is zero.
    function testFuzzDeployRevertsZeroVault(address initialOwner, address owner) external {
        vm.assume(initialOwner != address(0));
        vm.assume(owner != address(0));
        ST0xOrchestratorBeaconSetDeployer deployer = _deployerWithOwner(initialOwner);

        vm.expectRevert(abi.encodeWithSelector(ZeroVault.selector));
        deployer.deploy(OffchainAssetReceiptVault(payable(address(0))), owner);
    }

    /// `deploy` reverts with `ZeroOwner` when `owner` is zero (vault fuzzed
    /// to a non-zero address).
    function testFuzzDeployRevertsZeroOwner(address initialOwner, address vault_) external {
        vm.assume(initialOwner != address(0));
        vm.assume(vault_ != address(0));
        ST0xOrchestratorBeaconSetDeployer deployer = _deployerWithOwner(initialOwner);

        vm.expectRevert(abi.encodeWithSelector(ZeroOwner.selector));
        deployer.deploy(OffchainAssetReceiptVault(payable(vault_)), address(0));
    }

    /// Success path: emits the correct `Deployment` event with the sender,
    /// the returned proxy, and the vault. Also validates the proxy is
    /// non-zero, has code, its ERC-1967 beacon slot points at the deployer's
    /// beacon, and its `vault()` / `receipt()` / `nextBurnReceiptId()` /
    /// role assignments are all as expected. The `DEFAULT_ADMIN_ROLE` check
    /// is fuzzed over an "other" caller to prove the role is exclusive.
    function testFuzzDeploySuccess(
        address initialOwner,
        address vault_,
        address receiptAddr,
        address owner,
        address other
    ) external {
        vm.assume(initialOwner != address(0));
        vm.assume(owner != address(0));
        vm.assume(receiptAddr != address(0));
        vm.assume(other != owner);
        _assumeUsable(vault_);
        _prepareVault(vault_, receiptAddr);

        ST0xOrchestratorBeaconSetDeployer deployer = _deployerWithOwner(initialOwner);
        IBeacon beacon = deployer.iOrchestratorBeacon();

        // We can't know the CREATE address up-front without duplicating
        // BeaconProxy's constructor, so use recordLogs and pull the
        // Deployment event out afterwards to check topics + data.
        vm.recordLogs();
        address orchestrator = deployer.deploy(OffchainAssetReceiptVault(payable(vault_)), owner);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertTrue(orchestrator != address(0), "returned orchestrator must be non-zero");
        assertGt(orchestrator.code.length, 0, "returned orchestrator must have code");

        // Beacon-slot probe — proves the proxy is bound to our beacon.
        bytes32 slotBeacon = vm.load(orchestrator, BEACON_SLOT);
        assertEq(address(uint160(uint256(slotBeacon))), address(beacon), "proxy beacon slot must be our beacon");

        // ERC-7201 slot probe — first field is `vault`.
        bytes32 slotVault = vm.load(orchestrator, MAIN_STORAGE_LOCATION);
        assertEq(address(uint160(uint256(slotVault))), vault_, "erc7201 storage must hold vault");

        // Locate the Deployment event: 3 indexed topics + `owner` in data.
        bytes32 depSig = keccak256("Deployment(address,address,address,address)");
        bool found = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(deployer) && logs[i].topics.length == 4 && logs[i].topics[0] == depSig) {
                found = true;
                assertEq(address(uint160(uint256(logs[i].topics[1]))), address(this), "sender topic");
                assertEq(address(uint160(uint256(logs[i].topics[2]))), orchestrator, "orchestrator topic");
                assertEq(address(uint160(uint256(logs[i].topics[3]))), vault_, "vault topic");
                assertEq(abi.decode(logs[i].data, (address)), owner, "owner data field");
            }
        }
        assertTrue(found, "Deployment event must be emitted");

        // Clone-facing view checks.
        ST0xOrchestrator clone = ST0xOrchestrator(payable(orchestrator));
        assertEq(address(clone.vault()), vault_, "clone.vault()");
        assertEq(address(clone.receipt()), receiptAddr, "clone.receipt()");
        // Pointer seeds at mocked highwaterId (0) + 1.
        assertEq(clone.nextBurnReceiptId(), 1, "clone.nextBurnReceiptId()");
        assertTrue(clone.hasRole(0x00, owner), "owner has DEFAULT_ADMIN_ROLE");
        assertFalse(clone.hasRole(0x00, other), "other does not have DEFAULT_ADMIN_ROLE");
    }

    /// Anyone can call `deploy` — there's no auth on the deployer.
    function testFuzzDeployAnyCaller(
        address initialOwner,
        address caller,
        address vault_,
        address receiptAddr,
        address owner
    ) external {
        vm.assume(initialOwner != address(0));
        vm.assume(owner != address(0));
        vm.assume(receiptAddr != address(0));
        _assumeUsable(caller);
        _assumeUsable(vault_);
        vm.assume(vault_ != caller);
        _prepareVault(vault_, receiptAddr);

        ST0xOrchestratorBeaconSetDeployer deployer = _deployerWithOwner(initialOwner);

        vm.expectEmit(true, false, true, true, address(deployer));
        emit ST0xOrchestratorBeaconSetDeployer.Deployment(caller, address(0), vault_, owner);
        vm.prank(caller);
        address orchestrator = deployer.deploy(OffchainAssetReceiptVault(payable(vault_)), owner);

        assertTrue(orchestrator != address(0));
        assertGt(orchestrator.code.length, 0);
    }

    /// Multiple deploys against distinct `(vault, owner)` pairs each produce
    /// a unique proxy, and each is independently initialised. `n` is fuzzed
    /// in [1, 5].
    function testFuzzDeployMultipleDistinct(uint8 nRaw, uint256 seed) external {
        uint256 n = (uint256(nRaw) % 5) + 1;
        address initialOwner = address(0xB0B);
        ST0xOrchestratorBeaconSetDeployer deployer = _deployerWithOwner(initialOwner);

        address[] memory clones = new address[](n);
        address[] memory vaults = new address[](n);
        address[] memory receipts = new address[](n);
        address[] memory owners = new address[](n);

        for (uint256 i = 0; i < n; i++) {
            // Derive fresh addresses per iteration. Keep well clear of low
            // precompile range and of previously-generated addresses.
            address vault_ = address(uint160(uint256(keccak256(abi.encode(seed, "vault", i))) | 0x1000000));
            address receiptAddr = address(uint160(uint256(keccak256(abi.encode(seed, "receipt", i))) | 0x1000000));
            address owner = address(uint160(uint256(keccak256(abi.encode(seed, "owner", i))) | 0x1000000));

            // Cheap duplicate check against prior iterations.
            for (uint256 j = 0; j < i; j++) {
                vm.assume(vault_ != vaults[j]);
                vm.assume(receiptAddr != receipts[j]);
                vm.assume(owner != owners[j]);
            }

            _prepareVault(vault_, receiptAddr);
            address clone = deployer.deploy(OffchainAssetReceiptVault(payable(vault_)), owner);

            for (uint256 j = 0; j < i; j++) {
                assertTrue(clone != clones[j], "proxy addresses must be distinct");
            }

            ST0xOrchestrator o = ST0xOrchestrator(payable(clone));
            assertEq(address(o.vault()), vault_, "vault");
            assertEq(address(o.receipt()), receiptAddr, "receipt");
            assertTrue(o.hasRole(0x00, owner), "owner role");

            clones[i] = clone;
            vaults[i] = vault_;
            receipts[i] = receiptAddr;
            owners[i] = owner;
        }
    }

    // ---------------------------------------------------------------- //
    //                     supportsInterface                            //
    // ---------------------------------------------------------------- //

    /// `supportsInterface(IERC165)` is true; anything else that isn't the
    /// EIP-165 invalid sentinel is false.
    function testFuzzSupportsInterface(bytes4 selector) external {
        vm.assume(selector != type(IERC165).interfaceId);
        vm.assume(selector != 0xffffffff);
        ST0xOrchestratorBeaconSetDeployer deployer = _deployerWithOwner(address(0xB0B));
        assertTrue(deployer.supportsInterface(type(IERC165).interfaceId));
        assertFalse(deployer.supportsInterface(selector));
    }

    // ---------------------------------------------------------------- //
    //                     Beacon upgrade path                          //
    // ---------------------------------------------------------------- //

    /// Beacon owner can upgrade the impl; existing clones follow along. We
    /// prove the change by reading the beacon's `implementation()` before
    /// and after — that is what every clone delegates through.
    function testBeaconUpgradeRedirectsClones() external {
        address initialOwner = address(0xB0B);
        ST0xOrchestratorBeaconSetDeployer deployer = _deployerWithOwner(initialOwner);
        IBeacon beacon = deployer.iOrchestratorBeacon();

        // Deploy one clone against the real impl so we know the setup works.
        address vault_ = address(0xCAFE);
        address receiptAddr = address(0xBEEF);
        _prepareVault(vault_, receiptAddr);
        address clone = deployer.deploy(OffchainAssetReceiptVault(payable(vault_)), address(0xABCD));

        assertEq(beacon.implementation(), address(orchestratorImpl), "impl before upgrade");

        // Upgrade the beacon to a fresh impl.
        UpgradedImpl newImpl = new UpgradedImpl();
        vm.prank(initialOwner);
        UpgradeableBeacon(address(beacon)).upgradeTo(address(newImpl));

        assertEq(beacon.implementation(), address(newImpl), "impl after upgrade");
        // The clone still reads through the beacon — its beacon slot is
        // unchanged, its impl (transitively) is the new one.
        bytes32 slotBeacon = vm.load(clone, BEACON_SLOT);
        assertEq(address(uint160(uint256(slotBeacon))), address(beacon), "clone still bound to beacon");
        // Observe the redirection by CALLING THROUGH the clone: TAG() only
        // exists on UpgradedImpl, so a successful call proves live
        // delegation to the new impl (a proxy that cached the old impl at
        // construction would revert here).
        assertEq(UpgradedImpl(clone).TAG(), 0xBEEF, "clone delegates to upgraded impl");
    }

    /// Non-owner cannot upgrade the beacon.
    function testFuzzBeaconUpgradeUnauthorised(address notOwner) external {
        address initialOwner = address(0xB0B);
        vm.assume(notOwner != initialOwner);
        vm.assume(notOwner != address(0));
        ST0xOrchestratorBeaconSetDeployer deployer = _deployerWithOwner(initialOwner);
        IBeacon beacon = deployer.iOrchestratorBeacon();

        UpgradedImpl newImpl = new UpgradedImpl();
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        UpgradeableBeacon(address(beacon)).upgradeTo(address(newImpl));
    }
}
