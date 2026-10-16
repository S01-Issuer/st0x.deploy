// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    OffchainAssetReceiptVaultBeaconSetDeployer,
    OffchainAssetReceiptVaultBeaconSetDeployerConfig
} from "rain-vats-0.2.5/src/concrete/deploy/OffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {LibProdDeployCurrent} from "../../generated/LibProdDeployCurrent.sol";
import {LibTimelockInvariants} from "../../lib/LibTimelockInvariants.sol";

/// @title StoxOffchainAssetReceiptVaultBeaconSetDeployer
/// @notice Inherits OffchainAssetReceiptVaultBeaconSetDeployer with a
/// parameterless constructor that hardcodes the implementations from
/// LibProdDeployCurrent and resolves the beacons' initial owner from the
/// active chain id: the chain's governance timelock
/// (`LibTimelockInvariants.timelockForChainId`). No dynamic input, so the
/// contract is Zoltu-deployable, and the creation code is identical on every
/// chain while each chain's beacons come up owned by that chain's timelock —
/// no EOA or Safe ever holds beacon upgrade authority, and no ownership
/// migration follows the deploy. Deploying on a chain without a pinned
/// timelock reverts in the constructor.
contract StoxOffchainAssetReceiptVaultBeaconSetDeployer is
    OffchainAssetReceiptVaultBeaconSetDeployer(OffchainAssetReceiptVaultBeaconSetDeployerConfig({
            initialOwner: LibTimelockInvariants.timelockForChainId(block.chainid),
            initialReceiptImplementation: LibProdDeployCurrent.STOX_RECEIPT,
            initialOffchainAssetReceiptVaultImplementation: LibProdDeployCurrent.STOX_RECEIPT_VAULT
        }))
{}
