// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {LibProdTokensBase} from "../../../src/lib/LibProdTokensBase.sol";
import {LibProdDeployV1} from "../../../src/lib/LibProdDeployV1.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IReceiptVaultV3} from "ethgild/interface/IReceiptVaultV3.sol";
import {
    OffchainAssetReceiptVaultBeaconSetDeployer
} from "ethgild/concrete/deploy/OffchainAssetReceiptVaultBeaconSetDeployer.sol";

/// @title LibProdTokensBaseTest
/// @notice Fork tests verifying production token instances on Base.
contract LibProdTokensBaseTest is Test {
    /// @dev Block at which these tokens are known to exist. Must be pinned
    /// so the test is reproducible even if on-chain state changes later.
    uint256 constant PROD_TOKENS_BLOCK_NUMBER_BASE = 44601000;

    function createFork() internal {
        vm.createSelectFork(vm.envString("RPC_URL_BASE_FORK"), PROD_TOKENS_BLOCK_NUMBER_BASE);
    }

    /// tMSTR receipt vault is a beacon proxy behind the V1 deployer's vault
    /// beacon, owned by rainlang.eth.
    function testMstrReceiptVaultOnBase() external {
        createFork();

        // Receipt vault exists and has expected identity.
        assertTrue(LibProdTokensBase.MSTR_RECEIPT_VAULT.code.length > 0, "tMSTR receipt vault not deployed");
        assertEq(IERC20Metadata(LibProdTokensBase.MSTR_RECEIPT_VAULT).symbol(), "tMSTR");

        // Receipt vault's beacon is the V1 deployer's vault beacon, owned by
        // rainlang.eth.
        OffchainAssetReceiptVaultBeaconSetDeployer oarvDeployer = OffchainAssetReceiptVaultBeaconSetDeployer(
            LibProdDeployV1.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER
        );
        IBeacon vaultBeacon = oarvDeployer.I_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON();
        assertEq(
            Ownable(address(vaultBeacon)).owner(),
            LibProdDeployV1.BEACON_INITIAL_OWNER,
            "tMSTR vault beacon owner mismatch"
        );

        // Receipt contract exists and is referenced by the vault.
        address receipt = address(IReceiptVaultV3(payable(LibProdTokensBase.MSTR_RECEIPT_VAULT)).receipt());
        assertEq(receipt, LibProdTokensBase.MSTR_RECEIPT, "tMSTR receipt address mismatch");
        assertTrue(LibProdTokensBase.MSTR_RECEIPT.code.length > 0, "tMSTR receipt not deployed");

        // Receipt's beacon is the V1 deployer's receipt beacon, owned by
        // rainlang.eth.
        IBeacon receiptBeacon = oarvDeployer.I_RECEIPT_BEACON();
        assertEq(
            Ownable(address(receiptBeacon)).owner(),
            LibProdDeployV1.BEACON_INITIAL_OWNER,
            "tMSTR receipt beacon owner mismatch"
        );
    }

    /// wtMSTR wrapped vault wraps the tMSTR receipt vault and is a beacon
    /// proxy behind the V1 deployer's wrapped vault beacon.
    function testMstrWrappedTokenVaultOnBase() external {
        createFork();

        // Wrapped vault exists and has expected identity.
        assertTrue(LibProdTokensBase.MSTR_WRAPPED_TOKEN_VAULT.code.length > 0, "wtMSTR wrapped vault not deployed");
        assertEq(IERC20Metadata(LibProdTokensBase.MSTR_WRAPPED_TOKEN_VAULT).symbol(), "wtMSTR");

        // Wrapped vault's underlying asset is the tMSTR receipt vault.
        assertEq(
            IERC4626(LibProdTokensBase.MSTR_WRAPPED_TOKEN_VAULT).asset(),
            LibProdTokensBase.MSTR_RECEIPT_VAULT,
            "wtMSTR asset mismatch"
        );

        // Wrapped vault beacon is owned by rainlang.eth.
        (bool ok, bytes memory beaconData) = LibProdDeployV1.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER.staticcall(
            abi.encodeWithSignature("I_STOX_WRAPPED_TOKEN_VAULT_BEACON()")
        );
        assertTrue(ok, "wrapped beacon call failed");
        address wrappedBeacon = abi.decode(beaconData, (address));
        assertEq(
            Ownable(wrappedBeacon).owner(),
            LibProdDeployV1.BEACON_INITIAL_OWNER,
            "wtMSTR beacon owner mismatch"
        );
    }
}
