// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

library LibProdDeploy {
    /// rainlang.eth
    address constant BEACON_INIITAL_OWNER = address(0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b);

    /// https://basescan.org/address/0x2191981ca2477b745870cc307cbeb4cb2967ace3
    address constant OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER =
        address(0x2191981Ca2477B745870cC307cbEB4cB2967ACe3);

    /// https://basescan.org/address/0xef6f9d21ed2e2742bfd3dfcf67829e4855884fab
    address constant STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER = address(0xeF6f9D21ED2E2742bfd3dFcf67829e4855884faB);

    /// https://basescan.org/address/0x80A79767F2d7c24A0577f791eC2Af74a7c9A1eD1#code
    address constant STOX_WRAPPED_TOKEN_VAULT = address(0x80A79767F2d7c24A0577f791eC2Af74a7c9A1eD1);
}
