// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {LibProdDeployCurrent} from "../generated/LibProdDeployCurrent.sol";
import {LibStoxConfig} from "../lib/LibStoxConfig.sol";

/// @title StoxReceiptVaultBeacon
/// @notice An UpgradeableBeacon with a hardcoded implementation and its owner
/// read from `ConfigRegistry`, enabling deterministic deployment via the Zoltu
/// factory. The owner must never call `renounceOwnership`.
contract StoxReceiptVaultBeacon is
    UpgradeableBeacon(LibProdDeployCurrent.STOX_RECEIPT_VAULT, LibStoxConfig.beaconInitialOwner())
{}
