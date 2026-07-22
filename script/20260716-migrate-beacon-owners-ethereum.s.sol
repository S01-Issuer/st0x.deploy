// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";
import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";
import {LibProdBeaconsEthereum} from "../src/lib/LibProdBeaconsEthereum.sol";
import {LibProdDeployV1} from "../src/lib/LibProdDeployV1.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibBeaconInvariants} from "../src/lib/LibBeaconInvariants.sol";

/// @title MigrateBeaconOwnersEthereum
/// @notice Transfers ownership of the three ST0x production beacons on
/// **Ethereum mainnet** from the deploy EOA (`LibProdDeployV1.BEACON_INITIAL_OWNER`,
/// rainlang.eth) to the Ethereum token-owner Safe
/// (`LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM`). The Ethereum
/// equivalent of `MigrateBeaconOwners` (which already ran this migration for
/// Base's V1 beacons, #253) — the beacons differ per chain by deployer version
/// but the operation is identical.
///
/// @dev This is a **deploy-key broadcast**, not a Safe artifact: the beacons
/// are EOA-owned, so the migration is the EOA calling `transferOwnership`.
/// Broadcast as the EOA:
///
///   forge script script/20260716-migrate-beacon-owners-ethereum.s.sol \
///     --rpc-url ethereum --broadcast --private-key <EOA key>
///
/// Ordering: run AFTER the Ethereum Safe's threshold has been raised to match
/// Base (3-of-6). The beacons are not yet backing any vaults (no Ethereum
/// proxies exist yet), so this is pure ownership hand-off with no live-vault
/// risk — but doing it early makes the "Ethereum beacons are Safe-owned"
/// invariant (`EthereumBeaconOwnershipTest`) go green.
contract MigrateBeaconOwnersEthereum is Script {
    /// @notice Pre-flight every beacon against the EOA-owned state, broadcast
    /// the three `transferOwnership` calls to the Ethereum Safe, then re-assert
    /// every beacon against the Safe-owned state. Implementations are asserted
    /// unchanged across the transfer.
    function run() external {
        address safe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM;
        require(safe != address(0), "Ethereum token-owner Safe not pinned");
        address[3] memory beaconList = LibProdBeaconsEthereum.beacons();
        address[3] memory implList = LibProdBeaconsEthereum.implementations();

        // Pre-flight: every beacon is deployed, is the OZ UpgradeableBeacon,
        // is still owned by the deploy EOA, and points at its pinned impl.
        // Reverts with the relevant typed error on the first drift, before any
        // broadcast happens.
        for (uint256 i = 0; i < beaconList.length; i++) {
            LibBeaconInvariants.assertBeaconInvariants(beaconList[i], LibProdDeployV1.BEACON_INITIAL_OWNER, implList[i]);
        }

        // Broadcast the ownership transfers from the EOA — three separate
        // transactions, one per beacon.
        vm.startBroadcast();
        for (uint256 i = 0; i < beaconList.length; i++) {
            Ownable(beaconList[i]).transferOwnership(safe);
        }
        vm.stopBroadcast();

        // Post-state: every beacon is now Safe-owned, implementations
        // unchanged.
        for (uint256 i = 0; i < beaconList.length; i++) {
            LibBeaconInvariants.assertBeaconInvariants(beaconList[i], safe, implList[i]);
        }

        console2.log("Transferred ownership of 3 Ethereum beacons to:", vm.toString(safe));
    }
}
