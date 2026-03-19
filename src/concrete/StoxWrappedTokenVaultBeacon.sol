// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {LibProdDeployV2} from "../lib/LibProdDeployV2.sol";

/// @title StoxWrappedTokenVaultBeacon
/// @notice An UpgradeableBeacon with hardcoded owner and implementation,
/// enabling deterministic deployment via the Zoltu factory.
contract StoxWrappedTokenVaultBeacon is
    UpgradeableBeacon(LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT, LibProdDeployV2.BEACON_INITIAL_OWNER)
{}
