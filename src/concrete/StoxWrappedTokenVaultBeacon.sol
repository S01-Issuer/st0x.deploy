// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {LibProdDeployCurrent} from "../generated/LibProdDeployCurrent.sol";
import {LibTimelockInvariants} from "../lib/LibTimelockInvariants.sol";

/// @title StoxWrappedTokenVaultBeacon
/// @notice An UpgradeableBeacon with a hardcoded implementation and an owner
/// resolved from the active chain id, enabling deterministic deployment via
/// the Zoltu factory.
/// @dev Constructor passes `LibProdDeployCurrent.STOX_WRAPPED_TOKEN_VAULT` as the
/// beacon implementation and the chain's governance timelock
/// (`LibTimelockInvariants.timelockForChainId(block.chainid)`) as the initial
/// owner, so the creation code is identical on every chain while each chain's
/// beacon comes up owned by that chain's timelock. Deploying on a chain without
/// a pinned timelock reverts. The owner can upgrade the implementation via
/// `upgradeTo` or transfer ownership via `transferOwnership`.
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
    UpgradeableBeacon(
        LibProdDeployCurrent.STOX_WRAPPED_TOKEN_VAULT, LibTimelockInvariants.timelockForChainId(block.chainid)
    )
{}
