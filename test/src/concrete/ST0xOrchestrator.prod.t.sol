// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin-contracts-5.7.0/proxy/beacon/BeaconProxy.sol";
import {LibRainDeploy} from "rain-deploy-0.1.18/src/lib/LibRainDeploy.sol";

import {ST0xOrchestrator} from "../../../src/concrete/ST0xOrchestrator.sol";
import {StoxReceipt} from "../../../src/concrete/StoxReceipt.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {IST0xOrchestratorV1, MintAuthV1} from "../../../src/interface/IST0xOrchestratorV1.sol";
import {LibBeaconInvariants, IOwnable} from "../../../src/lib/LibBeaconInvariants.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibTokenInvariants, TokenInstance} from "../../../src/lib/LibTokenInvariants.sol";
import {LibProdDeployCurrent} from "../../../src/generated/LibProdDeployCurrent.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";

/// @dev Zero-amount mint and burn run every modifier before the body, so the
/// revert names the lock while it refuses and `ZeroAmount` once it passes.
contract ST0xOrchestratorProdTest is Test {
    function _newOrchestrator() internal returns (ST0xOrchestrator) {
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(new ST0xOrchestrator()), address(this));
        ST0xOrchestrator orchestrator = ST0xOrchestrator(
            payable(address(
                    new BeaconProxy(address(beacon), abi.encodeCall(ST0xOrchestrator.initialize, (address(this))))
                ))
        );
        orchestrator.grantRole(orchestrator.MINT_ROLE(), address(this));
        orchestrator.grantRole(orchestrator.BURN_ROLE(), address(this));
        return orchestrator;
    }

    function _assertEveryTokenReverts(ST0xOrchestrator orchestrator, TokenInstance[] memory tokens, bytes memory err)
        internal
    {
        assertTrue(tokens.length > 0, "no production tokens");
        for (uint256 i = 0; i < tokens.length; i++) {
            vm.expectRevert(err);
            orchestrator.mint(
                tokens[i].receiptVault, address(this), 0, MintAuthV1({nonce: bytes32(i), signature: ""}), ""
            );
            vm.expectRevert(err);
            orchestrator.burn(tokens[i].receiptVault, 0, "");
        }
    }

    function _upgradeBeacon(address beacon, address impl) internal {
        vm.prank(IOwnable(beacon).owner());
        UpgradeableBeacon(beacon).upgradeTo(impl);
    }

    function _assertInertUntilLockstepUpgrade(string memory network, TokenInstance[] memory tokens) internal {
        vm.createSelectFork(network);
        ST0xOrchestrator orchestrator = _newOrchestrator();

        assertFalse(orchestrator.vaultLogicIsExpected(), "inert today");
        _assertEveryTokenReverts(
            orchestrator,
            tokens,
            abi.encodeWithSelector(
                IST0xOrchestratorV1.VaultLogicMismatch.selector,
                LibProdDeployCurrent.STOX_RECEIPT_VAULT,
                LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30
            )
        );

        assertEq(
            LibRainDeploy.etchAndDeployZoltu(vm, type(StoxReceiptVault).creationCode),
            LibProdDeployCurrent.STOX_RECEIPT_VAULT,
            "candidate vault"
        );
        assertEq(
            LibRainDeploy.etchAndDeployZoltu(vm, type(StoxReceipt).creationCode),
            LibProdDeployCurrent.STOX_RECEIPT,
            "candidate receipt"
        );
        address[4] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(block.chainid);
        _upgradeBeacon(beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX], LibProdDeployCurrent.STOX_RECEIPT_VAULT);
        _upgradeBeacon(beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX], LibProdDeployCurrent.STOX_RECEIPT);

        assertTrue(orchestrator.vaultLogicIsExpected(), "live after lockstep upgrade");
        _assertEveryTokenReverts(orchestrator, tokens, abi.encodeWithSelector(IST0xOrchestratorV1.ZeroAmount.selector));
    }

    function testBaseInertUntilLockstepUpgrade() external {
        _assertInertUntilLockstepUpgrade(LibRainDeploy.BASE, LibTokenInvariants.productionTokensBase());
    }

    function testEthereumInertUntilLockstepUpgrade() external {
        _assertInertUntilLockstepUpgrade(LibStoxDeployNetworks.ETHEREUM, LibTokenInvariants.productionTokensEthereum());
    }

    function testHyperEvmInertUntilLockstepUpgrade() external {
        _assertInertUntilLockstepUpgrade(LibStoxDeployNetworks.HYPEREVM, LibTokenInvariants.productionTokensHyperEvm());
    }

    function testRobinhoodInertUntilLockstepUpgrade() external {
        _assertInertUntilLockstepUpgrade(
            LibStoxDeployNetworks.ROBINHOOD, LibTokenInvariants.productionTokensRobinhood()
        );
    }

    function testBscInertUntilLockstepUpgrade() external {
        _assertInertUntilLockstepUpgrade(LibStoxDeployNetworks.BSC, LibTokenInvariants.productionTokensBsc());
    }
}
