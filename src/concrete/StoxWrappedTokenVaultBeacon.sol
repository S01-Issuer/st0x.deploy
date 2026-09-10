// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {UpgradeableBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/UpgradeableBeacon.sol";
import {LibProdDeployCurrent} from "../generated/LibProdDeployCurrent.sol";
import {LibSafeInvariants} from "../lib/LibSafeInvariants.sol";

/// @title StoxWrappedTokenVaultBeacon
/// @notice An UpgradeableBeacon with a hardcoded implementation and an owner
/// resolved from the active chain id, enabling deterministic deployment via
/// the Zoltu factory.
/// @dev Constructor passes `LibProdDeployCurrent.STOX_WRAPPED_TOKEN_VAULT` as the
/// beacon implementation and the chain's ST0x token-owner Safe
/// (`LibSafeInvariants.safeForChainId(block.chainid)`) as the initial owner,
/// so the creation code is identical on every chain while each chain's beacon
/// comes up owned by that chain's Safe. Deploying on a chain without a pinned
/// Safe reverts. The owner can upgrade the implementation via `upgradeTo` or
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
    UpgradeableBeacon(LibProdDeployCurrent.STOX_WRAPPED_TOKEN_VAULT, LibSafeInvariants.safeForChainId(block.chainid))
{}
