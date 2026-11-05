// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.7.0/token/ERC20/extensions/IERC20Metadata.sol";
import {IOwnable} from "../interface/IOwnable.sol";
import {LibRainDeployRegistryBeaconProxy} from "rain-factory-0.2.10/src/lib/LibRainDeployRegistryBeaconProxy.sol";

import {LibProdDeployCurrent} from "../generated/LibProdDeployCurrent.sol";
import {IStoxAssetIdV1} from "../interface/IStoxAssetIdV1.sol";
import {IStoxUnderlyingV1} from "../interface/IStoxUnderlyingV1.sol";
import {LibProdTokenConfig, TokenConfig} from "./LibProdTokenConfig.sol";
import {LibProdTokenTargets} from "./LibProdTokenTargets.sol";
import {ST0X_NAME_SUFFIX} from "./LibUnderlying.sol";
import {LibUnderlyingNamingRollout} from "./LibUnderlyingNamingRollout.sol";

/// @notice A V6 row's token is not deployed on this chain.
/// @param underlying The row's ticker.
/// @param token The row's pinned token address.
error V6TokenNotDeployed(string underlying, address token);

/// @notice The token at a row's pinned address reports another asset id. This
/// binds each `setUnderlying` to its row the way `TickerNotBoundToVault` does
/// for the live tokens: a nameless token has no symbol to check.
/// @param token The token.
/// @param expected The row's asset id.
/// @param actual The token's asset id.
error AssetIdNotBoundToToken(address token, string expected, string actual);

/// @notice A V6 token is not owned by the governance timelock, so the
/// timelock's `setUnderlying` would revert the whole batch.
/// @param token The token.
/// @param owner The token's owner.
error V6TokenOwnerMismatch(address token, address owner);

/// @notice A V6 token already has a name or symbol, so this is not its first
/// rename.
/// @param token The token.
/// @param name The token's name.
/// @param symbol The token's symbol.
error V6TokenAlreadyNamed(address token, string name, string symbol);

/// @notice The batch the table's leading `ROW_COUNT` V6 rows derive is not the
/// one this migration froze: one of those rows was edited, removed or
/// reordered after the migration was written. A scheduled batch would then
/// strand, so such a change needs a new dated script.
/// @param expected The frozen operation id.
/// @param actual The id the table derives.
error V6FirstRenameBatchMoved(bytes32 expected, bytes32 actual);

/// @notice The table has fewer V6 rows than this migration names.
/// @param expected `ROW_COUNT`.
/// @param actual The number of V6 rows.
error V6FirstRenameTableShort(uint256 expected, uint256 actual);

/// @notice After execution a V6 token's metadata is not what its first rename
/// sets.
/// @param token The token.
/// @param expected The expected value.
/// @param actual The value read.
error V6TokenNameMismatch(address token, string expected, string actual);

/// @title LibV6FirstRename
/// @notice The first `setUnderlying` of the first `ROW_COUNT` V6 tokens, as one
/// batch on the governance timelock
/// (`LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK`, the RBAC owner of every
/// V6 token). A V6 token deploys with an empty name and symbol, and this batch
/// names it: the vault reports `"t" + underlying` and
/// `underlyingName + " (ST0x)"`. The batch covers the leading `ROW_COUNT`
/// `LibProdTokenConfig.v6TokenConfigs()` rows in table order, so its operation
/// id is the same on every chain, and a row appended later gets its own dated
/// script.
library LibV6FirstRename {
    /// @notice Salt of the batch.
    bytes32 internal constant SALT = keccak256("st0x.v6-first-rename.1");

    /// @notice The batch's operation id, frozen when this migration was
    /// written. Every script of the migration refuses unless the table still
    /// derives it, so a row edit cannot strand a scheduled batch or block its
    /// record on any chain.
    bytes32 internal constant OPERATION_ID = 0x3c6ec3588c98243a0d60c3f975e51fc70d7151678963297bfedc1c068e357780;

    /// @notice How many leading V6 rows this migration names. Fixed, so a
    /// listing that appends a row does not move the batch.
    uint256 internal constant ROW_COUNT = 59;

    /// @return The governance timelock that owns every V6 token.
    function timelock() internal pure returns (address) {
        return LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK;
    }

    /// @param configs The V6 rows, in table order.
    /// @return The leading `ROW_COUNT` of them. Reverts
    /// `V6FirstRenameTableShort` when there are fewer.
    function leading(TokenConfig[] memory configs) internal pure returns (TokenConfig[] memory) {
        if (configs.length < ROW_COUNT) revert V6FirstRenameTableShort(ROW_COUNT, configs.length);
        uint256 count = ROW_COUNT;
        // Shorten the array in place.
        assembly ("memory-safe") {
            mstore(configs, count)
        }
        return configs;
    }

    /// @return configs The rows the batch names: the leading `ROW_COUNT` V6
    /// rows. Reverts `V6FirstRenameBatchMoved` unless they still derive
    /// `OPERATION_ID`.
    function rows() internal pure returns (TokenConfig[] memory configs) {
        configs = leading(LibProdTokenConfig.v6TokenConfigs());
        bytes32 id = operationId(configs);
        if (id != OPERATION_ID) revert V6FirstRenameBatchMoved(OPERATION_ID, id);
    }

    /// @param config The row.
    /// @return The row's pinned V6 token address.
    function tokenOf(TokenConfig memory config) internal pure returns (address) {
        return
            LibRainDeployRegistryBeaconProxy.registryBeaconProxyDeployedAddress(LibProdTokenTargets.tokenTarget(config));
    }

    /// @param configs The rows.
    /// @return targets One token per row.
    /// @return values Zero for every call.
    /// @return payloads `setUnderlying(underlying, underlyingName)` per row.
    function batch(TokenConfig[] memory configs)
        internal
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory payloads)
    {
        targets = new address[](configs.length);
        values = new uint256[](configs.length);
        payloads = new bytes[](configs.length);
        for (uint256 i = 0; i < configs.length; i++) {
            targets[i] = tokenOf(configs[i]);
            payloads[i] =
                abi.encodeCall(IStoxUnderlyingV1.setUnderlying, (configs[i].underlying, configs[i].underlyingName));
        }
    }

    /// @param configs The rows.
    /// @return The batch's operation id, as `TimelockController.hashOperationBatch` computes it with no predecessor.
    function operationId(TokenConfig[] memory configs) internal pure returns (bytes32) {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = batch(configs);
        return keccak256(abi.encode(targets, values, payloads, bytes32(0), SALT));
    }

    /// @param configs The rows.
    /// @param delay The delay to schedule with.
    /// @return The `scheduleBatch` calldata.
    function scheduleCalldata(TokenConfig[] memory configs, uint256 delay) internal pure returns (bytes memory) {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = batch(configs);
        return abi.encodeCall(TimelockController.scheduleBatch, (targets, values, payloads, bytes32(0), SALT, delay));
    }

    /// @notice Reverts unless `config` can be named by the batch: its ticker
    /// and name are well formed, its token is deployed, reports the row's
    /// asset id, is owned by the governance timelock, and has no name or
    /// symbol yet.
    /// @param config The row.
    function assertReady(TokenConfig memory config) internal view {
        LibUnderlyingNamingRollout.assertUnderlyingWellFormed(config);
        address token = tokenOf(config);
        if (token.code.length == 0) revert V6TokenNotDeployed(config.underlying, token);
        string memory assetId = IStoxAssetIdV1(token).assetId();
        if (keccak256(bytes(assetId)) != keccak256(bytes(config.assetId))) {
            revert AssetIdNotBoundToToken(token, config.assetId, assetId);
        }
        address owner = IOwnable(token).owner();
        if (owner != timelock()) revert V6TokenOwnerMismatch(token, owner);
        string memory name = IERC20Metadata(token).name();
        string memory symbol = IERC20Metadata(token).symbol();
        if (bytes(name).length != 0 || bytes(symbol).length != 0) revert V6TokenAlreadyNamed(token, name, symbol);
    }

    /// @notice `assertReady` over every row.
    /// @param configs The rows.
    function assertAllReady(TokenConfig[] memory configs) internal view {
        for (uint256 i = 0; i < configs.length; i++) {
            assertReady(configs[i]);
        }
    }

    /// @notice Reverts unless `config`'s token reports the name and symbol
    /// its first rename sets and still reports the row's asset id.
    /// @param config The row.
    function assertNamed(TokenConfig memory config) internal view {
        address token = tokenOf(config);
        assertEqual(token, string.concat("t", config.underlying), IERC20Metadata(token).symbol());
        assertEqual(token, string.concat(config.underlyingName, ST0X_NAME_SUFFIX), IERC20Metadata(token).name());
        assertEqual(token, config.assetId, IStoxAssetIdV1(token).assetId());
    }

    /// @notice `assertNamed` over every row.
    /// @param configs The rows.
    function assertAllNamed(TokenConfig[] memory configs) internal view {
        for (uint256 i = 0; i < configs.length; i++) {
            assertNamed(configs[i]);
        }
    }

    function assertEqual(address token, string memory expected, string memory actual) private pure {
        if (keccak256(bytes(expected)) != keccak256(bytes(actual))) {
            revert V6TokenNameMismatch(token, expected, actual);
        }
    }
}
