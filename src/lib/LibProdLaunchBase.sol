// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title LibProdLaunchBase
/// @notice The Base contracts and signer of the token launch ported from
/// sft-ops that no other `LibProd*` library pins. The unified deployer, the
/// authoriser implementation, the shared authoriser and the owner Safe are
/// referenced where they already live.
library LibProdLaunchBase {
    /// @notice The deployer EOA every sft-ops CD launch signed with: the
    /// `deployedBy` of every ledger row that records one.
    address internal constant LAUNCH_SIGNER = 0x21Cc8a5fe957a167cB92F12F4E658d755b00Be53;

    /// @notice The MetaBoard sft-ops publishes token metadata to.
    /// https://basescan.org/address/0x59401C9302E79Eb8AC6aea659B8B3ae475715e86
    address internal constant METABOARD = 0x59401C9302E79Eb8AC6aea659B8B3ae475715e86;
    bytes32 internal constant METABOARD_CODEHASH = 0xcf3a2c496137d80703b0a96695bd5a4b48859a3735cdafa83364392d772a95da;

    /// @notice The clone factory sft-ops clones each token's throwaway
    /// certification authoriser from.
    /// https://basescan.org/address/0x5e9e22154D71f9Fd4b5FD1eE36852A4c9FcDcC9E
    address internal constant CLONE_FACTORY = 0x5e9e22154D71f9Fd4b5FD1eE36852A4c9FcDcC9E;
    bytes32 internal constant CLONE_FACTORY_CODEHASH =
        0x62a5565fee42952b343be568e4a9754eb6403d4cfc9ce46de71efc0d4c894e7a;
}
