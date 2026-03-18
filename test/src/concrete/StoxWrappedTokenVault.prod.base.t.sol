// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {LibProdDeployV1} from "../../../src/lib/LibProdDeployV1.sol";
import {LibTestProd} from "../../lib/LibTestProd.sol";
import {IBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol";
import {BeaconProxy} from "openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";
import {ICLONEABLE_V2_SUCCESS} from "rain.factory/interface/ICloneableV2.sol";

/// @title StoxWrappedTokenVaultV1ProdBaseTest
/// @notice Demonstrates that V1 on-chain StoxWrappedTokenVault accepts
/// address(0) as an asset without reverting. This is the vulnerability that
/// V2 fixes with the ZeroAsset check.
contract StoxWrappedTokenVaultV1ProdBaseTest is Test {
    /// V1 on-chain StoxWrappedTokenVault allows initializing with address(0)
    /// as the asset. This creates a bricked vault. V2 reverts with ZeroAsset.
    function testProdV1ZeroAssetDoesNotRevert() external {
        LibTestProd.createSelectForkBase(vm);

        // Get the beacon from the on-chain deployer using the V1 selector.
        (bool ok, bytes memory beaconData) = LibProdDeployV1
            .STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER
            .staticcall(abi.encodeWithSignature("I_STOX_WRAPPED_TOKEN_VAULT_BEACON()"));
        assertTrue(ok, "beacon call failed");
        address beacon = abi.decode(beaconData, (address));

        // Create a fresh proxy pointing to the V1 beacon.
        BeaconProxy proxy = new BeaconProxy(beacon, "");

        // Initialize with address(0) — this succeeds on V1 (no ZeroAsset
        // check), creating a bricked vault.
        (bool initOk, bytes memory initData) = address(proxy).call(
            abi.encodeWithSignature("initialize(bytes)", abi.encode(address(0)))
        );
        assertTrue(initOk, "V1 initialize with zero address should not revert");
        bytes32 result = abi.decode(initData, (bytes32));
        assertEq(result, ICLONEABLE_V2_SUCCESS);
    }
}
