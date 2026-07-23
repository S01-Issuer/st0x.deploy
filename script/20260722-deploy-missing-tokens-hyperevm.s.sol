// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";
import {Vm} from "forge-std-1.16.1/src/Vm.sol";
import {
    OffchainAssetReceiptVaultConfigV2
} from "rain-vats-0.1.6/src/concrete/deploy/OffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {ReceiptVaultConfigV2} from "rain-vats-0.1.6/src/abstract/ReceiptVault.sol";
import {IReceiptVaultV3} from "rain-vats-0.1.6/src/interface/IReceiptVaultV3.sol";
import {IAuthorizeV1} from "rain-vats-0.1.6/src/interface/IAuthorizeV1.sol";
import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";
import {LibBeaconInvariants} from "../src/lib/LibBeaconInvariants.sol";
import {IStoxUnifiedDeployerV1} from "../src/interface/IStoxUnifiedDeployerV1.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
import {LibProdTokenConfig, TokenConfig} from "../src/lib/LibProdTokenConfig.sol";
import {LibTokenInvariants, TokenInstance} from "../src/lib/LibTokenInvariants.sol";

/// @notice Pre-flight failed: a required deployer contract has no runtime
/// code at its pinned 0.1.1 address on the active fork.
/// @param deployer The pinned deployer address that is missing.
error DeployerNotDeployed(address deployer);

/// @notice Pre-flight failed: the active chain's resolved token-owner Safe is
/// not the pinned HYPEREVM Safe — wrong-network dispatch, or the pin has not
/// landed.
/// @param safe The Safe address the active chain resolved to.
error HyperEvmSafeNotReady(address safe);

/// @notice Pre-flight failed: the pinned HyperEVM V4 authoriser is not ready
/// (unpinned / no code / wrong codehash).
/// @param authoriser The authoriser address inspected.
error HyperEvmAuthoriserNotReady(address authoriser);

/// @notice Every canonical config row already has a fully-hydrated Ethereum
/// table entry — there is nothing left to deploy. Re-dispatching would mint
/// duplicate tokens, which is never meaningful.
error NoMissingTokens();

/// @notice The canonical config table and the Ethereum token table have
/// drifted out of row alignment. The gap-filling join is by index, so a
/// misaligned row must abort the deploy rather than deploy under the wrong
/// underlying.
/// @param index The misaligned row.
/// @param configUnderlying The config table's underlying at that row.
/// @param tableUnderlying The Ethereum table's underlying at that row.
error TokenTableMisaligned(uint256 index, string configUnderlying, string tableUnderlying);

/// @title DeployMissingTokensHyperEvm
/// @notice **PENDING.** The HyperEVM token deploy (RAI-1511): deploys, on
/// HyperEVM, exactly the canonical config rows whose
/// `LibTokenInvariants.productionTokensHyperEvm()` entry is still all-zero —
/// which at authoring time is the ENTIRE 29-token canonical set (the initial
/// bootstrap is just a gap-fill of everything). Dispatch via
/// `Actions → manual-broadcast` with
/// `script = 20260722-deploy-missing-tokens-hyperevm` and
/// `network = hyperevm`. Flips to `**EXECUTED YYYY-MM-DD.**` in the
/// post-execution pin PR that hydrates the table from the logged tuples.
///
/// Deliberately SELF-SCOPING, the same shape as the Ethereum gap-fill
/// (`20260722-deploy-missing-tokens-ethereum`): joins the canonical config
/// against the HyperEVM table row-by-row (aborting on any underlying
/// misalignment) and deploys only the all-zero rows — the explicit "missing
/// on this chain" state. Partial-failure recovery and late-added tokens are
/// both just re-dispatches; a fully-hydrated table refuses to deploy
/// anything (`NoMissingTokens`).
///
/// Per deployed token, identical to the executed Ethereum flow: deploy via
/// the 0.1.1 unified deployer (initialAdmin = deploy key) -> read back the
/// ERC-1155 receipt -> `setAuthorizer(HyperEVM V4 authoriser)` ->
/// `transferOwnership(HyperEVM Safe)` — one deploy-key broadcast, no Safe
/// signature. Logs each (underlying, receipt, receiptVault, wrapped) tuple
/// for the pin PR. Ordering per RAI-1511: pre-flight hard-gates on the
/// 0.1.1 core, the in-use beacons being HyperEVM-Safe-owned (the
/// beacon-owner migration), the hydrated authoriser pin, and the hydrated
/// Safe pin — dispatching early is a typed revert, never a partial deploy.
contract DeployMissingTokensHyperEvm is Script {
    /// @notice Assert a deployer contract is present at its pinned address.
    /// @param deployer The pinned deployer address.
    function _assertDeployer(address deployer) internal view {
        if (deployer.code.length == 0) revert DeployerNotDeployed(deployer);
    }

    /// @notice The active chain's token-owner Safe, resolved + policy-asserted
    /// through the shared entry point, then guarded to be HYPEREVM's Safe.
    /// @return safe The validated HyperEVM token-owner Safe address.
    function _assertSafeReady() internal view returns (address safe) {
        safe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        if (safe != LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_HYPEREVM) {
            revert HyperEvmSafeNotReady(safe);
        }
    }

    /// @notice Assert the Ethereum V4 authoriser is deployed at its pin with
    /// the shared EIP-1167 codehash.
    /// @return authoriser The validated authoriser address.
    function _assertAuthoriserReady() internal view returns (address authoriser) {
        authoriser = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_HYPEREVM;
        if (
            authoriser == address(0) || authoriser.code.length == 0
                || authoriser.codehash != LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH
        ) {
            revert HyperEvmAuthoriserNotReady(authoriser);
        }
    }

    /// @notice Select the configs to deploy: canonical config rows whose
    /// Ethereum table entry is all-zero. Joined by index with the underlying
    /// asserted equal row-for-row (the same alignment the cross-chain parity
    /// pin enforces); any drift aborts (`TokenTableMisaligned`). Reverts
    /// `NoMissingTokens` when the table is fully hydrated.
    /// @return missing The config rows still missing on HyperEVM.
    function _selectMissing() internal pure returns (TokenConfig[] memory missing) {
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        TokenInstance[] memory table = LibTokenInvariants.productionTokensHyperEvm();
        if (configs.length != table.length) {
            revert TokenTableMisaligned(
                configs.length < table.length ? configs.length : table.length, "<length>", "<length>"
            );
        }
        TokenConfig[] memory candidates = new TokenConfig[](configs.length);
        uint256 count = 0;
        for (uint256 i = 0; i < configs.length; i++) {
            if (keccak256(bytes(configs[i].underlying)) != keccak256(bytes(table[i].underlying))) {
                revert TokenTableMisaligned(i, configs[i].underlying, table[i].underlying);
            }
            bool entryClear = table[i].receipt == address(0) && table[i].receiptVault == address(0)
                && table[i].wrappedTokenVault == address(0);
            if (!entryClear) {
                continue;
            }
            candidates[count] = configs[i];
            count++;
        }
        if (count == 0) {
            revert NoMissingTokens();
        }
        missing = new TokenConfig[](count);
        for (uint256 i = 0; i < count; i++) {
            missing[i] = candidates[i];
        }
    }

    /// @notice Deploy every canonical token still missing from the Ethereum
    /// table via the 0.1.1 unified deployer, wire each onto the V4
    /// authoriser, and hand ownership to the Safe — one deploy-key
    /// broadcast, matched to the executed 20260706 flow. Broadcasts as the
    /// key `manual-broadcast.yaml` supplies via `--private-key`. Logs each
    /// deployed tuple for the pin PR.
    function run() external {
        // Pre-flight: identical gate chain to 20260706 — the 0.1.1 core
        // (whose beacon set IS the chain's in-use production beacons), the
        // in-use beacons Safe-owned, the authoriser, the Safe.
        address unifiedDeployer = LibProdDeployV4.STOX_UNIFIED_DEPLOYER_0_1_1;
        _assertDeployer(unifiedDeployer);
        _assertDeployer(LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1);
        _assertDeployer(LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_0_1_1);
        LibBeaconInvariants.assertProdBeaconsOwnedByChainSafe(block.chainid);
        address authoriser = _assertAuthoriserReady();
        address safe = _assertSafeReady();

        TokenConfig[] memory configs = _selectMissing();

        bytes32 deploymentTopic = keccak256("Deployment(address,address,address)");

        vm.startBroadcast();

        // Deployer identity — inside `vm.startBroadcast()` msg.sender
        // resolves to the broadcast address (`--private-key` in production).
        address deployer = msg.sender;

        console2.log("Deploying", configs.length, "missing tokens on chain id", block.chainid);
        console2.log("initialAdmin (deploy key, handed to Safe):", deployer);
        console2.log("token-owner Safe:", safe);
        console2.log("V4 authoriser:", authoriser);

        for (uint256 i = 0; i < configs.length; i++) {
            TokenConfig memory cfg = configs[i];
            OffchainAssetReceiptVaultConfigV2 memory vaultConfig = OffchainAssetReceiptVaultConfigV2({
                // The deploy key is the transient owner: it setAuthorizer's the
                // vault then hands ownership to the Safe, all below.
                initialAdmin: deployer,
                receiptVaultConfig: ReceiptVaultConfigV2({
                    asset: address(0), name: cfg.name, symbol: cfg.symbol, receipt: address(0)
                })
            });

            vm.recordLogs();
            IStoxUnifiedDeployerV1(unifiedDeployer).newTokenAndWrapperVault(vaultConfig);

            // Fish the deployed pair out of the unified deployer's
            // `Deployment(sender, asset, wrapper)` event.
            Vm.Log[] memory logs = vm.getRecordedLogs();
            (address receiptVault, address wrapped) = (address(0), address(0));
            for (uint256 j = 0; j < logs.length; j++) {
                if (
                    logs[j].emitter == unifiedDeployer && logs[j].topics.length > 0
                        && logs[j].topics[0] == deploymentTopic
                ) {
                    (, receiptVault, wrapped) = abi.decode(logs[j].data, (address, address, address));
                }
            }

            // The unified deployer's event drops the ERC-1155 receipt, so read
            // it back off the vault for the pin PR to hydrate.
            address receipt = address(IReceiptVaultV3(payable(receiptVault)).receipt());

            // Wire onto the authoriser (deploy key is still owner), then
            // relinquish ownership to the Safe. Order matters: `setAuthorizer`
            // is `onlyOwner`, so it must precede the handoff.
            ISetAuthorizer(receiptVault).setAuthorizer(IAuthorizeV1(authoriser));
            Ownable(receiptVault).transferOwnership(safe);

            console2.log("==== TOKEN DEPLOYED ====");
            console2.log("underlying:", cfg.underlying);
            console2.log("receipt (ERC-1155):", vm.toString(receipt));
            console2.log("receiptVault:", vm.toString(receiptVault));
            console2.log("wrappedTokenVault:", vm.toString(wrapped));
        }

        vm.stopBroadcast();

        console2.log(
            "All missing tokens deployed, authorised, and handed to the Safe."
            " Hydrate the all-zero LibTokenInvariants.productionTokensHyperEvm()" " rows from the logged tuples."
        );
    }
}

/// @dev Local mirror of the receipt-vault `setAuthorizer(IAuthorizeV1)`
/// owner-gated selector — rain-vats ships no interface carrying it; see the
/// 20260706 script for the full rationale.
interface ISetAuthorizer {
    function setAuthorizer(IAuthorizeV1 newAuthorizer) external;
}
