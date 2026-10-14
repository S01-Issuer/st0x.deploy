// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {ReceiptVault} from "rain-vats-0.2.4/src/abstract/ReceiptVault.sol";

import {IST0xOrchestratorV1} from "../interface/IST0xOrchestratorV1.sol";
import {LibBeaconInvariants} from "./LibBeaconInvariants.sol";

/// @title LibVaultLogicLock
/// @notice Version lock between a token and the vault + receipt logic its
/// caller was built against, resolved against this chain's production beacons.
library LibVaultLogicLock {
    /// @notice Revert unless `token` and its receipt are production proxies on
    /// this chain and their beacons serve `expectedVaultImpl` and
    /// `expectedReceiptImpl`.
    function checkToken(address token, address expectedVaultImpl, address expectedReceiptImpl) internal view {
        address[4] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(block.chainid);
        bytes32[2] memory proxyCodehashes = LibBeaconInvariants.prodProxyCodehashesForChainId(block.chainid);

        bytes32 expectedCodehash = proxyCodehashes[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX];
        if (token.codehash != expectedCodehash) {
            revert IST0xOrchestratorV1.VaultProxyCodehashMismatch(token, expectedCodehash, token.codehash);
        }
        address vaultImpl = IBeacon(beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX]).implementation();
        if (vaultImpl != expectedVaultImpl) {
            revert IST0xOrchestratorV1.VaultLogicMismatch(expectedVaultImpl, vaultImpl);
        }

        address receipt = address(ReceiptVault(payable(token)).receipt());
        expectedCodehash = proxyCodehashes[LibBeaconInvariants.RECEIPT_BEACON_INDEX];
        if (receipt.codehash != expectedCodehash) {
            revert IST0xOrchestratorV1.ReceiptProxyCodehashMismatch(receipt, expectedCodehash, receipt.codehash);
        }
        address receiptImpl = IBeacon(beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX]).implementation();
        if (receiptImpl != expectedReceiptImpl) {
            revert IST0xOrchestratorV1.ReceiptLogicMismatch(expectedReceiptImpl, receiptImpl);
        }
    }

    /// @notice True if this chain's production vault + receipt beacons serve
    /// `expectedVaultImpl` and `expectedReceiptImpl`.
    function prodBeaconsServe(address expectedVaultImpl, address expectedReceiptImpl) internal view returns (bool) {
        address[4] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(block.chainid);
        return IBeacon(beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX]).implementation() == expectedVaultImpl
            && IBeacon(beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX]).implementation() == expectedReceiptImpl;
    }
}
