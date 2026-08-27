// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.2/src/Script.sol";
import {console2} from "forge-std-1.16.2/src/console2.sol";
import {Vm} from "forge-std-1.16.2/src/Vm.sol";
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

/// @notice Dispatched against a chain this script cannot copy Base's token
/// set onto. Base itself is rejected too — it is the SOURCE, so "missing on
/// Base" is not a state this script can resolve.
/// @param chainId The active chain id.
error UnsupportedTargetChain(uint256 chainId);

/// @notice Pre-flight failed: the active chain's V4 authoriser is not ready
/// (unpinned, no code, or the wrong codehash).
/// @param authoriser The authoriser address inspected.
error AuthoriserNotReady(address authoriser);

/// @notice The canonical name/symbol table and the Base token table have
/// drifted out of row alignment. Every name/symbol this script deploys is
/// read from the config row at the Base row's index, so a misaligned pair
/// would deploy a token under the wrong underlying's strings.
/// @param index The misaligned row.
/// @param configUnderlying The config table's underlying at that row.
/// @param baseUnderlying The Base table's underlying at that row.
error TokenTableMisaligned(uint256 index, string configUnderlying, string baseUnderlying);

/// @notice The canonical name/symbol table has fewer rows than the Base token
/// table, so a deployed Base token has no config row to read its name and
/// symbol from. The reverse — a config table running AHEAD of Base — is a
/// normal state: rows are authored when a ticker is chosen and Base is pinned
/// when it is deployed, so the config table leads until the Base deploy lands.
/// @param configsLength The canonical config table's row count.
/// @param baseLength The Base token table's row count.
error TokenTableTooShort(uint256 configsLength, uint256 baseLength);

/// @notice Every token on Base already exists on the target chain, so there
/// is nothing to copy. This is also what stops a re-dispatch from minting
/// duplicates of tokens that already landed.
error NoMissingTokens();

/// @notice The unified deployer emitted no `Deployment` event this iteration,
/// so there is no address to wire or hand over. Named rather than left to
/// fault on a zero address, because it happens MID-BROADCAST with earlier
/// tokens already live.
/// @param underlying The token whose deployment could not be resolved.
error DeploymentEventMissing(string underlying);

/// @notice A freshly deployed vault did not end up owned by the Safe. A vault
/// left on the deploy key is a production asset held by a CI secret.
/// @param receiptVault The vault whose handoff did not land.
/// @param expected The Safe ownership was meant to land on.
/// @param actual The owner actually read back.
error OwnershipHandoffFailed(address receiptVault, address expected, address actual);

/// @notice A freshly deployed vault is not routed to the chain's authoriser.
/// Until `setAuthorizer` lands, every operation on the vault reverts.
/// @param receiptVault The vault whose authoriser did not land.
/// @param expected The authoriser it must route to.
/// @param actual The authoriser actually read back.
error AuthoriserNotWired(address receiptVault, address expected, address actual);

/// @title DeployMissingTokens
/// @notice Copies Base's production token set onto whichever chain this is
/// dispatched against, deploying only the tokens that chain does not already
/// have. Supersedes the per-chain `20260722-deploy-missing-tokens-ethereum`
/// and `-hyperevm` scripts, which were byte-identical apart from the chain
/// they hardcoded.
///
/// @dev "Missing" is defined against BASE, not against the canonical config:
/// a token is missing when its `underlying` appears in
/// `LibTokenInvariants.productionTokensBase()` and not in the target chain's
/// table. Base is the source of truth for what the token set IS — a ticker is
/// deployed there first, pinned, and then copied outward — so the target
/// chain's table simply lags Base until this script runs.
///
/// Defining it that way is what lets the tables carry different lengths
/// between a Base deploy and its copy. The rollout is:
///
/// 1. the tokens are deployed on Base and pinned into `productionTokensBase()`
/// 2. this script is dispatched per target chain, deploying the difference
/// 3. each run's logged tuples are pinned into that chain's table
///
/// Cross-chain parity is red between (1) and (3) — the chains genuinely do
/// differ in that window, and the suite says so rather than being taught to
/// tolerate it.
///
/// @dev Dispatch via `Actions → manual-broadcast` with
/// `script = 20260807-deploy-missing-tokens` and `network` set to the target
/// chain. One dispatch covers one chain because the workflow supplies a
/// single RPC per run; the SELECTION is chain-generic, so the same script
/// serves every target chain and any chain added later needs only a table and
/// an authoriser pin here.
///
/// Per token, identical to the scripts it replaces: deploy via the 0.1.1
/// unified deployer (initialAdmin = deploy key) -> read back the ERC-1155
/// receipt -> `setAuthorizer(target chain's V4 authoriser)` ->
/// `transferOwnership(target chain's token-owner Safe)`. One deploy-key
/// broadcast, no Safe signature. Logs each
/// (underlying, receipt, receiptVault, wrapped) tuple for the pin.
contract DeployMissingTokens is Script {
    /// @notice Assert a deployer contract is present at its pinned address.
    /// @param deployer The pinned deployer address to check.
    function _assertDeployer(address deployer) internal view {
        if (deployer == address(0) || deployer.code.length == 0) {
            revert DeployerNotDeployed(deployer);
        }
    }

    /// @notice The active chain's already-deployed token table.
    /// @dev Base is deliberately absent: it is the source this script copies
    /// FROM, so dispatching against it is a wrong-network dispatch rather
    /// than a no-op. A new target chain is onboarded by adding its table
    /// here alongside its authoriser pin below.
    /// @return tokens The target chain's token instances.
    function _targetTokens() internal view returns (TokenInstance[] memory tokens) {
        if (block.chainid == LibSafeInvariants.ETHEREUM_CHAIN_ID) {
            return LibTokenInvariants.productionTokensEthereum();
        }
        if (block.chainid == LibSafeInvariants.HYPEREVM_CHAIN_ID) {
            return LibTokenInvariants.productionTokensHyperEvm();
        }
        revert UnsupportedTargetChain(block.chainid);
    }

    /// @notice The active chain's V4 authoriser clone, asserted deployed at
    /// its pin with the shared EIP-1167 codehash.
    /// @return authoriser The validated authoriser address.
    function _assertAuthoriserReady() internal view returns (address authoriser) {
        if (block.chainid == LibSafeInvariants.ETHEREUM_CHAIN_ID) {
            authoriser = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM;
        } else if (block.chainid == LibSafeInvariants.HYPEREVM_CHAIN_ID) {
            authoriser = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_HYPEREVM;
        } else {
            revert UnsupportedTargetChain(block.chainid);
        }

        if (
            authoriser == address(0) || authoriser.code.length == 0
                || authoriser.codehash != LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH
        ) {
            revert AuthoriserNotReady(authoriser);
        }
    }

    /// @notice Select the tokens on Base that the target chain does not have,
    /// returning their canonical deploy configs.
    /// @dev The config table pairs with the BASE table by index, so it is
    /// checked row-for-row here; the target chain is matched by `underlying`
    /// rather than index, which is what allows its table to be shorter than
    /// Base's while a copy is outstanding.
    ///
    /// The config table is allowed to run LONGER than Base — a row is authored
    /// when a ticker is chosen and Base is pinned when it is deployed, so the
    /// config table leads in that window. Only the trailing rows Base actually
    /// carries are read, so the excess is inert; a config table SHORTER than
    /// Base is the genuine error, because a Base row would then have no
    /// name/symbol to deploy under.
    ///
    /// Both tables are taken as parameters rather than read from the libraries
    /// so that the misalignment guards below can be driven from a test — they
    /// are the only thing standing between a drifted table and deploying a
    /// token under the wrong underlying's strings, so they are worth being
    /// able to exercise directly. `run()` passes the canonical tables.
    /// @param configs The canonical name/symbol table, Base row order.
    /// @param base The Base token table — the source of truth for the set.
    /// @param targetTokens The target chain's existing token table.
    /// @return missing The deploy configs for the tokens to copy.
    function _selectMissing(
        TokenConfig[] memory configs,
        TokenInstance[] memory base,
        TokenInstance[] memory targetTokens
    ) internal pure returns (TokenConfig[] memory missing) {
        if (configs.length < base.length) {
            revert TokenTableTooShort(configs.length, base.length);
        }

        TokenConfig[] memory candidates = new TokenConfig[](base.length);
        uint256 count = 0;
        for (uint256 i = 0; i < base.length; i++) {
            if (keccak256(bytes(configs[i].underlying)) != keccak256(bytes(base[i].underlying))) {
                revert TokenTableMisaligned(i, configs[i].underlying, base[i].underlying);
            }
            if (_hasUnderlying(targetTokens, base[i].underlying)) {
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

    /// @notice Resolve the deployed pair out of the unified deployer's
    /// `Deployment(sender, asset, wrapper)` event.
    /// @dev Its own function, taking the logs rather than calling
    /// `vm.getRecordedLogs()` itself, so the miss can be shown to revert: the
    /// alternative is a zero address flowing into the receipt readback and
    /// faulting as a raw call to an empty account, mid-broadcast, with earlier
    /// tokens already live. Logs from other emitters and other events from the
    /// deployer are both ignored rather than mistaken for a deployment.
    /// @param logs The logs recorded across the deploy call.
    /// @param unifiedDeployer The deployer whose event is authoritative.
    /// @param underlying The token being deployed, for the revert.
    /// @return receiptVault The deployed receipt vault.
    /// @return wrapped The deployed wrapped token vault.
    function _readDeployment(Vm.Log[] memory logs, address unifiedDeployer, string memory underlying)
        internal
        pure
        returns (address receiptVault, address wrapped)
    {
        bytes32 deploymentTopic = keccak256("Deployment(address,address,address)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == unifiedDeployer && logs[i].topics.length > 0 && logs[i].topics[0] == deploymentTopic)
            {
                (, receiptVault, wrapped) = abi.decode(logs[i].data, (address, address, address));
            }
        }
        if (receiptVault == address(0)) {
            revert DeploymentEventMissing(underlying);
        }
    }

    /// @notice Assert a freshly deployed vault ended up wired to the chain's
    /// authoriser and owned by its Safe.
    /// @dev Each token is wired and handed over inside the same broadcast, so
    /// a silent miss leaves a live production vault either inoperable or owned
    /// by the CI deploy key, and nothing catches it until the pin PR's
    /// acceptance tests run. Public so it can be driven directly: an assertion
    /// reachable only from inside a broadcast loop cannot be shown to fire.
    /// Mirrors `20260706-deploy-tokens-ethereum`'s check of the same name.
    /// @param receiptVault The vault just deployed.
    /// @param expectedAuthoriser The authoriser it must route to.
    /// @param expectedSafe The Safe ownership must have landed on.
    function assertHandoffLanded(address receiptVault, address expectedAuthoriser, address expectedSafe) public view {
        address wiredAuthoriser = ISetAuthorizer(receiptVault).authorizer();
        if (wiredAuthoriser != expectedAuthoriser) {
            revert AuthoriserNotWired(receiptVault, expectedAuthoriser, wiredAuthoriser);
        }
        address landedOwner = Ownable(receiptVault).owner();
        if (landedOwner != expectedSafe) {
            revert OwnershipHandoffFailed(receiptVault, expectedSafe, landedOwner);
        }
    }

    /// @notice Whether `tokens` already carries an entry for `underlying`.
    /// @param tokens The table to search.
    /// @param underlying The ticker to look for.
    /// @return True when the ticker is already present.
    function _hasUnderlying(TokenInstance[] memory tokens, string memory underlying) internal pure returns (bool) {
        bytes32 target = keccak256(bytes(underlying));
        for (uint256 i = 0; i < tokens.length; i++) {
            if (keccak256(bytes(tokens[i].underlying)) == target) {
                return true;
            }
        }
        return false;
    }

    /// @notice Deploy every Base token the active chain is missing via the
    /// 0.1.1 unified deployer, wire each onto that chain's V4 authoriser, and
    /// hand ownership to its token-owner Safe — one deploy-key broadcast.
    /// Logs each deployed tuple for the pin.
    function run() external {
        address unifiedDeployer = LibProdDeployV4.STOX_UNIFIED_DEPLOYER_0_1_1;
        _assertDeployer(unifiedDeployer);
        _assertDeployer(LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1);
        _assertDeployer(LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_0_1_1);
        LibBeaconInvariants.assertProdBeaconsOwnedByChainSafe(block.chainid);
        address authoriser = _assertAuthoriserReady();
        address safe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);

        TokenConfig[] memory configs = _selectMissing(
            LibProdTokenConfig.productionTokenConfigs(), LibTokenInvariants.productionTokensBase(), _targetTokens()
        );

        vm.startBroadcast();

        // Deployer identity — inside `vm.startBroadcast()` msg.sender
        // resolves to the broadcast address (`--private-key` in production).
        address deployer = msg.sender;

        console2.log("Copying", configs.length, "Base tokens onto chain id", block.chainid);
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

            (address receiptVault, address wrapped) =
                _readDeployment(vm.getRecordedLogs(), unifiedDeployer, cfg.underlying);

            // The unified deployer's event drops the ERC-1155 receipt, so read
            // it back off the vault for the pin to hydrate.
            address receipt = address(IReceiptVaultV3(payable(receiptVault)).receipt());

            // Wire onto the authoriser (deploy key is still owner), then
            // relinquish ownership to the Safe. Order matters: `setAuthorizer`
            // is `onlyOwner`, so it must precede the handoff.
            ISetAuthorizer(receiptVault).setAuthorizer(IAuthorizeV1(authoriser));
            Ownable(receiptVault).transferOwnership(safe);
            assertHandoffLanded(receiptVault, authoriser, safe);

            console2.log("==== TOKEN DEPLOYED ====");
            console2.log("underlying:", cfg.underlying);
            console2.log("receipt (ERC-1155):", vm.toString(receipt));
            console2.log("receiptVault:", vm.toString(receiptVault));
            console2.log("wrappedTokenVault:", vm.toString(wrapped));
        }

        vm.stopBroadcast();

        console2.log(
            "All missing tokens deployed, authorised, and handed to the Safe."
            " Pin the logged tuples into this chain's LibTokenInvariants table."
        );
    }
}

/// @dev Local mirror of the receipt-vault `setAuthorizer(IAuthorizeV1)`
/// owner-gated selector — rain-vats ships no interface carrying it; see the
/// 20260706 script for the full rationale.
interface ISetAuthorizer {
    function setAuthorizer(IAuthorizeV1 newAuthorizer) external;
    function authorizer() external view returns (address);
}
