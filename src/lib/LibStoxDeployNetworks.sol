// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title LibStoxDeployNetworks
/// @notice The ST0x-specific deploy network-name constants that
/// `rain-deploy`'s `LibRainDeploy` does not provide. Each matches its
/// `[rpc_endpoints]` alias in `foundry.toml`, the same convention as every
/// `LibRainDeploy` network constant. Consumed by the audited deploy script
/// `script/DeployProdV4_0_1_1.sol` and the cross-chain fork tests.
library LibStoxDeployNetworks {
    /// @notice Ethereum mainnet network name, matching the `[rpc_endpoints]`
    /// alias in `foundry.toml` (resolved from `ETHEREUM_RPC_URL`).
    /// @dev Declared here because `rain-deploy-0.1.4`'s `LibRainDeploy` has no
    /// `ETHEREUM` constant. The Zoltu factory is deployed on Ethereum mainnet at
    /// the canonical `LibRainDeploy.ZOLTU_FACTORY` address, so deterministic
    /// deploys work unchanged.
    string internal constant ETHEREUM = "ethereum";

    /// @notice HyperEVM mainnet network name, matching the `[rpc_endpoints]`
    /// alias in `foundry.toml` (resolved from `HYPEREVM_RPC_URL`).
    /// @dev The Zoltu factory is deployed on HyperEVM at the canonical
    /// `LibRainDeploy.ZOLTU_FACTORY` address, so deterministic deploys work
    /// unchanged.
    string internal constant HYPEREVM = "hyperevm";
}
