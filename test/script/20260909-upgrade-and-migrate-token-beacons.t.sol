// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {Vm} from "forge-std-1.16.1/src/Vm.sol";
import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.6.1/token/ERC20/extensions/IERC20Metadata.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {
    OffchainAssetReceiptVaultConfigV2
} from "rain-vats-0.1.6/src/concrete/deploy/OffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {ReceiptVaultConfigV2} from "rain-vats-0.1.6/src/abstract/ReceiptVault.sol";

import {
    UpgradeAndMigrateTokenBeacons,
    NotA0_1_1BootstrapChain
} from "../../script/20260909-upgrade-and-migrate-token-beacons.s.sol";
import {UpgradeAndMigrateTokenBeaconsHarness} from "./UpgradeAndMigrateTokenBeaconsHarness.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibProdBeacons0_1_1} from "../../src/lib/LibProdBeacons0_1_1.sol";
import {LibBeaconInvariants, BeaconOwnerMismatch} from "../../src/lib/LibBeaconInvariants.sol";
import {ClosureCodehashMismatch} from "../../src/lib/LibClosureInvariants.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {IOwnable} from "../../src/interface/IOwnable.sol";
import {IStoxUnifiedDeployerV1} from "../../src/interface/IStoxUnifiedDeployerV1.sol";

/// @title UpgradeAndMigrateTokenBeaconsTest
/// @notice The chain-generic 0.1.1 token-beacon bootstrap refuses every
/// chain it must not touch: Base (in-use beacons are the V1 set), any chain
/// missing the 0.1.30 upgrade targets, and any chain whose beacons have
/// already left the deploy EOA. The positive path is the live broadcast on
/// a freshly bootstrapped chain, whose forcing function is that chain's
/// `*BeaconOwnershipTest`; what the script must land is pinned here against
/// Ethereum, which reached the same end state through the Safe-signed fleet
/// upgrade, and the claim that tokens are then born on 0.1.30 through the
/// 0.1.1 unified deployer is proven on the Ethereum fork.
contract UpgradeAndMigrateTokenBeaconsTest is Test {
    /// @notice ERC-1967 beacon slot: `keccak256("eip1967.proxy.beacon") - 1`.
    bytes32 internal constant ERC1967_BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    /// @notice Base's in-use production beacons are its V1-generation set,
    /// so the 0.1.1 bootstrap does not apply and is refused before any
    /// owner read.
    function testRefusesBase() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        UpgradeAndMigrateTokenBeacons script = new UpgradeAndMigrateTokenBeacons();
        vm.expectRevert(abi.encodeWithSelector(NotA0_1_1BootstrapChain.selector, LibSafeInvariants.BASE_CHAIN_ID));
        script.run();
    }

    /// @notice A chain whose beacons already migrated is refused on the
    /// EOA-owner pre-flight rather than re-run — Ethereum's beacons left the
    /// deploy EOA on 2026-07-16. The 0.1.30 targets are live there, so the
    /// closure gate passes and the owner check is the refusal.
    function testRefusesAnAlreadyMigratedChain() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        address receiptBeacon = LibProdBeacons0_1_1.beacons()[LibBeaconInvariants.RECEIPT_BEACON_INDEX];
        address currentOwner = IOwnable(receiptBeacon).owner();
        assertNotEq(currentOwner, LibProdDeployV4.BEACON_INITIAL_OWNER, "Ethereum receipt beacon still EOA-owned");

        UpgradeAndMigrateTokenBeacons script = new UpgradeAndMigrateTokenBeacons();
        vm.expectRevert(
            abi.encodeWithSelector(
                BeaconOwnerMismatch.selector, receiptBeacon, LibProdDeployV4.BEACON_INITIAL_OWNER, currentOwner
            )
        );
        script.run();
    }

    /// @notice A chain without the audited 0.1.30 targets at their pins is
    /// refused on the closure gate BEFORE the beacon state is read: the
    /// upgrade half has nothing to point at, and the refusal names the
    /// missing target rather than a misleading beacon error. Ethereum's
    /// beacons are already migrated, so the closure gate firing first is
    /// what this proves.
    function testRefusesAChainWithoutTheUpgradeTargets() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        vm.etch(LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30, hex"fe");

        UpgradeAndMigrateTokenBeacons script = new UpgradeAndMigrateTokenBeacons();
        vm.expectRevert(
            abi.encodeWithSelector(
                ClosureCodehashMismatch.selector,
                LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30,
                LibProdDeployV4.STOX_RECEIPT_VAULT_CODEHASH_0_1_30,
                keccak256(hex"fe")
            )
        );
        script.run();
    }

    /// @notice The end state this script lands on a fresh chain is exactly
    /// where Ethereum's in-use beacons sit after the Safe-signed fleet
    /// upgrade executed: receipt + receipt vault on 0.1.30, wrapped token
    /// vault still on 0.1.1. Cross-chain parity is on where the beacons
    /// point, so the two routes must converge.
    function testPostImplementationsMatchTheExecutedFleetUpgrade() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        UpgradeAndMigrateTokenBeaconsHarness harness = new UpgradeAndMigrateTokenBeaconsHarness();
        address[3] memory post = harness.callPostImplementations();
        address[4] memory beacons = LibProdBeacons0_1_1.beacons();
        for (uint256 i = 0; i < post.length; i++) {
            assertEq(IBeacon(beacons[i]).implementation(), post[i], "Ethereum beacon impl != script end state");
        }
        assertEq(post[LibBeaconInvariants.RECEIPT_BEACON_INDEX], LibProdDeployV4.STOX_RECEIPT_0_1_30);
        assertEq(post[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX], LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30);
        assertEq(
            post[LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX], LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_0_1_1
        );
    }

    /// @notice On a fresh chain the token deploy runs AFTER this script, so
    /// the 0.1.1 unified deployer creates proxies against beacons that
    /// already serve 0.1.30. Ethereum is that exact configuration today
    /// (0.1.1 unified deployer, beacons repointed by the fleet upgrade), so
    /// a deploy through it on the fork proves the 0.1.1 deployer's
    /// `initialize` payload is accepted by the 0.1.30 vault logic and the
    /// new proxy resolves through the pinned beacon to 0.1.30.
    function testTokensAreBornOn0_1_30ThroughThe0_1_1UnifiedDeployer() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        address unified = LibProdDeployV4.STOX_UNIFIED_DEPLOYER_0_1_1;
        address receiptVaultBeacon = LibProdBeacons0_1_1.beacons()[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX];
        assertEq(
            IBeacon(receiptVaultBeacon).implementation(),
            LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30,
            "precondition: Ethereum receipt-vault beacon is on 0.1.30"
        );

        OffchainAssetReceiptVaultConfigV2 memory config = OffchainAssetReceiptVaultConfigV2({
            initialAdmin: address(this),
            receiptVaultConfig: ReceiptVaultConfigV2({
                asset: address(0), name: "Probe", symbol: "PROBE", receipt: address(0)
            })
        });
        vm.recordLogs();
        IStoxUnifiedDeployerV1(unified).newTokenAndWrapperVault(config);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256("Deployment(address,address,address)");
        address vault;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == unified && logs[i].topics[0] == topic) {
                (, vault,) = abi.decode(logs[i].data, (address, address, address));
            }
        }
        assertNotEq(vault, address(0), "unified deployer did not emit Deployment");
        assertEq(
            address(uint160(uint256(vm.load(vault, ERC1967_BEACON_SLOT)))),
            receiptVaultBeacon,
            "new vault does not resolve through the pinned receipt-vault beacon"
        );
        assertEq(IERC20Metadata(vault).symbol(), "PROBE", "0.1.30 vault logic did not initialise the proxy");
        assertEq(IOwnable(vault).owner(), address(this), "initialAdmin did not land as owner");
    }
}
