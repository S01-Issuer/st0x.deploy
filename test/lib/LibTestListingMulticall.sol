// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {IMulticall3} from "forge-std-1.17.0/src/interfaces/IMulticall3.sol";
import {ICloneableFactoryV7} from "rain-factory-0.2.11/src/interface/ICloneableFactoryV7.sol";
import {RegistryBeaconProxyParams} from "rain-factory-0.2.11/src/lib/LibRainDeployRegistryBeaconProxy.sol";

import {IStoxListingV1} from "../../src/interface/IStoxListingV1.sol";
import {ListingRow} from "../../src/lib/LibListingTree.sol";

/// @dev The canonical Multicall3, at the same address on every chain that has it.
address constant MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;

/// @dev The runtime code hash of the canonical Multicall3.
bytes32 constant MULTICALL3_CODEHASH = 0xd5c15df687b16f2ff992fc8d767b4216323184a2bbc6ee2f9c398c318e770891;

/// @title LibTestListingMulticall
/// @notice The Multicall3 `aggregate3` calls that deploy a V6 token and name it from its listing in one transaction.
library LibTestListingMulticall {
    /// @notice The factory call that deploys the token, then its `nameListing`; neither may fail.
    /// @param params The token's registry beacon proxy params.
    /// @param row The token's listing row.
    /// @param proof The row's proof.
    /// @param root The listing root.
    /// @param signature The listing signer's signature over the root.
    /// @return The calls.
    function deployAndName(
        RegistryBeaconProxyParams memory params,
        ListingRow memory row,
        bytes32[] memory proof,
        bytes32 root,
        bytes memory signature
    ) internal pure returns (IMulticall3.Call3[] memory) {
        IMulticall3.Call3[] memory calls = new IMulticall3.Call3[](2);
        calls[0] = IMulticall3.Call3({
            target: params.factory,
            allowFailure: false,
            callData: abi.encodeCall(
                ICloneableFactoryV7.registryBeaconProxy,
                (params.registry, params.authority, params.beaconName, params.data, params.salt)
            )
        });
        calls[1] = name(row, proof, root, signature);
        return calls;
    }

    /// @notice The token's `nameListing` call, which may not fail.
    /// @param row The token's listing row.
    /// @param proof The row's proof.
    /// @param root The listing root.
    /// @param signature The listing signer's signature over the root.
    /// @return The call.
    function name(ListingRow memory row, bytes32[] memory proof, bytes32 root, bytes memory signature)
        internal
        pure
        returns (IMulticall3.Call3 memory)
    {
        return IMulticall3.Call3({
            target: row.token,
            allowFailure: false,
            callData: abi.encodeCall(
                IStoxListingV1.nameListing, (row.assetId, row.ticker, row.name, proof, root, signature)
            )
        });
    }
}
