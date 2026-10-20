// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {IAuthorizeV1} from "rain-vats-0.2.5/src/interface/IAuthorizeV1.sol";

/// @notice The unified deployer emitted no `Deployment` event, so there is no
/// address to wire or hand over. Named rather than left to fault on a zero
/// address, because it happens mid-broadcast with earlier tokens already live.
/// @param underlying The token whose deployment could not be resolved.
error DeploymentEventMissing(string underlying);

/// @notice A freshly deployed vault did not end up owned by its intended owner.
/// @param receiptVault The vault whose handoff did not land.
/// @param expected The owner ownership was meant to land on.
/// @param actual The owner actually read back.
error OwnershipHandoffFailed(address receiptVault, address expected, address actual);

/// @notice A freshly deployed vault is not routed to its authoriser. Until
/// `setAuthorizer` lands, every operation on the vault reverts.
/// @param receiptVault The vault whose authoriser did not land.
/// @param expected The authoriser it must route to.
/// @param actual The authoriser actually read back.
error AuthoriserNotWired(address receiptVault, address expected, address actual);

/// @dev The receipt-vault `setAuthorizer(IAuthorizeV1)` owner-gated selector.
/// rain-vats ships no interface carrying it.
interface ISetAuthorizer {
    function setAuthorizer(IAuthorizeV1 newAuthorizer) external;
    function authorizer() external view returns (address);
}

/// @title LibTokenDeployment
/// @notice What the token-deploy scripts share: resolving the pair the unified
/// deployer created, and asserting the vault ended wired and handed over.
library LibTokenDeployment {
    bytes32 internal constant DEPLOYMENT_TOPIC = keccak256("Deployment(address,address,address)");

    /// @notice Resolve the deployed pair out of the unified deployer's
    /// `Deployment(sender, asset, wrapper)` event. Logs from other emitters, and
    /// other events from the deployer, are ignored.
    /// @param logs The logs recorded across the deploy call.
    /// @param unifiedDeployer The deployer whose event is authoritative.
    /// @param underlying The token being deployed, for the revert.
    function readDeployment(Vm.Log[] memory logs, address unifiedDeployer, string memory underlying)
        internal
        pure
        returns (address receiptVault, address wrapped)
    {
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter == unifiedDeployer && logs[i].topics.length > 0 && logs[i].topics[0] == DEPLOYMENT_TOPIC
            ) {
                (, receiptVault, wrapped) = abi.decode(logs[i].data, (address, address, address));
            }
        }
        if (receiptVault == address(0)) {
            revert DeploymentEventMissing(underlying);
        }
    }

    /// @notice Assert a deployed vault is wired to `expectedAuthoriser` and
    /// owned by `expectedOwner`.
    function assertHandoffLanded(address receiptVault, address expectedAuthoriser, address expectedOwner)
        internal
        view
    {
        address wiredAuthoriser = ISetAuthorizer(receiptVault).authorizer();
        if (wiredAuthoriser != expectedAuthoriser) {
            revert AuthoriserNotWired(receiptVault, expectedAuthoriser, wiredAuthoriser);
        }
        address landedOwner = Ownable(receiptVault).owner();
        if (landedOwner != expectedOwner) {
            revert OwnershipHandoffFailed(receiptVault, expectedOwner, landedOwner);
        }
    }
}
