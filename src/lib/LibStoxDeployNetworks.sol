// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @dev Thrown when `DEPLOYMENT_NETWORK` names neither the all-networks
/// sentinel nor one of the calling script's supported networks.
error UnknownDeploymentNetwork(string network);

/// @title LibStoxDeployNetworks
/// @notice The ST0x-specific deploy network-name constants that
/// `rain-deploy`'s `LibRainDeploy` does not provide, and the
/// `DEPLOYMENT_NETWORK` resolution the deploy scripts share. Each name matches
/// its `[rpc_endpoints]` alias in `foundry.toml`, the same convention as every
/// `LibRainDeploy` network constant. Consumed by the audited deploy scripts
/// `script/DeployProdV4_0_1_1.sol` and `script/DeployProdV4_0_1_30.sol`, and by
/// the cross-chain fork tests.
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

    /// @notice `DEPLOYMENT_NETWORK` sentinel selecting every network the
    /// calling script supports, so one dispatch ships a suite to all of them.
    /// @dev Not an `[rpc_endpoints]` alias, and deliberately not the empty
    /// string: an unset `DEPLOYMENT_NETWORK` must still revert rather than
    /// broadcast to every chain the script knows.
    string internal constant ALL = "all";

    /// @notice Resolves a `DEPLOYMENT_NETWORK` value against the calling
    /// script's supported set.
    /// @dev The `ALL` case returns `supported` itself, so the deployed set is
    /// the script's own list and cannot pick up a network that list excludes.
    /// @param selection The raw `DEPLOYMENT_NETWORK` value.
    /// @param supported The `foundry.toml` rpc aliases the script supports.
    /// @return Every supported alias for `ALL`, otherwise the single selected
    /// alias.
    function selectNetworks(string memory selection, string[] memory supported)
        internal
        pure
        returns (string[] memory)
    {
        bytes32 selectionHash = keccak256(bytes(selection));

        if (selectionHash == keccak256(bytes(ALL))) {
            return supported;
        }

        for (uint256 i = 0; i < supported.length; i++) {
            if (selectionHash == keccak256(bytes(supported[i]))) {
                string[] memory selected = new string[](1);
                selected[0] = supported[i];
                return selected;
            }
        }

        revert UnknownDeploymentNetwork(selection);
    }
}
