// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {LibProdDeployV3} from "../lib/LibProdDeployV3.sol";

/// @title StoxWrappedTokenVaultBeacon
/// @notice An UpgradeableBeacon with hardcoded owner and implementation,
/// enabling deterministic deployment via the Zoltu factory.
/// @dev Constructor passes `LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT` as the
/// beacon implementation and `LibProdDeployV3.BEACON_INITIAL_OWNER` as the
/// initial owner. The owner can upgrade the implementation via `upgradeTo` or
/// transfer ownership via `transferOwnership`.
///
/// WARNING: The inherited `renounceOwnership()` from OpenZeppelin `Ownable`
/// permanently sets the owner to `address(0)`, which would irreversibly
/// disable `upgradeTo`. The owner must never call `renounceOwnership`.
///
/// `StoxWrappedTokenVaultBeaconSetDeployer` creates `BeaconProxy` instances
/// that delegate to this beacon's `implementation()`.
///
/// The implementation contract must already be deployed at its Zoltu address
/// before this beacon is deployed, because the `UpgradeableBeacon` constructor
/// validates that the implementation address has code.
contract StoxWrappedTokenVaultBeacon is
    UpgradeableBeacon(LibProdDeployV3.STOX_WRAPPED_TOKEN_VAULT, LibProdDeployV3.BEACON_INITIAL_OWNER)
{}
