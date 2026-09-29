// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.16.2/src/Vm.sol";
import {DeployMissingTokens} from "../../script/20260807-deploy-missing-tokens.s.sol";
import {TokenInstance} from "../../src/lib/LibTokenInvariants.sol";
import {TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";

/// @dev Exposes the script's internals for the pure selection tests.
contract DeployMissingTokensHarness is DeployMissingTokens {
    /// @notice The script's `_selectMissing()`, externally callable. Takes the
    /// config and Base tables so a test can drive the alignment guards with a
    /// deliberately drifted pair, which the canonical tables cannot express.
    /// @param configs The canonical name/symbol table, Base row order.
    /// @param base The Base token table.
    /// @param target The target chain's existing token table. Named `target`
    /// rather than `targetTokens` so it does not shadow `targetTokens()` below.
    /// @return The Base tokens absent from `target`.
    function selectMissing(TokenConfig[] memory configs, TokenInstance[] memory base, TokenInstance[] memory target)
        external
        pure
        returns (TokenConfig[] memory)
    {
        return _selectMissing(configs, base, target);
    }

    /// @notice The script's `_targetTokens()`, externally callable.
    /// @return The active chain's token table.
    function targetTokens() external view returns (TokenInstance[] memory) {
        return _targetTokens();
    }

    /// @notice The script's `_assertAuthoriserReady()`, externally callable.
    /// @return The validated authoriser for the active chain.
    function assertAuthoriserReady() external view returns (address) {
        return _assertAuthoriserReady();
    }

    /// @notice The script's `_readDeployment()`, externally callable.
    /// @param logs The logs to resolve the deployed pair from.
    /// @param unifiedDeployer The deployer whose event is authoritative.
    /// @param underlying The token being deployed, for the revert.
    /// @return receiptVault The deployed receipt vault.
    /// @return wrapped The deployed wrapped token vault.
    function readDeployment(Vm.Log[] memory logs, address unifiedDeployer, string memory underlying)
        external
        pure
        returns (address receiptVault, address wrapped)
    {
        return _readDeployment(logs, unifiedDeployer, underlying);
    }
}
