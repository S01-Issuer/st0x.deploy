// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {LibProdDeployCurrent} from "../../../src/generated/LibProdDeployCurrent.sol";
import {LibProdDeployV4 as V4} from "../../../src/generated/LibProdDeployV4.sol";
import {StoxWrappedTokenVaultBeacon} from "../../../src/concrete/StoxWrappedTokenVaultBeacon.sol";
import {RegistryOwnedBeaconSuiteTest} from "./RegistryOwnedBeaconSuiteTest.sol";

contract StoxDeploySuitesWrappedTokenVaultBeaconOwnerTest is RegistryOwnedBeaconSuiteTest {
    function suiteKey() internal pure override returns (string memory) {
        return WRAPPED_TOKEN_VAULT_BEACON;
    }

    function pin() internal pure override returns (address) {
        return V4.STOX_WRAPPED_TOKEN_VAULT_BEACON_CANDIDATE;
    }

    function implementation() internal pure override returns (address) {
        return LibProdDeployCurrent.STOX_WRAPPED_TOKEN_VAULT;
    }

    function construct() internal override {
        new StoxWrappedTokenVaultBeacon();
    }
}
