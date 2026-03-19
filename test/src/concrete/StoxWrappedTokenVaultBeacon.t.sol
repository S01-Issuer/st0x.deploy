// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {LibRainDeploy} from "rain.deploy/lib/LibRainDeploy.sol";
import {StoxWrappedTokenVault} from "../../../src/concrete/StoxWrappedTokenVault.sol";
import {StoxWrappedTokenVaultBeacon} from "../../../src/concrete/StoxWrappedTokenVaultBeacon.sol";
import {LibProdDeployV1} from "../../../src/lib/LibProdDeployV1.sol";
import {LibProdDeployV2} from "../../../src/lib/LibProdDeployV2.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract StoxWrappedTokenVaultBeaconTest is Test {
    /// Beacon deploys via Zoltu with correct implementation and owner.
    function testBeaconConstructsWithExpectedConstants() external {
        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(type(StoxWrappedTokenVault).creationCode);
        address beacon = LibRainDeploy.deployZoltu(type(StoxWrappedTokenVaultBeacon).creationCode);

        assertEq(beacon, LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT_BEACON);
        assertEq(StoxWrappedTokenVaultBeacon(beacon).implementation(), LibProdDeployV2.STOX_WRAPPED_TOKEN_VAULT);
        assertEq(Ownable(beacon).owner(), LibProdDeployV2.BEACON_INITIAL_OWNER);
    }

    /// BEACON_INITIAL_OWNER is the same across V1 and V2.
    function testBeaconInitialOwnerConsistentAcrossVersions() external pure {
        assertEq(LibProdDeployV1.BEACON_INITIAL_OWNER, LibProdDeployV2.BEACON_INITIAL_OWNER);
    }
}
