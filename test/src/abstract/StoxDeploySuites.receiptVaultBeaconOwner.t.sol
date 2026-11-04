// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {LibProdDeployCurrent} from "../../../src/generated/LibProdDeployCurrent.sol";
import {LibProdDeployV4 as V4} from "../../../src/generated/LibProdDeployV4.sol";
import {StoxReceiptVaultBeacon} from "../../../src/concrete/StoxReceiptVaultBeacon.sol";
import {RegistryOwnedBeaconSuiteTest} from "./RegistryOwnedBeaconSuiteTest.sol";

contract StoxDeploySuitesReceiptVaultBeaconOwnerTest is RegistryOwnedBeaconSuiteTest {
    function suiteKey() internal pure override returns (string memory) {
        return RECEIPT_VAULT_BEACON;
    }

    function pin() internal pure override returns (address) {
        return V4.STOX_RECEIPT_VAULT_BEACON_CANDIDATE;
    }

    function implementation() internal pure override returns (address) {
        return LibProdDeployCurrent.STOX_RECEIPT_VAULT;
    }

    function construct() internal override {
        new StoxReceiptVaultBeacon();
    }
}
