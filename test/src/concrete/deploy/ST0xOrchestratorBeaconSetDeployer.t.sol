// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.16.2/src/Test.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/UpgradeableBeacon.sol";
import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";
import {IERC165} from "@openzeppelin-contracts-5.6.1/utils/introspection/IERC165.sol";

import {ST0xOrchestratorBeaconSetDeployer} from "../../../../src/concrete/deploy/ST0xOrchestratorBeaconSetDeployer.sol";
import {UpgradedImpl} from "./UpgradedImpl.sol";
import {ST0xOrchestrator, ST0X_TOKEN_OWNER_SAFE_NAME} from "../../../../src/concrete/ST0xOrchestrator.sol";
import {LibTestAddressRegistry} from "../../lib/LibTestAddressRegistry.sol";
import {LibTestMigrationRegistry} from "../../lib/LibTestMigrationRegistry.sol";
import {IAddressRegistryV1} from "rain-deploy-0.1.11/src/interface/IAddressRegistryV1.sol";
import {IST0xVaultBeaconSet} from "../../../../src/interface/IST0xVaultBeaconSet.sol";
import {LibProdDeployV4} from "../../../../src/generated/LibProdDeployV4.sol";
import {IST0xOrchestratorBeaconSetDeployerV1} from "../../../../src/interface/IST0xOrchestratorBeaconSetDeployerV1.sol";

contract ST0xOrchestratorBeaconSetDeployerTest is Test {
    // ERC-1967 beacon slot.
    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    /// The orchestrator's vault-logic version guard (run by `initialize`,
    /// i.e. inside `deploy`) reads these fixed production addresses.
    address internal constant GUARD_DEPLOYER =
        LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CANDIDATE;
    address internal constant VAULT_BEACON = address(0xBEAC04);
    address internal constant RECEIPT_BEACON = address(0xBEAC12);

    ST0xOrchestrator internal impl;

    function setUp() public {
        impl = new ST0xOrchestrator();
        // The Zoltu deployer hardcodes the beacon implementation to the fixed
        // production impl address (`ST0X_ORCHESTRATOR_CANDIDATE`), so etch
        // the freshly-built orchestrator runtime there — the beacon requires
        // code at that address, and `deploy` delegatecalls it via the proxy.
        vm.etch(LibProdDeployV4.ST0X_ORCHESTRATOR_CANDIDATE, address(impl).code);
        // `deploy` initialises the proxy, which runs the orchestrator's
        // vault-logic version guard — install passing mocks up front.
        _makeGuardPass();
        // Every deploy records a migration, so the registry has to be present
        // for all of them, not only the ones that bind an owner inline.
        LibTestMigrationRegistry.etch(vm);
    }

    /// Make the orchestrator's vault-logic version guard PASS: the production
    /// deployer resolves each beacon and each beacon reports the expected
    /// implementation.
    function _makeGuardPass() internal {
        vm.mockCall(
            GUARD_DEPLOYER,
            abi.encodeWithSelector(IST0xVaultBeaconSet.iOffchainAssetReceiptVaultBeacon.selector),
            abi.encode(VAULT_BEACON)
        );
        vm.mockCall(
            GUARD_DEPLOYER,
            abi.encodeWithSelector(IST0xVaultBeaconSet.iReceiptBeacon.selector),
            abi.encode(RECEIPT_BEACON)
        );
        vm.mockCall(
            VAULT_BEACON,
            abi.encodeWithSelector(IBeacon.implementation.selector),
            abi.encode(LibProdDeployV4.STOX_RECEIPT_VAULT_CANDIDATE)
        );
        vm.mockCall(
            RECEIPT_BEACON,
            abi.encodeWithSelector(IBeacon.implementation.selector),
            abi.encode(LibProdDeployV4.STOX_RECEIPT_CANDIDATE)
        );
    }

    function _deployer() internal returns (ST0xOrchestratorBeaconSetDeployer) {
        return new ST0xOrchestratorBeaconSetDeployer();
    }

    /// The no-arg constructor bakes the beacon owner + implementation from
    /// `LibProdDeployV4`.
    function testConstructorSuccess() external {
        ST0xOrchestratorBeaconSetDeployer d = _deployer();
        IBeacon beacon = d.iOrchestratorBeacon();
        assertEq(beacon.implementation(), LibProdDeployV4.ST0X_ORCHESTRATOR_CANDIDATE, "beacon impl");
        assertEq(Ownable(address(beacon)).owner(), LibProdDeployV4.BEACON_INITIAL_OWNER, "beacon owner");
    }

    /// There is no zero-owner path left to guard: the owner comes from the
    /// registry, which refuses to bind the zero address, and an unbound name
    /// reverts the read. So the deployer's failure mode on a chain with
    /// nothing bound is the registry's own error, not one of ours.
    function testDeployRevertsOnAnUnboundName() external {
        ST0xOrchestratorBeaconSetDeployer d = _deployer();
        LibTestAddressRegistry.etch(vm);
        LibTestAddressRegistry.unbind(vm, ST0X_TOKEN_OWNER_SAFE_NAME);
        vm.expectRevert(
            abi.encodeWithSelector(IAddressRegistryV1.NameNotRegistered.selector, ST0X_TOKEN_OWNER_SAFE_NAME)
        );
        d.deploy();
    }

    /// The caller does not choose the owner. `caller` is pranked and is not
    /// the bound address, and the deployed instance's admin is the bound
    /// address regardless.
    function testFuzzDeploySuccess(address owner, address caller) external {
        vm.assume(owner != address(0));
        vm.assume(caller != address(0));
        vm.assume(caller != owner);
        ST0xOrchestratorBeaconSetDeployer d = _deployer();
        IBeacon beacon = d.iOrchestratorBeacon();
        LibTestAddressRegistry.etchAndBind(vm, ST0X_TOKEN_OWNER_SAFE_NAME, owner);
        LibTestMigrationRegistry.etch(vm);

        vm.recordLogs();
        vm.prank(caller);
        address orchestrator = d.deploy();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertTrue(orchestrator != address(0), "non-zero");
        assertGt(orchestrator.code.length, 0, "has code");
        // Bound to the beacon.
        assertEq(address(uint160(uint256(vm.load(orchestrator, BEACON_SLOT)))), address(beacon), "beacon slot");
        // Owner holds DEFAULT_ADMIN_ROLE; not vault-bound (singleton).
        ST0xOrchestrator o = ST0xOrchestrator(payable(orchestrator));
        assertTrue(o.hasRole(0x00, owner), "owner is admin");
        assertFalse(o.hasRole(0x00, caller), "caller not admin");

        // Deployment(sender, orchestrator, owner) — sender+orchestrator indexed, owner in data.
        bytes32 sig = keccak256("Deployment(address,address,address)");
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(d) && logs[i].topics.length == 3 && logs[i].topics[0] == sig) {
                found = true;
                assertEq(address(uint160(uint256(logs[i].topics[1]))), caller, "sender topic");
                assertEq(address(uint160(uint256(logs[i].topics[2]))), orchestrator, "orchestrator topic");
                assertEq(abi.decode(logs[i].data, (address)), owner, "owner data");
            }
        }
        assertTrue(found, "Deployment emitted");
    }

    /// Two deploys give two proxies even under one binding — the owner is
    /// not what distinguishes them. The second is also deployed after the
    /// binding moved, to show the proxies take the value live at their own
    /// construction rather than the deployer caching one.
    function testDeployMultipleDistinct() external {
        ST0xOrchestratorBeaconSetDeployer d = _deployer();
        LibTestAddressRegistry.etchAndBind(vm, ST0X_TOKEN_OWNER_SAFE_NAME, address(0xA11CE));
        address a = d.deploy();
        LibTestAddressRegistry.bind(vm, ST0X_TOKEN_OWNER_SAFE_NAME, address(0xBEEF));
        address b = d.deploy();
        assertTrue(a != b, "distinct proxies");
        assertTrue(ST0xOrchestrator(payable(a)).hasRole(0x00, address(0xA11CE)), "first took the first binding");
        assertTrue(ST0xOrchestrator(payable(b)).hasRole(0x00, address(0xBEEF)), "second took the second");
        assertFalse(ST0xOrchestrator(payable(a)).hasRole(0x00, address(0xBEEF)), "rebind moved the first");
    }

    function testBeaconUpgradeRedirectsSingleton() external {
        ST0xOrchestratorBeaconSetDeployer d = _deployer();
        IBeacon beacon = d.iOrchestratorBeacon();
        LibTestAddressRegistry.etchAndBind(vm, ST0X_TOKEN_OWNER_SAFE_NAME, address(0xA11CE));
        address orchestrator = d.deploy();

        UpgradedImpl newImpl = new UpgradedImpl();
        // The beacon owner is the fixed production owner, not a deploy param.
        vm.prank(LibProdDeployV4.BEACON_INITIAL_OWNER);
        UpgradeableBeacon(address(beacon)).upgradeTo(address(newImpl));

        // Call through the proxy proves live delegation to the new impl.
        assertEq(UpgradedImpl(orchestrator).TAG(), 0xBEEF, "delegates to upgraded impl");
    }

    function testFuzzBeaconUpgradeUnauthorised(address notOwner) external {
        vm.assume(notOwner != LibProdDeployV4.BEACON_INITIAL_OWNER && notOwner != address(0));
        ST0xOrchestratorBeaconSetDeployer d = _deployer();
        IBeacon beacon = d.iOrchestratorBeacon();
        UpgradedImpl newImpl = new UpgradedImpl();
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        UpgradeableBeacon(address(beacon)).upgradeTo(address(newImpl));
    }

    function testSupportsInterface() external {
        ST0xOrchestratorBeaconSetDeployer d = _deployer();
        // Both advertised interfaces report true.
        assertTrue(d.supportsInterface(type(IST0xOrchestratorBeaconSetDeployerV1).interfaceId), "V1");
        assertTrue(d.supportsInterface(type(IERC165).interfaceId), "IERC165");
        // ERC-165 requires the 0xffffffff sentinel to always be unsupported.
        assertFalse(d.supportsInterface(0xffffffff), "0xffffffff");
    }

    /// No false positives: every interface id other than the two advertised
    /// ones must report unsupported.
    function testFuzzSupportsInterfaceRejectsOthers(bytes4 badInterfaceId) external {
        vm.assume(badInterfaceId != type(IST0xOrchestratorBeaconSetDeployerV1).interfaceId);
        vm.assume(badInterfaceId != type(IERC165).interfaceId);
        ST0xOrchestratorBeaconSetDeployer d = _deployer();
        assertFalse(d.supportsInterface(badInterfaceId), "no false positive");
    }
}
