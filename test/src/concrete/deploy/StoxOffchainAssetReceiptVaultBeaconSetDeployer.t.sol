// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {
    StoxOffchainAssetReceiptVaultBeaconSetDeployer
} from "../../../../src/concrete/deploy/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {LibProdDeployCurrent} from "../../../../src/generated/LibProdDeployCurrent.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {
    LibTimelockInvariants,
    UnsupportedChainForGovernanceTimelock
} from "../../../../src/lib/LibTimelockInvariants.sol";

contract StoxOffchainAssetReceiptVaultBeaconSetDeployerTest is Test {
    function setUp() public {
        vm.etch(LibProdDeployCurrent.STOX_RECEIPT, hex"00");
        vm.etch(LibProdDeployCurrent.STOX_RECEIPT_VAULT, hex"00");
    }

    function assertBeaconsOwnedBy(uint256 chainId, address timelock) internal {
        vm.chainId(chainId);
        StoxOffchainAssetReceiptVaultBeaconSetDeployer deployer = new StoxOffchainAssetReceiptVaultBeaconSetDeployer();
        assertEq(Ownable(address(deployer.iReceiptBeacon())).owner(), timelock, "receipt beacon owner");
        assertEq(Ownable(address(deployer.iOffchainAssetReceiptVaultBeacon())).owner(), timelock, "vault beacon owner");
    }

    function testBeaconsOwnedByEachChainTimelock() external {
        assertBeaconsOwnedBy(LibSafeInvariants.BASE_CHAIN_ID, LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK);
        assertBeaconsOwnedBy(
            LibSafeInvariants.ETHEREUM_CHAIN_ID, LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_ETHEREUM
        );
        assertBeaconsOwnedBy(
            LibSafeInvariants.HYPEREVM_CHAIN_ID, LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_HYPEREVM
        );
        assertBeaconsOwnedBy(
            LibSafeInvariants.ROBINHOOD_CHAIN_ID, LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_ROBINHOOD
        );
        assertBeaconsOwnedBy(LibSafeInvariants.BSC_CHAIN_ID, LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_BSC);
    }

    function testRefusesAChainWithoutATimelockPin(uint64 chainId) external {
        vm.assume(
            chainId != LibSafeInvariants.BASE_CHAIN_ID && chainId != LibSafeInvariants.ETHEREUM_CHAIN_ID
                && chainId != LibSafeInvariants.HYPEREVM_CHAIN_ID && chainId != LibSafeInvariants.ROBINHOOD_CHAIN_ID
                && chainId != LibSafeInvariants.BSC_CHAIN_ID
        );
        vm.chainId(chainId);
        vm.expectRevert(abi.encodeWithSelector(UnsupportedChainForGovernanceTimelock.selector, uint256(chainId)));
        new StoxOffchainAssetReceiptVaultBeaconSetDeployer();
    }
}
