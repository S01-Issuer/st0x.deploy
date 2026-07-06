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
/// `LibRainDeploy.deployToNetworks` is idempotent per network (an
/// already-deployed contract is skipped, its codehash still verified), so
/// re-running a suite after adding a network here is a no-op on the networks
/// that already carry the artifact and a fresh Zoltu deploy on the ones that
/// don't. That per-network idempotence is what keeps every chain in this list
/// bytecode-identical by construction: one suite run covers all of them.
library LibStoxDeployNetworks {
    /// @notice Ethereum mainnet network name. Matches the `[rpc_endpoints]`
    /// alias in `foundry.toml` (resolved from `ETHEREUM_RPC_URL`), the same
    /// pattern as every `LibRainDeploy` network constant.
    /// @dev Declared here because `rain-deploy-0.1.4`'s `LibRainDeploy`
    /// predates Rain deployments on Ethereum mainnet and has no `ETHEREUM`
    /// constant. The Zoltu factory IS deployed on Ethereum mainnet at the
    /// canonical `LibRainDeploy.ZOLTU_FACTORY` address (verified 2026-07-06,
    /// RAI-1211), so deterministic deploys work unchanged. When a future
    /// rain-deploy release ships its own `ETHEREUM` constant this one should
    /// be replaced with a re-export.
    string internal constant ETHEREUM = "ethereum";

    /// @notice The networks each suite in `script/Deploy.sol` is broadcast to.
    /// @return networks The list of network names (Base + Ethereum mainnet).
    function supportedNetworks() internal pure returns (string[] memory networks) {
        networks = new string[](2);
        networks[0] = LibRainDeploy.BASE;
        networks[1] = ETHEREUM;
    }
}
