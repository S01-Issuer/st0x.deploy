// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    OffchainAssetReceiptVaultBeaconSetDeployer,
    OffchainAssetReceiptVaultConfigV2,
    OffchainAssetReceiptVault
} from "rain-vats-0.1.6/src/concrete/deploy/OffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {IERC165} from "@openzeppelin-contracts-5.6.1/utils/introspection/IERC165.sol";
import {StoxWrappedTokenVaultBeaconSetDeployer} from "./StoxWrappedTokenVaultBeaconSetDeployer.sol";
import {ST0xOrchestratorBeaconSetDeployer} from "./ST0xOrchestratorBeaconSetDeployer.sol";
import {LibProdDeployV4} from "../../lib/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../lib/LibSafeInvariants.sol";
import {StoxWrappedTokenVault} from "../StoxWrappedTokenVault.sol";
import {IStoxUnifiedDeployerV1} from "../../interface/IStoxUnifiedDeployerV1.sol";

/// @title StoxUnifiedDeployer
/// @notice Deploys an OffchainAssetReceiptVault, a StoxWrappedTokenVault
/// linked to it, and an ST0xOrchestrator clone bound to the OARV —
/// atomically, in a single transaction. Every downstream address
/// (beacon-set-deployers + orchestrator owner) is hardcoded here to keep the
/// audit trail in git.
///
/// The orchestrator is owned by `LibSafeInvariants.STOX_TOKEN_OWNER_SAFE`
/// (the same Safe that owns the tokens), so the token-owner multisig gains
/// a mint/burn policy handle at deploy time — no separate ops step to wire
/// it up.
contract StoxUnifiedDeployer is IERC165, IStoxUnifiedDeployerV1 {
    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IStoxUnifiedDeployerV1).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /// Emitted when a new OARV / StoxWrappedTokenVault / ST0xOrchestrator
    /// triple is deployed.
    /// @param sender The address that initiated the deployment.
    /// @param asset The deployed OffchainAssetReceiptVault.
    /// @param wrapper The deployed StoxWrappedTokenVault (asset-linked).
    /// @param orchestrator The deployed ST0xOrchestrator clone
    /// (asset-linked). Owner is `STOX_TOKEN_OWNER_SAFE`.
    event Deployment(address sender, address asset, address wrapper, address orchestrator);

    /// @notice Deploys an OARV, a StoxWrappedTokenVault linked to it, and an
    /// ST0xOrchestrator clone bound to the same OARV. All three happen in
    /// one transaction; a partial deploy is not possible.
    /// @dev Reentrancy is not exploitable here because this contract is
    /// entirely stateless — no storage, no balances. A reentrant call would
    /// just create another independent triple.
    /// @param config The configuration for the OARV. The resulting asset
    /// address is used to deploy the wrapper and the orchestrator.
    // slither-disable-next-line reentrancy-events
    function newTokenAndWrapperVault(OffchainAssetReceiptVaultConfigV2 memory config) external {
        OffchainAssetReceiptVault asset = OffchainAssetReceiptVaultBeaconSetDeployer(
                LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_RAIN_VATS_0_1_6
            ).newOffchainAssetReceiptVault(config);
        StoxWrappedTokenVault wrappedTokenVault = StoxWrappedTokenVaultBeaconSetDeployer(
                LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_RAIN_VATS_0_1_6
            ).newStoxWrappedTokenVault(address(asset));
        address orchestrator = ST0xOrchestratorBeaconSetDeployer(
                LibProdDeployV4.STOX_ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_RAIN_VATS_0_1_6
            ).deploy(asset, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE);

        emit Deployment(msg.sender, address(asset), address(wrappedTokenVault), orchestrator);
    }
}
