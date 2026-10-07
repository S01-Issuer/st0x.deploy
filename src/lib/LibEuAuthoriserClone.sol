// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibICloneableFactoryV4} from "rain-factory-0.1.30/src/lib/LibICloneableFactoryV4.sol";
import {LibCloneFactoryDeploy} from "rain-factory-deploy-0.1.15/src/lib/LibCloneFactoryDeploy.sol";
import {
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.2.4/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";

import {LibProdDeployV4} from "../generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "./LibSafeInvariants.sol";

// The open salt for the EU assets authoriser. Open rather than namespaced so
// the digest covers the implementation and the init data and NOT the caller:
// one address on every network, and a frontrunner can only deploy the clone we
// specified.
bytes32 constant EU_AUTHORISER_SALT = keccak256("st0x.eu-assets-authoriser");

/// @title LibEuAuthoriserClone
/// @notice Every derived fact about the EU assets authoriser clone, each
/// computed by `rain-factory`'s own derivation rather than restated here.
///
/// The clone proxies the audited 0.1.1 authoriser pinned in `LibProdDeployV4`.
/// Its init data is the initial admin alone — the minter is role state granted
/// afterwards — so changing the minter cannot move the address.
library LibEuAuthoriserClone {
    /// @notice The implementation the clone delegates into.
    /// @return The audited 0.1.1 authoriser.
    function implementation() internal pure returns (address) {
        return LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1;
    }

    /// @notice The init data, and so half the open-salt digest.
    /// @return The `abi.encode`d config: the token-owner Safe as initial admin.
    function cloneData() internal pure returns (bytes memory) {
        return abi.encode(
            OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: LibSafeInvariants.STOX_TOKEN_OWNER_SAFE})
        );
    }

    /// @notice The clone's creation code — the EIP-1167 initcode the factory
    /// assembles, from the factory's own helper so this repo carries no second
    /// spelling of the proxy layout.
    /// @return The creation code.
    function cloneCreationCode() internal pure returns (bytes memory) {
        return LibICloneableFactoryV4.cloneCreationCode(implementation());
    }

    /// @notice The clone's runtime code: the creation code's tail, which is
    /// what `CREATE2` leaves on chain. The implementation address is embedded
    /// in it, so a matching code hash proves which implementation the clone
    /// delegates into — which is why the implementation needs no separate
    /// dependency entry.
    /// @return The runtime code.
    function cloneRuntimeCode() internal pure returns (bytes memory) {
        bytes memory creation = cloneCreationCode();
        // The EIP-1167 initcode is a 10-byte copy-and-return prefix followed
        // by the 45-byte runtime it returns.
        bytes memory runtime = new bytes(creation.length - 10);
        for (uint256 i = 0; i < runtime.length; i++) {
            runtime[i] = creation[i + 10];
        }
        return runtime;
    }

    /// @notice The address the clone lands at, on every network.
    /// @return The predicted clone address.
    function cloneDeployedAddress() internal pure returns (address) {
        return LibICloneableFactoryV4.predictCloneAddress(
            LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS,
            implementation(),
            LibICloneableFactoryV4.effectiveOpenSalt(EU_AUTHORISER_SALT, cloneData())
        );
    }

    /// @notice The code hash the clone reports once deployed.
    /// @return `keccak256` of the runtime code.
    function cloneDeployedCodehash() internal pure returns (bytes32) {
        return keccak256(cloneRuntimeCode());
    }
}
