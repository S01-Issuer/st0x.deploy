// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {UpgradeableBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/UpgradeableBeacon.sol";
import {LibProdDeployCurrent} from "../generated/LibProdDeployCurrent.sol";

/// @title StoxWrappedTokenVaultBeacon
/// @notice An UpgradeableBeacon with hardcoded owner and implementation,
/// enabling deterministic deployment via the Zoltu factory.
/// @dev Constructor passes `LibProdDeployCurrent.STOX_WRAPPED_TOKEN_VAULT` as the
/// beacon implementation and `LibProdDeployCurrent.BEACON_INITIAL_OWNER` as the
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
    UpgradeableBeacon(LibProdDeployCurrent.STOX_WRAPPED_TOKEN_VAULT, LibProdDeployCurrent.BEACON_INITIAL_OWNER)
{}
