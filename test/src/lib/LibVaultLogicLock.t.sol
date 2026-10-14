// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin-contracts-5.7.0/proxy/beacon/BeaconProxy.sol";
import {LibRainDeploy} from "rain-deploy-0.1.18/src/lib/LibRainDeploy.sol";
import {ReceiptVault} from "rain-vats-0.2.4/src/abstract/ReceiptVault.sol";

import {IST0xOrchestratorV1} from "../../../src/interface/IST0xOrchestratorV1.sol";
import {LibBeaconInvariants, IOwnable, UnsupportedChainForProdBeacons} from "../../../src/lib/LibBeaconInvariants.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "../../../src/lib/LibTokenInvariants.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {LibVaultLogicLockHarness} from "./LibVaultLogicLockHarness.sol";

/// @dev Unpinned head forks: the live fleet and beacons are what is checked.
contract LibVaultLogicLockTest is Test {
    address internal constant VAULT_IMPL = LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30;
    address internal constant RECEIPT_IMPL = LibProdDeployV4.STOX_RECEIPT_0_1_30;

    LibVaultLogicLockHarness internal harness;

    function _fork(string memory network) internal {
        vm.createSelectFork(network);
        harness = new LibVaultLogicLockHarness();
    }

    function _assertFleetPasses(TokenInstance[] memory tokens) internal {
        address[4] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(block.chainid);
        bytes32[2] memory pins = LibBeaconInvariants.prodProxyCodehashesForChainId(block.chainid);
        for (uint256 i = 0; i < pins.length; i++) {
            assertEq(address(new BeaconProxy(beacons[i], "")).codehash, pins[i], "pin is a production-beacon proxy");
        }

        assertTrue(harness.prodBeaconsServe(VAULT_IMPL, RECEIPT_IMPL), "beacons serve 0.1.30");
        assertTrue(tokens.length > 0, "no production tokens");
        for (uint256 i = 0; i < tokens.length; i++) {
            assertEq(
                address(ReceiptVault(payable(tokens[i].receiptVault)).receipt()),
                tokens[i].receipt,
                tokens[i].underlying
            );
            harness.checkToken(tokens[i].receiptVault, VAULT_IMPL, RECEIPT_IMPL);
        }
    }

    function _repoint(address beacon, address impl) internal {
        vm.prank(IOwnable(beacon).owner());
        UpgradeableBeacon(beacon).upgradeTo(impl);
    }

    function _assertRefusals(TokenInstance memory token) internal {
        bytes32 vaultPin = LibBeaconInvariants.prodProxyCodehashesForChainId(
            block.chainid
        )[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX];
        address[2] memory notVaults = [token.wrappedTokenVault, token.receipt];
        for (uint256 i = 0; i < notVaults.length; i++) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IST0xOrchestratorV1.VaultProxyCodehashMismatch.selector,
                    notVaults[i],
                    vaultPin,
                    notVaults[i].codehash
                )
            );
            harness.checkToken(notVaults[i], VAULT_IMPL, RECEIPT_IMPL);
        }

        address[4] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(block.chainid);
        address vaultBeacon = beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX];
        address receiptBeacon = beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX];
        address newImpl = address(new LibVaultLogicLockHarness());

        _repoint(vaultBeacon, newImpl);
        assertFalse(harness.prodBeaconsServe(VAULT_IMPL, RECEIPT_IMPL), "vault beacon repointed");
        vm.expectRevert(abi.encodeWithSelector(IST0xOrchestratorV1.VaultLogicMismatch.selector, VAULT_IMPL, newImpl));
        harness.checkToken(token.receiptVault, VAULT_IMPL, RECEIPT_IMPL);

        _repoint(vaultBeacon, VAULT_IMPL);
        _repoint(receiptBeacon, newImpl);
        assertFalse(harness.prodBeaconsServe(VAULT_IMPL, RECEIPT_IMPL), "receipt beacon repointed");
        vm.expectRevert(
            abi.encodeWithSelector(IST0xOrchestratorV1.ReceiptLogicMismatch.selector, RECEIPT_IMPL, newImpl)
        );
        harness.checkToken(token.receiptVault, VAULT_IMPL, RECEIPT_IMPL);
    }

    function testBaseFleetPassesLock() external {
        _fork(LibRainDeploy.BASE);
        _assertFleetPasses(LibTokenInvariants.productionTokensBase());
    }

    function testEthereumFleetPassesLock() external {
        _fork(LibStoxDeployNetworks.ETHEREUM);
        _assertFleetPasses(LibTokenInvariants.productionTokensEthereum());
    }

    function testHyperEvmFleetPassesLock() external {
        _fork(LibStoxDeployNetworks.HYPEREVM);
        _assertFleetPasses(LibTokenInvariants.productionTokensHyperEvm());
    }

    function testRobinhoodFleetPassesLock() external {
        _fork(LibStoxDeployNetworks.ROBINHOOD);
        _assertFleetPasses(LibTokenInvariants.productionTokensRobinhood());
    }

    function testBscFleetPassesLock() external {
        _fork(LibStoxDeployNetworks.BSC);
        _assertFleetPasses(LibTokenInvariants.productionTokensBsc());
    }

    function testBaseLockRefusals() external {
        _fork(LibRainDeploy.BASE);
        _assertRefusals(LibTokenInvariants.productionTokensBase()[0]);
    }

    function testEthereumLockRefusals() external {
        _fork(LibStoxDeployNetworks.ETHEREUM);
        _assertRefusals(LibTokenInvariants.productionTokensEthereum()[0]);
    }

    function testHyperEvmLockRefusals() external {
        _fork(LibStoxDeployNetworks.HYPEREVM);
        _assertRefusals(LibTokenInvariants.productionTokensHyperEvm()[0]);
    }

    function testRobinhoodLockRefusals() external {
        _fork(LibStoxDeployNetworks.ROBINHOOD);
        _assertRefusals(LibTokenInvariants.productionTokensRobinhood()[0]);
    }

    function testBscLockRefusals() external {
        _fork(LibStoxDeployNetworks.BSC);
        _assertRefusals(LibTokenInvariants.productionTokensBsc()[0]);
    }

    function testUnsupportedChainReverts(uint64 chainId) external {
        vm.assume(chainId != LibSafeInvariants.BASE_CHAIN_ID);
        vm.assume(chainId != LibSafeInvariants.ETHEREUM_CHAIN_ID);
        vm.assume(chainId != LibSafeInvariants.HYPEREVM_CHAIN_ID);
        vm.assume(chainId != LibSafeInvariants.ROBINHOOD_CHAIN_ID);
        vm.assume(chainId != LibSafeInvariants.BSC_CHAIN_ID);
        harness = new LibVaultLogicLockHarness();
        vm.chainId(chainId);
        vm.expectRevert(abi.encodeWithSelector(UnsupportedChainForProdBeacons.selector, uint256(chainId)));
        harness.checkToken(address(this), VAULT_IMPL, RECEIPT_IMPL);
        vm.expectRevert(abi.encodeWithSelector(UnsupportedChainForProdBeacons.selector, uint256(chainId)));
        harness.prodBeaconsServe(VAULT_IMPL, RECEIPT_IMPL);
    }
}
