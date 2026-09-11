// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    OffchainAssetReceiptVaultBeaconSetDeployer,
    OffchainAssetReceiptVaultBeaconSetDeployerConfig
} from "rain-vats-0.1.6/src/concrete/deploy/OffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {LibProdDeployCurrent} from "../../generated/LibProdDeployCurrent.sol";
import {LibSafeInvariants} from "../../lib/LibSafeInvariants.sol";

/// @title StoxOffchainAssetReceiptVaultBeaconSetDeployer
/// @notice Inherits OffchainAssetReceiptVaultBeaconSetDeployer with a
/// parameterless constructor that hardcodes the implementations from
/// LibProdDeployCurrent and resolves the beacons' initial owner from the
/// active chain id: the chain's ST0x token-owner Safe
/// (`LibSafeInvariants.safeForChainId`). No dynamic input, so the contract is
/// Zoltu-deployable, and the creation code is identical on every chain while
/// each chain's beacons come up owned by that chain's Safe — no EOA ever holds
/// beacon upgrade authority, and no ownership migration follows the deploy.
/// Deploying on a chain without a pinned Safe reverts in the constructor.
contract StoxOffchainAssetReceiptVaultBeaconSetDeployer is
    OffchainAssetReceiptVaultBeaconSetDeployer(OffchainAssetReceiptVaultBeaconSetDeployerConfig({
            initialOwner: LibSafeInvariants.safeForChainId(block.chainid),
            initialReceiptImplementation: LibProdDeployCurrent.STOX_RECEIPT,
            initialOffchainAssetReceiptVaultImplementation: LibProdDeployCurrent.STOX_RECEIPT_VAULT
        }))
{}
