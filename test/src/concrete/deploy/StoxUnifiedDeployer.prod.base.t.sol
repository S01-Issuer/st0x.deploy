// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std/Test.sol";

import {StoxUnifiedDeployer} from "../../../../src/concrete/deploy/StoxUnifiedDeployer.sol";
import {LibProdDeployV1} from "../../../../src/lib/LibProdDeployV1.sol";
import {LibTestProd} from "../../../lib/LibTestProd.sol";
import {LibTestDeploy} from "../../../lib/LibTestDeploy.sol";
import {
    IOffchainAssetReceiptVaultBeaconSetDeployerV1
} from "rain.vats/interface/IOffchainAssetReceiptVaultBeaconSetDeployerV1.sol";
import {OffchainAssetReceiptVaultConfigV2} from "rain.vats/concrete/vault/OffchainAssetReceiptVault.sol";
import {ReceiptVaultConfigV2} from "rain.vats/abstract/ReceiptVault.sol";
import {
    StoxWrappedTokenVaultBeaconSetDeployer
} from "../../../../src/concrete/deploy/StoxWrappedTokenVaultBeaconSetDeployer.sol";
import {IBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {MockERC20} from "../../../concrete/MockERC20.sol";

contract StoxProdBaseTest is Test {
    /// Verify all deployed contract addresses, codehashes on Base fork.
    function checkAllV1OnChain() internal view {
        // OffchainAssetReceiptVaultBeaconSetDeployer
        assertTrue(
            LibProdDeployV1.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER.code.length > 0,
            "OffchainAssetReceiptVaultBeaconSetDeployer not deployed"
        );
        assertEq(
            LibProdDeployV1.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER.codehash,
            LibProdDeployV1.PROD_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_BASE_CODEHASH_V1
        );

        // StoxWrappedTokenVaultBeaconSetDeployer
        assertTrue(
            LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER.code.length > 0,
            "StoxWrappedTokenVaultBeaconSetDeployer not deployed"
        );
        assertEq(
            LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER.codehash,
            LibProdDeployV1.PROD_STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_BASE_CODEHASH_V1
        );

        // StoxWrappedTokenVault implementation (via beacon)
        // The on-chain deployer uses the old I_STOX_WRAPPED_TOKEN_VAULT_BEACON
        // selector from before the rename to iStoxWrappedTokenVaultBeacon.
        (bool ok, bytes memory beaconData) = LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER
            .staticcall(abi.encodeWithSignature("I_STOX_WRAPPED_TOKEN_VAULT_BEACON()"));
        assertTrue(ok, "beacon call failed");
        address wrappedImpl = IBeacon(abi.decode(beaconData, (address))).implementation();
        assertEq(
            wrappedImpl,
            LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION,
            "StoxWrappedTokenVault implementation address mismatch"
        );
        assertTrue(wrappedImpl.code.length > 0, "StoxWrappedTokenVault implementation not deployed");
        assertEq(wrappedImpl.codehash, LibProdDeployV1.PROD_STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1);

        // Wrapped vault beacon owner must match BEACON_INITIAL_OWNER.
        address wrappedBeacon = abi.decode(beaconData, (address));
        assertEq(
            Ownable(wrappedBeacon).owner(), LibProdDeployV1.BEACON_INITIAL_OWNER, "Wrapped vault beacon owner mismatch"
        );

        // StoxUnifiedDeployer
        assertTrue(LibProdDeployV1.STOX_UNIFIED_DEPLOYER.code.length > 0, "StoxUnifiedDeployer not deployed");
        assertEq(
            LibProdDeployV1.STOX_UNIFIED_DEPLOYER.codehash, LibProdDeployV1.PROD_STOX_UNIFIED_DEPLOYER_BASE_CODEHASH_V1
        );

        // StoxReceipt implementation (via beacon)
        IOffchainAssetReceiptVaultBeaconSetDeployerV1 oarvDeployer = IOffchainAssetReceiptVaultBeaconSetDeployerV1(
            LibProdDeployV1.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER
        );
        address receiptImpl = oarvDeployer.I_RECEIPT_BEACON().implementation();
        assertEq(
            receiptImpl, LibProdDeployV1.STOX_RECEIPT_IMPLEMENTATION, "StoxReceipt implementation address mismatch"
        );
        assertTrue(receiptImpl.code.length > 0, "StoxReceipt implementation not deployed");
        assertEq(receiptImpl.codehash, LibProdDeployV1.PROD_STOX_RECEIPT_IMPLEMENTATION_BASE_CODEHASH_V1);

        // StoxReceiptVault implementation (via beacon)
        address vaultImpl = oarvDeployer.I_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON().implementation();
        assertEq(
            vaultImpl,
            LibProdDeployV1.STOX_RECEIPT_VAULT_IMPLEMENTATION,
            "StoxReceiptVault implementation address mismatch"
        );
        assertTrue(vaultImpl.code.length > 0, "StoxReceiptVault implementation not deployed");
        assertEq(vaultImpl.codehash, LibProdDeployV1.PROD_STOX_RECEIPT_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1);

        // OARV receipt beacon owner must match BEACON_INITIAL_OWNER.
        assertEq(
            Ownable(address(oarvDeployer.I_RECEIPT_BEACON())).owner(),
            LibProdDeployV1.BEACON_INITIAL_OWNER,
            "Receipt beacon owner mismatch"
        );

        // OARV vault beacon owner must match BEACON_INITIAL_OWNER.
        assertEq(
            Ownable(address(oarvDeployer.I_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON())).owner(),
            LibProdDeployV1.BEACON_INITIAL_OWNER,
            "Receipt vault beacon owner mismatch"
        );
    }

    /// Both StoxReceipt and StoxReceiptVault diverged from V1 when rebase
    /// logic was added, so no contract's current compiled bytecode matches
    /// its V1 constant. The V1 bytecodes are frozen in LibProdDeployV1 as
    /// an audit trail only. Contracts that changed between V1 and V2
    /// (StoxWrappedTokenVault, StoxWrappedTokenVaultBeaconSetDeployer,
    /// StoxUnifiedDeployer) are verified in the V2 tests instead.

    /// All contracts MUST be deployed on Base.
    function testProdDeployBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkAllV1OnChain();
    }
}
