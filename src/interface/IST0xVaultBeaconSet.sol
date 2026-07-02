// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {IBeacon} from "@openzeppelin-contracts-5.6.1/proxy/beacon/IBeacon.sol";

/// @title IST0xVaultBeaconSet
/// @notice The subset of `OffchainAssetReceiptVaultBeaconSetDeployer` the
/// orchestrator reads to enforce its vault-logic version lock. Every
/// production receipt vault + receipt is a `BeaconProxy` of these two
/// beacons, so reading the beacons' current `implementation()` is a single
/// global check that covers every token the orchestrator can touch.
interface IST0xVaultBeaconSet {
    function iOffchainAssetReceiptVaultBeacon() external view returns (IBeacon);
    function iReceiptBeacon() external view returns (IBeacon);
}
