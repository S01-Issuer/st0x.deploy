// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";
import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";
import {LibProdBeacons0_1_1} from "../src/lib/LibProdBeacons0_1_1.sol";
import {LibProdDeployV1} from "../src/lib/LibProdDeployV1.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibBeaconInvariants} from "../src/lib/LibBeaconInvariants.sol";

/// @title MigrateBeaconOwnersHyperEvm
/// @notice **PENDING.** Transfers ownership of the three ST0x production
/// beacons on **HyperEVM** (chain id 999) from the deploy EOA
/// (`LibProdDeployV1.BEACON_INITIAL_OWNER`, rainlang.eth) to the HyperEVM
/// token-owner Safe (`LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_HYPEREVM`).
/// The HyperEVM leg of the same migration executed for Base (#253) and
/// Ethereum (`20260716-migrate-beacon-owners-ethereum`) — HyperEVM
/// bootstraps at 0.1.1, so its beacons are the SAME deterministic addresses
/// as Ethereum's (`LibProdBeacons0_1_1`). Flips to `**EXECUTED
/// YYYY-MM-DD.**` in the post-execution pin PR.
///
/// @dev This is a **deploy-EOA broadcast**, not a Safe artifact: the beacons
/// come up EOA-owned from the beacon-set deployer constructors, so the
/// migration is the EOA calling `transferOwnership`. Broadcast as the EOA:
///
///   forge script script/20260722-migrate-beacon-owners-hyperevm.s.sol \
///     --rpc-url hyperevm --legacy --broadcast --private-key <EOA key>
///
/// (`--legacy`: HyperEVM's RPC rejects forge's EIP-1559 `eth_feeHistory`
/// fee-estimation ranges.)
///
/// Ordering (RAI-1511): run AFTER the 0.1.1 impl suites are deployed on
/// HyperEVM (the beacons don't exist before) and AFTER the HyperEVM Safe
/// pin hydrates, and BEFORE the token deploy — the token-deploy pre-flight
/// hard-gates on `assertProdBeaconsOwnedByChainSafe`. The beacons back no
/// vaults yet at that point, so this is pure ownership hand-off with no
/// live-vault risk.
contract MigrateBeaconOwnersHyperEvm is Script {
    /// @notice Pre-flight every beacon against the EOA-owned state, broadcast
    /// the three `transferOwnership` calls to the HyperEVM Safe, then
    /// re-assert every beacon against the Safe-owned state. Implementations
    /// are asserted unchanged across the transfer.
    function run() external {
        address safe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_HYPEREVM;
        require(safe != address(0), "HyperEVM token-owner Safe not pinned");
        require(block.chainid == LibSafeInvariants.HYPEREVM_CHAIN_ID, "not HyperEVM - wrong --rpc-url");
        address[3] memory beaconList = LibProdBeacons0_1_1.beacons();
        address[3] memory implList = LibProdBeacons0_1_1.implementations();

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

        console2.log("Transferred ownership of 3 HyperEVM beacons to:", vm.toString(safe));
    }
}
