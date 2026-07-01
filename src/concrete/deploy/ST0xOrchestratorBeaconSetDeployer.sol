// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin-contracts-5.6.1/proxy/beacon/BeaconProxy.sol";
import {IERC165} from "@openzeppelin-contracts-5.6.1/utils/introspection/IERC165.sol";

import {OffchainAssetReceiptVault} from "rain-vats-0.1.6/src/concrete/vault/OffchainAssetReceiptVault.sol";

import {ST0xOrchestrator} from "../ST0xOrchestrator.sol";

/// Thrown when the deployer is constructed with `initialOwner == address(0)`.
error ZeroInitialOwner();

/// Thrown when the deployer is constructed with a zero implementation
/// address for the orchestrator.
error ZeroOrchestratorImplementation();

/// Thrown when `deploy` is called with `vault == address(0)`.
error ZeroVault();

/// Thrown when `deploy` is called with `owner == address(0)`.
error ZeroOwner();

/// Configuration for `ST0xOrchestratorBeaconSetDeployer` construction.
/// @param initialOwner Owner of the internal `UpgradeableBeacon`. In
/// production this is the owner multisig.
/// @param initialOrchestratorImplementation Implementation contract the
/// beacon initially points at.
struct ST0xOrchestratorBeaconSetDeployerConfig {
    address initialOwner;
    address initialOrchestratorImplementation;
}

/// @title ST0xOrchestratorBeaconSetDeployer
/// @notice Mints per-token `ST0xOrchestrator` clones as `BeaconProxy`
/// instances, all pointing at a shared beacon owned by the initial owner
/// multisig. A single beacon upgrade rolls every orchestrator forward at
/// once — matching how the tokens themselves are versioned.
///
/// Zoltu-friendly: the constructor takes no dynamic input; the config is
/// hardcoded on the Stox subclass via `LibProdDeployV*` constants.
contract ST0xOrchestratorBeaconSetDeployer is IERC165 {
    /// Emitted when a new `ST0xOrchestrator` clone is deployed.
    /// @param sender The address that called `deploy`.
    /// @param orchestrator Address of the newly deployed orchestrator proxy.
    /// @param vault The receipt vault the orchestrator is bound to.
    event Deployment(address indexed sender, address indexed orchestrator, address indexed vault);

    /// The beacon every deployed orchestrator proxy points at.
    IBeacon public immutable iOrchestratorBeacon;

    constructor(ST0xOrchestratorBeaconSetDeployerConfig memory config) {
        if (config.initialOwner == address(0)) revert ZeroInitialOwner();
        if (config.initialOrchestratorImplementation == address(0)) revert ZeroOrchestratorImplementation();

        iOrchestratorBeacon = new UpgradeableBeacon(config.initialOrchestratorImplementation, config.initialOwner);
    }

    /// @notice Deploy a fresh `ST0xOrchestrator` clone bound to `vault_` and
    /// owned by `owner`. Callable by anyone — no auth on the deployer; the
    /// per-clone owner is what governs the clone. Idempotence and per-vault
    /// deduplication are the caller's responsibility.
    function deploy(OffchainAssetReceiptVault vault_, address owner) external returns (address) {
        if (address(vault_) == address(0)) revert ZeroVault();
        if (owner == address(0)) revert ZeroOwner();

        bytes memory initData = abi.encodeCall(ST0xOrchestrator.initialize, (vault_, owner));
        BeaconProxy proxy = new BeaconProxy(address(iOrchestratorBeacon), initData);

        emit Deployment(msg.sender, address(proxy), address(vault_));
        return address(proxy);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}
