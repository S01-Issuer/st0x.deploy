// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

/// @title LibStoxDeployNetworks
/// @notice Single source of truth for the networks the ST0x production deploy
/// broadcasts to. `script/Deploy.sol` reads this instead of hardcoding the list
/// inline, so the supported-network set lives in one place. ST0x deploys to
/// Base and Ethereum mainnet.
///
/// `LibRainDeploy.deployToNetworks` is idempotent per network — an
/// already-deployed contract is skipped and its codehash re-verified — so a
/// single suite run keeps every network in this list bytecode-identical by
/// construction.
library LibStoxDeployNetworks {
    /// @notice Ethereum mainnet network name, matching the `[rpc_endpoints]`
    /// alias in `foundry.toml` (resolved from `ETHEREUM_RPC_URL`), the same
    /// pattern as every `LibRainDeploy` network constant.
    /// @dev Declared here because `rain-deploy-0.1.4`'s `LibRainDeploy` has no
    /// `ETHEREUM` constant. The Zoltu factory is deployed on Ethereum mainnet at
    /// the canonical `LibRainDeploy.ZOLTU_FACTORY` address, so deterministic
    /// deploys work unchanged.
    string internal constant ETHEREUM = "ethereum";

    /// @notice The networks each suite in `script/Deploy.sol` is broadcast to.
    /// @return networks The list of network names (Base + Ethereum mainnet).
    function supportedNetworks() internal pure returns (string[] memory networks) {
        networks = new string[](2);
        networks[0] = LibRainDeploy.BASE;
        networks[1] = ETHEREUM;
    }
}
