// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";
import {Vm} from "forge-std-1.16.1/src/Vm.sol";
import {IERC165} from "@openzeppelin-contracts-5.6.1/utils/introspection/IERC165.sol";
import {
    OffchainAssetReceiptVaultConfigV2
} from "rain-vats-0.1.6/src/concrete/deploy/OffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {ReceiptVaultConfigV2} from "rain-vats-0.1.6/src/abstract/ReceiptVault.sol";

import {IGnosisSafe} from "../src/interface/IGnosisSafe.sol";
import {IAuthorisable} from "../src/interface/IAuthorisable.sol";
import {IOwnable} from "../src/interface/IOwnable.sol";
import {IStoxUnifiedDeployerV1} from "../src/interface/IStoxUnifiedDeployerV1.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibSafeOps, SafeTx} from "../src/lib/LibSafeOps.sol";
import {LibProdDeployCurrent} from "../src/generated/LibProdDeployCurrent.sol";
import {LibProdAuthoriserClones} from "../src/lib/LibProdAuthoriserClones.sol";
import {LibProdTokenConfig, TokenConfig} from "../src/lib/LibProdTokenConfig.sol";
import {LibTokenInvariants, TokenInstance} from "../src/lib/LibTokenInvariants.sol";

/// @notice Minimal surface for the receipt vault's owner-gated
/// `setAuthorizer`. Encoded via the interface so the calldata is the
/// canonical `setAuthorizer(address)` selector.
interface ISetAuthorizer {
    function setAuthorizer(address newAuthorizer) external;
}

/// @notice Pre-flight failed: a required deployer contract has no runtime
/// code at its pinned V4 address on the active fork — the core V4 suites
/// have not been broadcast to this chain yet (bootstrap step 1).
/// @param deployer The pinned deployer address that is missing.
error DeployerNotDeployed(address deployer);

/// @notice Pre-flight failed: the Ethereum token table in
/// `LibTokenInvariants.productionTokensEthereum()` is still placeholders,
/// so the authorise bundle has no vaults to target. Deploy the tokens
/// (`run()`) and hydrate the table (pin PR) first.
error EthereumTokenTableNotHydrated();

/// @notice Pre-flight failed: a receipt vault to be authorised is not
/// owned by the Ethereum Safe, so the Safe's `setAuthorizer` call would
/// revert `onlyOwner`. Surfaces the offending vault.
/// @param vault The receipt vault whose owner is wrong.
/// @param expectedOwner The Ethereum token-owner Safe.
/// @param actualOwner The owner actually read on-chain.
error VaultNotOwnedBySafe(address vault, address expectedOwner, address actualOwner);

/// @notice Pre-flight failed: the pinned Ethereum V4 authoriser clone is
/// still `address(0)` / has no code / has the wrong codehash. Mirrors the
/// clone-script guards; a token cannot be authorised onto a clone that
/// isn't the pinned, deployed one.
/// @param clone The clone address inspected.
error EthereumCloneNotReady(address clone);

/// @notice `verify()` found the pre-emitted authorise bundle does not
/// match what the live pre-flight would author. Surfaces the first field
/// that drifted.
/// @param field The field that diverged (e.g. `"chainId"`, `"to"`,
/// `"data"`, `"safeTxHash"`, `"txCount"`).
error VerifyMismatch(string field);

/// @title DeployTokensEthereum
/// @notice **PENDING.** Deploys the full 20-token ST0x production set on
/// Ethereum mainnet, matched to Base (RAI-1095), and authors the
/// authoriser-wiring Safe bundle. Both entrypoints stay red until the
/// Ethereum core is deployed (`run()`) and the Safe + clone + token table
/// are live (`authorizeTokens()`). Flips to `**EXECUTED YYYY-MM-DD.**` in
/// the post-execution pin PR.
/// @dev Two operations, mirroring the deploy-then-configure split the rest
/// of the multichain stack uses:
///
/// - **`run()`** (EOA broadcast) — iterates
///   `LibProdTokenConfig.productionTokenConfigs()` and calls
///   `StoxUnifiedDeployer.newTokenAndWrapperVault` once per token with
///   `initialAdmin` = the Ethereum token-owner Safe and the Base-verbatim
///   `name` / `symbol`. Each call deploys the receipt vault + wrapped
///   vault beacon-proxy pair; because `initialAdmin` is the Safe, the
///   vaults are Safe-owned from block one and the broadcasting EOA never
///   holds any role. The deterministic addresses are NOT known ahead of
///   the broadcast (the beacon-set deployer uses nonce-based clones), so
///   the script logs each deployed `(underlying, receiptVault, wrapped)`
///   for the post-execution pin PR to hydrate
///   `LibTokenInvariants.productionTokensEthereum()`.
///
/// - **`authorizeTokens()`** (Safe Tx Builder bundle) — after the token
///   table is hydrated, authors a 20-tx bundle of owner-gated
///   `setAuthorizer(clone)` calls (one per receipt vault) wiring every
///   vault onto the Ethereum V4 authoriser clone. Freshly-deployed vaults
///   initialise with themselves as authoriser (every op reverts) until
///   this lands, exactly as on Base.
///
/// After both run and the token table is hydrated, the cross-chain parity
/// pin (`StoxCrossChainParity.t.sol`, RAI-1097) is the acceptance test:
/// name/symbol/decimals equal to Base per underlying, uniform authoriser
/// (this clone) and owner (this Safe), clean V4 beacon lineage.
///
/// See `docs/ETHEREUM_BOOTSTRAP.md` § 7 for where this sits in the runbook.
contract DeployTokensEthereum is Script {
    /// @notice Human-readable authorise-bundle name shown to Safe signers.
    string internal constant AUTHORIZE_BUNDLE_NAME = "ST0x tokens (Ethereum) - set authoriser on all vaults";

    /// @notice Output path for the authorise-bundle JSON artifact.
    string internal constant AUTHORIZE_ARTIFACT_PATH = "out/tokens-ethereum-authorize.json";

    /// @notice Assert a deployer contract is present at its pinned address.
    /// @param deployer The pinned deployer address.
    function _assertDeployer(address deployer) internal view {
        if (deployer.code.length == 0) revert DeployerNotDeployed(deployer);
    }

    /// @notice Deploy all 20 tokens on the active chain via the unified
    /// deployer, Safe-owned, matched to Base. EOA broadcast: reads
    /// `DEPLOYMENT_KEY`. Logs each deployed pair for the pin PR.
    function run() external {
        // The token-owner Safe is shared across chains (matched-address
        // deploy), so it is the same pin Base uses.
        address safe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;

        // Pre-flight: the unified deployer and both beacon-set deployers it
        // delegates to must be live at their pinned V4 addresses (bootstrap
        // step 1 broadcast the core suites here).
        address unifiedDeployer = LibProdDeployCurrent.STOX_UNIFIED_DEPLOYER;
        _assertDeployer(unifiedDeployer);
        _assertDeployer(LibProdDeployCurrent.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER);
        _assertDeployer(LibProdDeployCurrent.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER);

        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        uint256 deployerKey = vm.envUint("DEPLOYMENT_KEY");

        bytes32 deploymentTopic = keccak256("Deployment(address,address,address)");

        console2.log("Deploying", configs.length, "tokens on chain id", block.chainid);
        console2.log("initialAdmin (token-owner Safe):", safe);

        for (uint256 i = 0; i < configs.length; i++) {
            TokenConfig memory cfg = configs[i];
            OffchainAssetReceiptVaultConfigV2 memory vaultConfig = OffchainAssetReceiptVaultConfigV2({
                initialAdmin: safe,
                receiptVaultConfig: ReceiptVaultConfigV2({
                    asset: address(0), name: cfg.name, symbol: cfg.symbol, receipt: address(0)
                })
            });

            vm.recordLogs();
            vm.broadcast(deployerKey);
            IStoxUnifiedDeployerV1(unifiedDeployer).newTokenAndWrapperVault(vaultConfig);

            // Fish the deployed pair out of the unified deployer's
            // `Deployment(sender, asset, wrapper)` event so the operator can
            // hydrate the token table without re-deriving addresses.
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

            console2.log("==== TOKEN DEPLOYED ====");
            console2.log("underlying:", cfg.underlying);
            console2.log("receiptVault:", vm.toString(receiptVault));
            console2.log("wrappedTokenVault:", vm.toString(wrapped));
        }

        console2.log(
            "All tokens deployed. Hydrate LibTokenInvariants.productionTokensEthereum() from the logged pairs."
        );
    }

    /// @notice Assert the Ethereum V4 authoriser clone is deployed at its
    /// pin with the shared EIP-1167 codehash.
    /// @return clone The validated clone address.
    function _assertCloneReady() internal view returns (address clone) {
        clone = LibProdAuthoriserClones.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM;
        if (
            clone == address(0) || clone.code.length == 0
                || clone.codehash != LibProdAuthoriserClones.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH
        ) {
            revert EthereumCloneNotReady(clone);
        }
    }

    /// @notice Read the hydrated Ethereum receipt vaults, asserting the
    /// table is fully hydrated and every vault is Safe-owned (so the
    /// owner-gated `setAuthorizer` will not revert on execution).
    /// @param safe The Ethereum token-owner Safe.
    /// @return vaults The 20 receipt vault addresses.
    function _hydratedReceiptVaults(address safe) internal view returns (address[] memory vaults) {
        TokenInstance[] memory tokens = LibTokenInvariants.productionTokensEthereum();
        vaults = new address[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            address vault = tokens[i].receiptVault;
            if (vault == address(0) || vault.code.length == 0) revert EthereumTokenTableNotHydrated();
            address owner = IOwnable(vault).owner();
            if (owner != safe) revert VaultNotOwnedBySafe(vault, safe, owner);
            vaults[i] = vault;
        }
    }

    /// @notice Build the canonical `setAuthorizer(clone)` bundle for the
    /// supplied vaults. Factored out so `authorizeTokens()` and `verify()`
    /// author byte-identical bundles.
    /// @param vaults The receipt vaults to authorise.
    /// @param clone The Ethereum V4 authoriser clone.
    /// @return txs The setAuthorizer transactions.
    function _buildAuthorizeTxs(address[] memory vaults, address clone) internal pure returns (SafeTx[] memory txs) {
        txs = new SafeTx[](vaults.length);
        for (uint256 i = 0; i < vaults.length; i++) {
            txs[i] = SafeTx({
                to: vaults[i], value: 0, data: abi.encodeCall(ISetAuthorizer.setAuthorizer, (clone)), operation: 0
            });
        }
    }

    /// @notice Author the Safe bundle that wires every Ethereum receipt
    /// vault onto the Ethereum V4 authoriser clone. Simulates each call and
    /// asserts the post-state, then emits the Tx Builder JSON + SafeTxHash.
    function authorizeTokens() external {
        IGnosisSafe safe = IGnosisSafe(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
        LibSafeInvariants.assertAll(safe);

        address clone = _assertCloneReady();
        address[] memory vaults = _hydratedReceiptVaults(address(safe));
        SafeTx[] memory txs = _buildAuthorizeTxs(vaults, clone);

        uint256 nonce = safe.nonce();
        bytes32 safeTxHash = LibSafeOps.computeMultiSendSafeTxHash(safe, txs, nonce);

        // Simulate each setAuthorizer via the Safe; nonce is not advanced.
        for (uint256 i = 0; i < txs.length; i++) {
            LibSafeOps.simulateExternalCall(safe, txs[i].to, txs[i].data);
        }

        // Post-state: every vault now points at the clone.
        for (uint256 i = 0; i < vaults.length; i++) {
            require(IAuthorisable(vaults[i]).authorizer() == clone, "post-state: vault.authorizer() != clone");
        }

        string memory json = LibSafeOps.emitTxBuilderJson(address(safe), block.chainid, AUTHORIZE_BUNDLE_NAME, txs);
        vm.writeFile(AUTHORIZE_ARTIFACT_PATH, json);

        console2.log("==== TX BUILDER JSON BEGIN ====");
        console2.log(json);
        console2.log("==== TX BUILDER JSON END ====");
        console2.log("SafeTxHash:", vm.toString(safeTxHash));
        console2.log("Nonce:", nonce);
    }

    /// @notice Re-run the authorise-bundle pre-flight and assert a
    /// pre-emitted artifact matches what the live pre-flight would author.
    /// Used by signers to confirm the artifact wasn't tampered with.
    /// @param jsonPath Filesystem path to the Tx Builder JSON to verify.
    function verify(string calldata jsonPath) external view {
        IGnosisSafe safe = IGnosisSafe(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);
        LibSafeInvariants.assertAll(safe);

        address clone = _assertCloneReady();
        address[] memory vaults = _hydratedReceiptVaults(address(safe));
        SafeTx[] memory expected = _buildAuthorizeTxs(vaults, clone);

        (uint256 parsedChainId, address parsedTo, SafeTx[] memory parsedTxs) = LibSafeOps.parseTxBuilderJson(jsonPath);
        if (parsedChainId != block.chainid) revert VerifyMismatch("chainId");
        if (parsedTxs.length != expected.length) revert VerifyMismatch("txCount");
        if (parsedTo != expected[0].to) revert VerifyMismatch("to");
        for (uint256 i = 0; i < expected.length; i++) {
            if (parsedTxs[i].to != expected[i].to) revert VerifyMismatch("to");
            if (parsedTxs[i].value != expected[i].value) revert VerifyMismatch("value");
            if (keccak256(parsedTxs[i].data) != keccak256(expected[i].data)) revert VerifyMismatch("data");
        }

        bytes32 liveHash = LibSafeOps.computeMultiSendSafeTxHash(safe, expected, safe.nonce());
        bytes32 artifactHash = LibSafeOps.computeMultiSendSafeTxHash(safe, parsedTxs, safe.nonce());
        if (liveHash != artifactHash) revert VerifyMismatch("safeTxHash");
    }
}
