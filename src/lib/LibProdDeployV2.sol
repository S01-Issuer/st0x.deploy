// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title LibProdDeployV2
/// @notice V2 production deployment addresses and codehashes, hardcoded to
/// match what is actually deployed on-chain via the Zoltu deterministic
/// deployer. These values are an audit trail — do not update them.
/// For current (undeployed) code, see LibProdDeployV3.
library LibProdDeployV2 {
    /// @dev The initial owner for all V2 beacons. Resolves to rainlang.eth.
    address constant BEACON_INITIAL_OWNER = address(0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b);

    address constant STOX_RECEIPT = address(0xbAB0E6b7B5dDA86FB8ba81c00aEA0Ceb8b73686b);
    bytes32 constant STOX_RECEIPT_CODEHASH =
        bytes32(0x14348054f718979709402d1892155361f5ea99d8e7267823fcac9c7763bcefab);

    address constant STOX_RECEIPT_VAULT = address(0xc95dB340A7a100881626475d41BFf70857Aa920D);
    bytes32 constant STOX_RECEIPT_VAULT_CODEHASH =
        bytes32(0x6147eafd814bc0154f4a6b8247b8c092580fa2e0356e81e4422cfebc2ee94ebb);

    address constant STOX_WRAPPED_TOKEN_VAULT = address(0xb438a1eA1550fd199d67D67a69B71F4324bB8660);
    bytes32 constant STOX_WRAPPED_TOKEN_VAULT_CODEHASH =
        bytes32(0xe27ea554b311e0be917e5562ac279eb6e035dd86427b1a2427b66d5e8da5f031);

    address constant STOX_UNIFIED_DEPLOYER = address(0xeaE1c37b7aD1643D20da2B1b97705Fa949eAFaE7);
    bytes32 constant STOX_UNIFIED_DEPLOYER_CODEHASH =
        bytes32(0xf66db64c4830ba82f948d38aa8eeed0fb013b2c78e7bad9dac6f051ea24d3056);

    address constant STOX_WRAPPED_TOKEN_VAULT_BEACON = address(0x846a468e6fDA529D282D60df7D1EE785EB954600);
    bytes32 constant STOX_WRAPPED_TOKEN_VAULT_BEACON_CODEHASH =
        bytes32(0x8e95867e52db417944afd90f3b6c3c980962831e8a944e7f6958ba8f8cc10630);

    address constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER =
        address(0x0C5154C4861908Bd5a6FD6fFCB063e9869ceFa41);
    bytes32 constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CODEHASH =
        bytes32(0x4cab65f32a2ff27c29808ddd2f0ef935ee679028b92afbbcaf491d6ff3c73ea7);

    address constant STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER = address(0xBFB3D7Baece65D1f1640986CdA313177F1160C70);
    bytes32 constant STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_CODEHASH =
        bytes32(0x74242aadf35ad5abe3c4ce31caa8532f606988fcbff8bcecf9fab91c4966045a);

    address constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1 =
        address(0x667d2Ab75908c7d7983008aDbF558332F381a5f5);
    bytes32 constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CODEHASH =
        bytes32(0xc35b1e63fac46e869fa736e9793e5378f774b1568f9ca56c0f358b17fc12ecd0);

    address constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1 =
        address(0x72b2a394E129ede556b4024aCe939a964bA0a876);
    bytes32 constant STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_PAYMENT_MINT_AUTHORIZER_V1_CODEHASH =
        bytes32(0xd71cc144cb671b6eeece0598e613ddc712c059e6448857bdeaec58f188cbbba8);
}
