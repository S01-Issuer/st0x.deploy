// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibProdDeployV2} from "../../../../src/lib/LibProdDeployV2.sol";
import {LibProdDeployV2BaseOverrides} from "../../../../src/lib/LibProdDeployV2BaseOverrides.sol";
import {LibSafeInvariants} from "../../../../src/lib/LibSafeInvariants.sol";
import {LibInvariants} from "../../../../src/lib/LibInvariants.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {
    IOffchainAssetReceiptVaultBeaconSetDeployerV1
} from "rain-vats-0.2.18/src/interface/deprecated/IOffchainAssetReceiptVaultBeaconSetDeployerV1.sol";

/// @title StoxProdV2Test
/// @notice Fork tests verifying all V2 Zoltu deployments exist on all
/// supported networks with expected codehashes. These tests will fail until
/// V2 is deployed on-chain.
contract StoxProdV2Test is Test {
    struct V2Contract {
        string name;
        address account;
        bytes32 codehash;
    }

    function v2Contracts() internal pure returns (V2Contract[9] memory) {
        return [
            V2Contract("StoxReceipt", LibProdDeployV2.STOX_RECEIPT, LibProdDeployV2.STOX_RECEIPT_CODEHASH),
            V2Contract(
                "StoxReceiptVault", LibProdDeployV2.STOX_RECEIPT_VAULT, LibProdDeployV2.STOX_RECEIPT_VAULT_CODEHASH
            ),
            V2Contract(
                "StoxWrappedTokenVault",
                LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT,
                LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_CODEHASH
            ),
            V2Contract(
                "StoxWrappedTokenVaultBeacon",
                LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON,
                LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_CODEHASH
            ),
            V2Contract(
                "StoxWrappedTokenVaultBeaconSetDeployer",
                LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER,
                LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CODEHASH
            ),
            V2Contract(
                "StoxOffchainAssetReceiptVaultBeaconSetDeployer",
                LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER,
                LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CODEHASH
            ),
            V2Contract(
                "StoxUnifiedDeployer",
                LibProdDeployV2.STOX_UNIFIED_DEPLOYER,
                LibProdDeployV2.STOX_UNIFIED_DEPLOYER_CODEHASH
            ),
            V2Contract(
                "StoxOffchainAssetReceiptVaultAuthorizerV1",
                LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1,
                LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CODEHASH
            ),
            V2Contract(
                "StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1",
                LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1,
                LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_CODEHASH
            )
        ];
    }

    function checkAllV2OnChain(
        string memory network,
        address expectedReceiptBeaconImpl,
        address expectedReceiptBeaconOwner,
        address expectedVaultBeaconImpl,
        address expectedVaultBeaconOwner
    ) internal {
        vm.createSelectFork(network);
        V2Contract[9] memory contracts = v2Contracts();
        for (uint256 i = 0; i < contracts.length; i++) {
            string memory label = string.concat(network, ": V2 ", contracts[i].name);
            assertTrue(contracts[i].account.code.length > 0, string.concat(label, " not deployed"));
            assertEq(contracts[i].account.codehash, contracts[i].codehash, string.concat(label, " codehash"));
        }

        assertEq(
            IBeacon(LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON).implementation(),
            LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT,
            string.concat(network, ": V2 beacon implementation mismatch")
        );
        assertEq(
            Ownable(LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON).owner(),
            LibProdDeployV2.BEACON_INITIAL_OWNER,
            string.concat(network, ": V2 beacon owner mismatch")
        );

        // OARV deployer: on-chain V2 has V1 ABI (I_RECEIPT_BEACON selectors).
        IOffchainAssetReceiptVaultBeaconSetDeployerV1 oarvDeployer = IOffchainAssetReceiptVaultBeaconSetDeployerV1(
            LibProdDeployV2.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER
        );

        IBeacon receiptBeacon = oarvDeployer.I_RECEIPT_BEACON();
        assertEq(
            receiptBeacon.implementation(),
            expectedReceiptBeaconImpl,
            string.concat(network, ": V2 receipt beacon implementation mismatch")
        );
        assertEq(
            Ownable(address(receiptBeacon)).owner(),
            expectedReceiptBeaconOwner,
            string.concat(network, ": V2 receipt beacon owner mismatch")
        );

        IBeacon vaultBeacon = oarvDeployer.I_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON();
        assertEq(
            vaultBeacon.implementation(),
            expectedVaultBeaconImpl,
            string.concat(network, ": V2 vault beacon implementation mismatch")
        );
        assertEq(
            Ownable(address(vaultBeacon)).owner(),
            expectedVaultBeaconOwner,
            string.concat(network, ": V2 vault beacon owner mismatch")
        );
    }

    /// All V2 contracts MUST be deployed on every non-Base V2 network, with
    /// the beacons in their deployed state.
    function testProdDeployV2OffBase() external {
        string[4] memory networks =
            [LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE_SEPOLIA, LibRainDeploy.FLARE, LibRainDeploy.POLYGON];
        for (uint256 i = 0; i < networks.length; i++) {
            checkAllV2OnChain(
                networks[i],
                LibProdDeployV2.STOX_RECEIPT,
                LibProdDeployV2.BEACON_INITIAL_OWNER,
                LibProdDeployV2.STOX_RECEIPT_VAULT,
                LibProdDeployV2.BEACON_INITIAL_OWNER
            );
        }
    }

    /// All V2 contracts MUST be deployed on Base.
    /// OARV deployer beacons on Base were corrupted post-deployment — see
    /// LibProdDeployV2BaseOverrides for details.
    /// Also pins the ST0x token-owner Safe's invariants against the live
    /// Base head fork — Base is the only network where the Safe is deployed,
    /// so this is the unique site where the Safe-state pins are exercised
    /// against on-chain reality.
    function testProdDeployBaseV2() external {
        checkAllV2OnChain(
            LibRainDeploy.BASE,
            LibProdDeployV2BaseOverrides.RECEIPT_BEACON_IMPLEMENTATION,
            LibProdDeployV2BaseOverrides.RECEIPT_BEACON_OWNER,
            LibProdDeployV2BaseOverrides.VAULT_BEACON_IMPLEMENTATION,
            LibProdDeployV2BaseOverrides.VAULT_BEACON_OWNER
        );
        LibInvariants.assertAll(Safe(payable(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE)));
    }
}
