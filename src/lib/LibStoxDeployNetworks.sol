// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibRainDeploy} from "rain-deploy-0.1.38/src/lib/LibRainDeploy.sol";

/// @notice `LibStoxDeployNetworks.networksWithout` names a network that is not
/// a deployment network, so it would leave out nothing.
/// @param network The name.
error NotADeploymentNetwork(string network);

/// @title LibStoxDeployNetworks
/// @notice The ST0x deploy network set: the one list of networks ST0x deploys
/// to, as `rain-deploy`'s `LibRainDeploy` network names. Each name matches its
/// `[rpc_endpoints]` alias in `foundry.toml`. Consumed by the cross-chain fork
/// tests.
library LibStoxDeployNetworks {
    /// @notice Ethereum mainnet: `LibRainDeploy.ETHEREUM`.
    /// @dev The Zoltu factory is deployed on Ethereum mainnet at the canonical
    /// `LibRainDeploy.ZOLTU_FACTORY` address, so deterministic deploys work
    /// unchanged.
    string internal constant ETHEREUM = LibRainDeploy.ETHEREUM;

    /// @notice HyperEVM mainnet: `LibRainDeploy.HYPEREVM`.
    /// @dev The Zoltu factory is deployed on HyperEVM at the canonical
    /// `LibRainDeploy.ZOLTU_FACTORY` address, so deterministic deploys work
    /// unchanged.
    string internal constant HYPEREVM = LibRainDeploy.HYPEREVM;

    /// @notice Robinhood Chain mainnet (chain id 4663): `LibRainDeploy.ROBINHOOD`.
    /// @dev An Arbitrum Orbit L2 settling to Ethereum. The Zoltu factory is
    /// deployed there at the canonical `LibRainDeploy.ZOLTU_FACTORY` address
    /// with Base's exact runtime, so deterministic deploys land at the same
    /// addresses as on every other chain.
    string internal constant ROBINHOOD = LibRainDeploy.ROBINHOOD;

    /// @notice BNB Smart Chain mainnet (chain id 56): `LibRainDeploy.BSC`.
    /// @dev The Zoltu factory is deployed there at the canonical
    /// `LibRainDeploy.ZOLTU_FACTORY` address with Base's exact runtime, so
    /// deterministic deploys land at the same addresses as on every other
    /// chain.
    string internal constant BSC = LibRainDeploy.BSC;

    /// @notice 0G mainnet (chain id 16661): `LibRainDeploy.ZEROG`.
    string internal constant ZEROG = LibRainDeploy.ZEROG;

    /// @notice Every network ST0x deploys to, as `foundry.toml` rpc aliases:
    /// the networks before 0G, then 0G.
    /// @dev A dispatch forks each network its suite is declared on and skips any
    /// that already has code at the expected address, so one dispatch ships a
    /// suite everywhere and a repeat dispatch is a no-op wherever it landed. 0G
    /// runs the audited 0.1.1 and 0.1.30 releases except the ones
    /// `LibStoxReleasedNetworks.releasesNotOnZerog` names, and the EU and US
    /// authoriser clones (`StoxDeploySuites.setCandidateNetworks`).
    /// @return The `foundry.toml` rpc aliases to deploy to.
    function deploymentNetworks() internal pure returns (string[] memory) {
        string[] memory before = networksBeforeZerog();
        string[] memory networks = new string[](before.length + 1);
        for (uint256 i = 0; i < before.length; i++) {
            networks[i] = before[i];
        }
        networks[before.length] = LibRainDeploy.ZEROG;
        return networks;
    }

    /// @notice The networks ST0x deployed to before 0G joined, as `foundry.toml`
    /// rpc aliases. Frozen: the releases 0G does not run stay on these, the
    /// networks they were cut for. A network added later is not one of them.
    /// @return The `foundry.toml` rpc aliases.
    function networksBeforeZerog() internal pure returns (string[] memory) {
        string[] memory networks = new string[](5);
        networks[0] = LibRainDeploy.BASE;
        networks[1] = LibRainDeploy.ETHEREUM;
        networks[2] = LibRainDeploy.HYPEREVM;
        networks[3] = LibRainDeploy.ROBINHOOD;
        networks[4] = LibRainDeploy.BSC;
        return networks;
    }

    /// @notice `deploymentNetworks()` without `excluded`, in order. Refuses
    /// `NotADeploymentNetwork` when `excluded` is not one of them.
    /// @param excluded The network to leave out.
    /// @return The other deployment networks.
    function networksWithout(string memory excluded) internal pure returns (string[] memory) {
        string[] memory networks = deploymentNetworks();
        bytes32 excludedHash = keccak256(bytes(excluded));
        uint256 kept = 0;
        for (uint256 i = 0; i < networks.length; i++) {
            if (keccak256(bytes(networks[i])) != excludedHash) {
                networks[kept++] = networks[i];
            }
        }
        if (kept == networks.length) revert NotADeploymentNetwork(excluded);
        assembly ("memory-safe") {
            mstore(networks, kept)
        }
        return networks;
    }
}
