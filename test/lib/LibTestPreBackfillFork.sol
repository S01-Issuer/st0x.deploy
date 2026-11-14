// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";

import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";

/// @title LibTestPreBackfillFork
/// @notice Forks a deployment network at a pinned block before the V5
/// backfill: the root line is at genesis and the chain's Safe is an unscoped
/// delegate of the root.
library LibTestPreBackfillFork {
    error NoPreBackfillBlock(string network);

    uint256 internal constant BASE_BLOCK = 53495406;
    uint256 internal constant ETHEREUM_BLOCK = 26340194;
    uint256 internal constant HYPEREVM_BLOCK = 50349731;
    uint256 internal constant ROBINHOOD_BLOCK = 105752011;
    uint256 internal constant BSC_BLOCK = 131593319;

    function blockOf(string memory network) internal pure returns (uint256) {
        bytes32 name = keccak256(bytes(network));
        if (name == keccak256(bytes(LibRainDeploy.BASE))) return BASE_BLOCK;
        if (name == keccak256(bytes(LibStoxDeployNetworks.ETHEREUM))) return ETHEREUM_BLOCK;
        if (name == keccak256(bytes(LibStoxDeployNetworks.HYPEREVM))) return HYPEREVM_BLOCK;
        if (name == keccak256(bytes(LibStoxDeployNetworks.ROBINHOOD))) return ROBINHOOD_BLOCK;
        if (name == keccak256(bytes(LibStoxDeployNetworks.BSC))) return BSC_BLOCK;
        revert NoPreBackfillBlock(network);
    }

    function select(Vm vm, string memory network) internal {
        vm.createSelectFork(network, blockOf(network));
    }
}
