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

/// @dev Local mirror of the receipt-vault `setAuthorizer(IAuthorizeV1)`
/// owner-gated selector. rain-vats ships no interface carrying it (it lives
/// only on the concrete `OffchainAssetReceiptVault`), and importing the
/// concrete would drag its full storage inheritance into this script just to
/// encode one selector — the same trade the 20260623 swap script makes. The
/// vault's other two admin surfaces come from canonical homes: `receipt()`
/// via rain-vats `IReceiptVaultV3`, `transferOwnership` via OZ `Ownable`.
interface ISetAuthorizer {
    function setAuthorizer(IAuthorizeV1 newAuthorizer) external;
}

/// @notice Pre-flight failed: a required deployer contract has no runtime
/// code at its pinned V4 address on the active fork — the core V4 suites
/// have not been broadcast to this chain yet (bootstrap step 1).
/// @param deployer The pinned deployer address that is missing.
error DeployerNotDeployed(address deployer);

/// @notice Pre-flight failed: the pinned Ethereum V4 authoriser clone is
/// still `address(0)` / has no code / has the wrong codehash. A token cannot
/// be wired onto a clone that isn't the pinned, deployed one.
/// @param clone The clone address inspected.
error EthereumCloneNotReady(address clone);

/// @notice Pre-flight failed: the active chain's resolved token-owner Safe is
/// not the pinned ETHEREUM Safe. Either the script was dispatched against a
/// network other than Ethereum mainnet (this script deploys the Ethereum
/// token set only), or the Ethereum pin
/// (`LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM`) has not landed.
/// @param safe The Safe address the active chain resolved to.
error EthereumSafeNotReady(address safe);

/// @title DeployTokensEthereum
/// @notice **PENDING.** Deploys the full ST0x production token set on Ethereum
/// mainnet, matched to Base, wires each vault onto the V4 authoriser
/// clone, and hands ownership to the token-owner Safe — all in a single
/// deploy-key broadcast, no Safe signature. Flips to `**EXECUTED YYYY-MM-DD.**`
/// in the post-execution pin PR.
/// @dev Single operation (`run()`), broadcast from the CI deploy key via
/// `manual-broadcast.yaml`. Mirrors the authoriser-clone deploy pattern: the
/// deploy key deploys, configures, then self-relinquishes — the Safe signs
/// nothing. Per token, in order:
///
///   1. `StoxUnifiedDeployer.newTokenAndWrapperVault` with `initialAdmin` =
///      the deploy key and the `name`/`symbol` from `LibProdTokenConfig` (the
///      canonical table captured verbatim from Base). Deploys the receipt
///      (ERC-1155) + receipt vault + wrapped vault beacon-proxy triple; the
///      deploy key owns the receipt vault at this point. (The receipt and the
///      wrapped vault have no owner.)
///   2. `setAuthorizer(clone)` on the receipt vault — allowed because the
///      deploy key is (transiently) the owner. Until this lands a fresh vault
///      is self-authorised and every op reverts, exactly as on Base.
///   3. `transferOwnership(safe)` on the receipt vault — single-step OZ
///      `Ownable`, so ownership lands on the Safe with no accept step. After
///      this the deploy key holds nothing.
///
/// The deterministic addresses are NOT known ahead of the broadcast (the
/// beacon-set deployer uses nonce-based clones), so the script logs each
/// deployed `(underlying, receipt, receiptVault, wrapped)` for the
/// post-execution pin PR to hydrate
/// `LibTokenInvariants.productionTokensEthereum()`. Pre-flight
/// requires the clone (step 2 target) and the Safe (step 3 target) both live,
/// so the ordering — Safe out-of-band, then clone, then tokens — is enforced.
///
/// After execution the cross-chain parity pin (`StoxCrossChainParity.t.sol`)
/// is the acceptance test: name/symbol equal to the canonical config
/// per underlying, uniform authoriser (this clone) and owner (this Safe).
contract DeployTokensEthereum is Script {
    /// @notice Assert a deployer contract is present at its pinned address.
    /// @param deployer The pinned deployer address.
    function _assertDeployer(address deployer) internal view {
        if (deployer.code.length == 0) revert DeployerNotDeployed(deployer);
    }

    /// @notice The active chain's token-owner Safe, resolved + policy-asserted
    /// through the shared entry point (`assertActiveChainTokenOwnerSafe` — the
    /// identical assertion the scheduled CI pin runs per chain), then guarded
    /// to be ETHEREUM's Safe: this script deploys the Ethereum token set, so
    /// a dispatch against any other network's RPC must revert rather than
    /// deploy duplicate tokens onto that chain.
    /// @return safe The validated Ethereum token-owner Safe address.
    function _assertSafeReady() internal view returns (address safe) {
        safe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        if (safe != LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM) {
            revert EthereumSafeNotReady(safe);
        }
    }

    /// @notice Assert the Ethereum V4 authoriser clone is deployed at its pin
    /// with the shared EIP-1167 codehash.
    /// @return clone The validated clone address.
    function _assertCloneReady() internal view returns (address clone) {
        clone = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM;
        if (
            clone == address(0) || clone.code.length == 0
                || clone.codehash != LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH
        ) {
            revert EthereumCloneNotReady(clone);
        }
    }

    /// @notice Deploy every production token on the active chain via the
    /// unified deployer, wire each onto the V4 authoriser clone, and hand
    /// ownership to the Safe — one deploy-key broadcast, matched to Base.
    /// Broadcasts as the key `manual-broadcast.yaml` supplies via
    /// `--private-key` (the same CI deploy key every operational broadcast
    /// uses). Logs each deployed pair for the pin PR.
    function run() external {
        // Pre-flight: the unified deployer + both beacon-set deployers it
        // delegates to must be live at their pinned addresses. The 0.1.1
        // pins, NOT `LibProdDeployCurrent`: Ethereum's bootstrap shipped the
        // audited 0.1.1 set, and the 0.1.1 unified deployer is what wires
        // new vault proxies onto the chain's IN-USE production beacons (the
        // 0.1.1 set pinned via `LibProdBeaconsEthereum` /
        // `LibBeaconInvariants`). The current tag's deployer is a different
        // Zoltu address that (a) is not deployed on Ethereum and (b) would
        // wire tokens onto a different, unadopted beacon set even if it were.
        address unifiedDeployer = LibProdDeployV4.STOX_UNIFIED_DEPLOYER_0_1_1;
        _assertDeployer(unifiedDeployer);
        _assertDeployer(LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1);
        _assertDeployer(LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_0_1_1);

        // Pre-flight: the chain's IN-USE production beacons — the beacons
        // every vault proxy created below will delegate through — are owned
        // by this chain's token-owner Safe. A beacon owned by anything else
        // could be repointed under the new tokens. The same assertion the
        // per-chain prod pin (`StoxProdV4`) runs on every CI commit.
        LibBeaconInvariants.assertProdBeaconsOwnedByChainSafe(block.chainid);

        // The clone (setAuthorizer target) and the Safe (ownership-handoff
        // target) must both be live before we deploy, since each token is fully
        // wired in this same broadcast.
        address clone = _assertCloneReady();
        address safe = _assertSafeReady();

        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();

        bytes32 deploymentTopic = keccak256("Deployment(address,address,address)");

        vm.startBroadcast();

        // Deployer identity — inside `vm.startBroadcast()` msg.sender
        // resolves to the broadcast address (`--private-key` in production,
        // supplied by `manual-broadcast.yaml`). Captured so the
        // `initialAdmin` baked into each vault's config lines up with the
        // key that then calls `setAuthorizer` + `transferOwnership`.
        address deployer = msg.sender;

        console2.log("Deploying", configs.length, "tokens on chain id", block.chainid);
        console2.log("initialAdmin (deploy key, handed to Safe):", deployer);
        console2.log("token-owner Safe:", safe);
        console2.log("V4 authoriser clone:", clone);

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

            // Wire onto the clone (deploy key is still owner), then relinquish
            // ownership to the Safe. Order matters: `setAuthorizer` is
            // `onlyOwner`, so it must precede the handoff. Only the receipt
            // vault is ownable — the receipt and wrapped vault have no owner,
            // so nothing to hand off for those.
            ISetAuthorizer(receiptVault).setAuthorizer(IAuthorizeV1(clone));
            Ownable(receiptVault).transferOwnership(safe);

            console2.log("==== TOKEN DEPLOYED ====");
            console2.log("underlying:", cfg.underlying);
            console2.log("receipt (ERC-1155):", vm.toString(receipt));
            console2.log("receiptVault:", vm.toString(receiptVault));
            console2.log("wrappedTokenVault:", vm.toString(wrapped));
        }

        vm.stopBroadcast();

        console2.log(
            "All tokens deployed, authorised, and handed to the Safe. Hydrate"
            " LibTokenInvariants.productionTokensEthereum() from the logged pairs."
        );
    }
}
