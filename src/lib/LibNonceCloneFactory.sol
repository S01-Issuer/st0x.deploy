// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title LibNonceCloneFactory
/// @notice Pins for the nonce-based `CloneFactory` (rain-factory 0.1.1) that
/// every live V4 authoriser clone was deployed through. rain-factory 0.1.5's
/// `LibCloneFactoryDeploy` pins the deterministic-only factory, which exposes
/// no `clone(address,bytes)` — the clone-deploy script must keep targeting the
/// nonce-based factory these pins describe.
library LibNonceCloneFactory {
    /// The address of the nonce-based `CloneFactory` when deployed with the
    /// rain standard zoltu deployer.
    address constant CLONE_FACTORY_DEPLOYED_ADDRESS = address(0x444acC29d63fa643E8adCC35FD9aa6DE111dCb39);

    /// The code hash of the nonce-based `CloneFactory` when deployed with the
    /// rain standard zoltu deployer. This can be used to verify that the
    /// deployed contract has the expected bytecode, which provides stronger
    /// guarantees than just checking the address.
    bytes32 constant CLONE_FACTORY_DEPLOYED_CODEHASH =
        bytes32(0xf21b813c7075a1621285df3a8369d0652c31ea80cb807be1aaadafeecd134475);
}
