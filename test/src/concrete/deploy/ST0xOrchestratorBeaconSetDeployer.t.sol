// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";
import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {IERC165} from "@openzeppelin-contracts-5.7.0/utils/introspection/IERC165.sol";

import {ST0xOrchestratorBeaconSetDeployer} from "../../../../src/concrete/deploy/ST0xOrchestratorBeaconSetDeployer.sol";
import {UpgradedImpl} from "./UpgradedImpl.sol";
import {ST0xOrchestrator} from "../../../../src/concrete/ST0xOrchestrator.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {
    LibTimelockInvariants,
    UnsupportedChainForGovernanceTimelock
} from "../../../../src/lib/LibTimelockInvariants.sol";
import {IST0xVaultBeaconSet} from "../../../../src/interface/IST0xVaultBeaconSet.sol";
import {LibProdDeployV4} from "../../../../src/generated/LibProdDeployV4.sol";
import {IST0xOrchestratorBeaconSetDeployerV2} from "../../../../src/interface/IST0xOrchestratorBeaconSetDeployerV2.sol";

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
        // `initialize` seats the chain's timelock, so the default test chain
        // id (which has none) would revert every deploy.
        vm.chainId(LibSafeInvariants.BASE_CHAIN_ID);
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

    /// The no-arg constructor bakes the beacon implementation from
    /// `LibProdDeployV4` and hands the beacon to the chain's timelock: the
    /// deploy key never owns it.
    function testFuzzConstructorSuccess(uint256 chainIndex) external {
        (uint256 chainId, address timelock) = _chain(chainIndex);
        vm.chainId(chainId);
        ST0xOrchestratorBeaconSetDeployer d = _deployer();
        IBeacon beacon = d.iOrchestratorBeacon();
        assertEq(beacon.implementation(), LibProdDeployV4.ST0X_ORCHESTRATOR_CANDIDATE, "beacon impl");
        assertEq(Ownable(address(beacon)).owner(), timelock, "beacon owner");
        assertTrue(timelock != LibProdDeployV4.BEACON_INITIAL_OWNER, "not the deploy key");
    }

    /// A chain with no pinned timelock has no beacon owner, so the deployer
    /// cannot be constructed there.
    function testConstructorRevertsOnAChainWithNoTimelock() external {
        vm.chainId(1337);
        vm.expectRevert(abi.encodeWithSelector(UnsupportedChainForGovernanceTimelock.selector, uint256(1337)));
        new ST0xOrchestratorBeaconSetDeployer();
    }

    /// The chains with a pinned governance timelock, each paired with it.
    function _chain(uint256 index) internal pure returns (uint256 chainId, address timelock) {
        uint256[5] memory chainIds = [
            LibSafeInvariants.BASE_CHAIN_ID,
            LibSafeInvariants.ETHEREUM_CHAIN_ID,
            LibSafeInvariants.HYPEREVM_CHAIN_ID,
            LibSafeInvariants.ROBINHOOD_CHAIN_ID,
            LibSafeInvariants.BSC_CHAIN_ID
        ];
        chainId = chainIds[index % chainIds.length];
        timelock = LibTimelockInvariants.timelockForChainId(chainId);
    }

    /// A chain with no pinned timelock has no owner to seat, so `deploy`
    /// reverts rather than deploying an instance nobody governs.
    function testDeployRevertsOnAChainWithNoTimelock() external {
        ST0xOrchestratorBeaconSetDeployer d = _deployer();
        vm.chainId(1337);
        vm.expectRevert(abi.encodeWithSelector(UnsupportedChainForGovernanceTimelock.selector, uint256(1337)));
        d.deploy();
    }

    /// The caller does not choose the owner: on every chain the deployed
    /// instance's admin is that chain's timelock, whoever calls.
    function testFuzzDeploySuccess(uint256 chainIndex, address caller) external {
        (uint256 chainId, address timelock) = _chain(chainIndex);
        vm.assume(caller != address(0));
        vm.assume(caller != timelock);
        vm.chainId(chainId);
        ST0xOrchestratorBeaconSetDeployer d = _deployer();
        IBeacon beacon = d.iOrchestratorBeacon();

        vm.recordLogs();
        vm.prank(caller);
        address orchestrator = d.deploy();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertTrue(orchestrator != address(0), "non-zero");
        assertGt(orchestrator.code.length, 0, "has code");
        // Bound to the beacon.
        assertEq(address(uint160(uint256(vm.load(orchestrator, BEACON_SLOT)))), address(beacon), "beacon slot");
        // The timelock holds DEFAULT_ADMIN_ROLE; not vault-bound (singleton).
        ST0xOrchestrator o = ST0xOrchestrator(payable(orchestrator));
        assertTrue(o.hasRole(0x00, timelock), "timelock is admin");
        assertFalse(o.hasRole(0x00, caller), "caller not admin");

        // Deployment(sender, orchestrator, owner) — sender+orchestrator indexed, owner in data.
        bytes32 sig = keccak256("Deployment(address,address,address)");
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(d) && logs[i].topics.length == 3 && logs[i].topics[0] == sig) {
                found = true;
                assertEq(address(uint160(uint256(logs[i].topics[1]))), caller, "sender topic");
                assertEq(address(uint160(uint256(logs[i].topics[2]))), orchestrator, "orchestrator topic");
                assertEq(abi.decode(logs[i].data, (address)), timelock, "owner data");
            }
        }
        assertTrue(found, "Deployment emitted");
    }

    /// Two deploys give two proxies under the same owner: the owner is not
    /// what distinguishes them.
    function testDeployMultipleDistinct() external {
        vm.chainId(LibSafeInvariants.BASE_CHAIN_ID);
        ST0xOrchestratorBeaconSetDeployer d = _deployer();
        address a = d.deploy();
        address b = d.deploy();
        assertTrue(a != b, "distinct proxies");
        address timelock = LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK;
        assertTrue(ST0xOrchestrator(payable(a)).hasRole(0x00, timelock), "first seats the timelock");
        assertTrue(ST0xOrchestrator(payable(b)).hasRole(0x00, timelock), "second seats the timelock");
    }

    function testBeaconUpgradeRedirectsSingleton() external {
        ST0xOrchestratorBeaconSetDeployer d = _deployer();
        IBeacon beacon = d.iOrchestratorBeacon();
        address orchestrator = d.deploy();

        UpgradedImpl newImpl = new UpgradedImpl();
        // The beacon owner is the chain's timelock, not a deploy param.
        vm.prank(LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK);
        UpgradeableBeacon(address(beacon)).upgradeTo(address(newImpl));

        // Call through the proxy proves live delegation to the new impl.
        assertEq(UpgradedImpl(orchestrator).TAG(), 0xBEEF, "delegates to upgraded impl");
    }

    function testFuzzBeaconUpgradeUnauthorised(address notOwner) external {
        vm.assume(notOwner != LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK && notOwner != address(0));
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
        assertTrue(d.supportsInterface(type(IST0xOrchestratorBeaconSetDeployerV2).interfaceId), "V2");
        assertTrue(d.supportsInterface(type(IERC165).interfaceId), "IERC165");
        // ERC-165 requires the 0xffffffff sentinel to always be unsupported.
        assertFalse(d.supportsInterface(0xffffffff), "0xffffffff");
    }

    /// No false positives: every interface id other than the two advertised
    /// ones must report unsupported.
    function testFuzzSupportsInterfaceRejectsOthers(bytes4 badInterfaceId) external {
        vm.assume(badInterfaceId != type(IST0xOrchestratorBeaconSetDeployerV2).interfaceId);
        vm.assume(badInterfaceId != type(IERC165).interfaceId);
        ST0xOrchestratorBeaconSetDeployer d = _deployer();
        assertFalse(d.supportsInterface(badInterfaceId), "no false positive");
    }
}
