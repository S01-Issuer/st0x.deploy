// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

/// @title LibStoxDeployNetworks
/// @notice The ST0x deploy network set: the name constants `rain-deploy`'s
/// `LibRainDeploy` does not provide, and the one list of networks ST0x deploys
/// to. Each name matches its `[rpc_endpoints]` alias in `foundry.toml`, the
/// same convention as every `LibRainDeploy` network constant. Consumed by the
/// audited deploy scripts `script/DeployProdV4_0_1_1.sol` and
/// `script/DeployProdV4_0_1_30.sol`, and by the cross-chain fork tests.
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

    /// @notice Every network ST0x deploys to, as `foundry.toml` rpc aliases.
    /// @dev The deploy scripts hand this whole list to
    /// `LibRainDeploy.deployToNetworks`, which forks each in turn and skips any
    /// that already has code at the expected address, so one dispatch ships a
    /// suite everywhere and a repeat dispatch is a no-op wherever it landed.
    /// @return The `foundry.toml` rpc aliases to deploy to.
    function deploymentNetworks() internal pure returns (string[] memory) {
        string[] memory networks = new string[](3);
        networks[0] = LibRainDeploy.BASE;
        networks[1] = ETHEREUM;
        networks[2] = HYPEREVM;
        return networks;
    }
}
