// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";

import {IGnosisSafe} from "../src/interface/IGnosisSafe.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibEuAuthoriserClone} from "../src/lib/LibEuAuthoriserClone.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibSafeOps, SafeTx} from "../src/lib/LibSafeOps.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";

/// @notice The EU authoriser clone is not on chain, or does not carry the
/// pinned EIP-1167 code hash, on the active chain. The grants cannot be
/// authored against a contract that is not there.
/// @param clone The clone address inspected.
error EuAuthoriserNotDeployed(address clone);

/// @notice The Safe does not hold the `_ADMIN` role the bundle needs in order
/// to grant with it. Nothing in the bundle could execute.
/// @param clone The clone inspected.
/// @param role The `_ADMIN` role the Safe is missing.
error SafeMissingRoleAdmin(address clone, bytes32 role);

/// @title GrantEuAuthoriserRoles
/// @notice Authors the Safe bundle that takes the freshly cloned EU assets
/// authoriser from "initial admin only" to its pinned role map, and hands
/// governance to the timelock.
///
/// Emits Safe Tx Builder JSON and the MultiSend `SafeTxHash`. It NEVER
/// broadcasts: the Safe executes, and a signer compares the hash this prints
/// against what their wallet shows before signing.
///
/// The bundle, in order:
///
/// 1. every `(role, grantee)` pair in the map, granted by the Safe while it
///    still holds the `_ADMIN` roles from `initialize`;
/// 2. each of the seven `_ADMIN` roles granted to the chain's governance
///    timelock;
/// 3. each of the seven renounced by the Safe.
///
/// Order is load-bearing. Renouncing before granting the action roles would
/// leave a clone nobody can administer — the `_ADMIN` roles are their own
/// admin, so once unheld they can never be granted again. Steps 2 and 3 are
/// in that order for the same reason: the timelock must hold a role before
/// the Safe gives up the only other copy.
///
/// The map is `LibAuthoriserInvariants.expectedGrants(safe, timelock, minter)`
/// — the production map with the EU minter in the mint and redeem slots. The
/// post-state is exactly what `assertExpectedGrants` asserts, so the bundle
/// and the invariant cannot describe different end states.
contract GrantEuAuthoriserRoles is Script {
    /// The bundle's name in the Tx Builder JSON, so a signer sees what they
    /// are loading.
    string internal constant BUNDLE_NAME = "ST0x EU assets authoriser: role map and admin handover to the timelock";

    /// @notice Where the JSON is written, per chain, so a multi-chain rollout
    /// does not overwrite one chain's artifact with another's.
    /// @return The artifact path.
    function artifactPath() internal view virtual returns (string memory) {
        return string.concat("out/20261006-grant-eu-authoriser-roles-", vm.toString(block.chainid), ".json");
    }

    /// @notice The clone, the Safe and the timelock, each asserted ready
    /// before any transaction is authored against them.
    /// @return clone The EU authoriser clone.
    /// @return safe The chain's token-owner Safe.
    /// @return timelock The chain's governance timelock.
    function preflight() public view returns (address clone, address safe, address timelock) {
        clone = LibEuAuthoriserClone.cloneDeployedAddress();
        if (clone.code.length == 0 || clone.codehash != LibEuAuthoriserClone.cloneDeployedCodehash()) {
            revert EuAuthoriserNotDeployed(clone);
        }

        safe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        LibTimelockInvariants.assertTimelockState(timelock, safe);

        // The Safe grants with its `_ADMIN` roles, so a Safe that has already
        // renounced them authors a bundle every transaction of which reverts.
        // Named by role rather than reported as a generic failure.
        bytes32[7] memory admins = adminRoles();
        for (uint256 i = 0; i < admins.length; i++) {
            if (!IAccessControl(clone).hasRole(admins[i], safe)) {
                revert SafeMissingRoleAdmin(clone, admins[i]);
            }
        }
    }

    /// @notice The seven `_ADMIN` roles, in the order the map's leading slice
    /// carries them.
    /// @return roles The `_ADMIN` roles.
    function adminRoles() public pure returns (bytes32[7] memory roles) {
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants(
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE,
            LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK,
            LibAuthoriserInvariants.GRANTEE_EU_MINTER
        );
        for (uint256 i = 0; i < LibAuthoriserInvariants.ADMIN_ROLE_COUNT; i++) {
            roles[i] = grants[i].role;
        }
    }

    /// @notice The bundle: the map, then the handover, then the renounce.
    /// @param clone The authoriser the roles are on.
    /// @param safe The Safe executing the bundle.
    /// @param timelock The admin holder the bundle hands governance to.
    /// @return txs The transactions, in execution order.
    function grantBundle(address clone, address safe, address timelock) public pure returns (SafeTx[] memory txs) {
        RoleGrant[] memory grants =
            LibAuthoriserInvariants.expectedGrants(safe, timelock, LibAuthoriserInvariants.GRANTEE_EU_MINTER);
        bytes32[7] memory admins = adminRoles();

        txs = new SafeTx[](grants.length + admins.length);

        for (uint256 i = 0; i < grants.length; i++) {
            txs[i] = SafeTx({
                to: clone,
                value: 0,
                data: abi.encodeCall(IAccessControl.grantRole, (grants[i].role, grants[i].grantee)),
                operation: 0
            });
        }

        // The timelock receives each `_ADMIN` before the Safe renounces it, so
        // no window exists in which an `_ADMIN` role is unheld.
        for (uint256 i = 0; i < admins.length; i++) {
            txs[grants.length + i] = SafeTx({
                to: clone, value: 0, data: abi.encodeCall(IAccessControl.renounceRole, (admins[i], safe)), operation: 0
            });
        }
    }

    /// @notice Authors the bundle, simulates every transaction against the
    /// live clone, asserts the post-state the invariant demands, and writes
    /// the JSON a signer loads.
    function run() external {
        (address clone, address safe, address timelock) = preflight();

        SafeTx[] memory txs = grantBundle(clone, safe, timelock);
        IGnosisSafe gnosisSafe = IGnosisSafe(safe);
        uint256 nonce = gnosisSafe.nonce();
        bytes32 bundleSafeTxHash = LibSafeOps.computeMultiSendSafeTxHash(gnosisSafe, txs, nonce);

        // Simulated in order against the real clone, so a bundle that cannot
        // execute fails here rather than after signatures are collected.
        for (uint256 i = 0; i < txs.length; i++) {
            LibSafeOps.simulateExternalCall(gnosisSafe, txs[i].to, txs[i].data);
        }

        // The post-state is the invariant's, not a restatement: if the bundle
        // reaches a state `assertExpectedGrants` would refuse, the refusal is
        // here and not on the next live-state run.
        LibAuthoriserInvariants.assertExpectedGrants(clone, safe, timelock, LibAuthoriserInvariants.GRANTEE_EU_MINTER);

        string memory json = LibSafeOps.emitTxBuilderJson(safe, block.chainid, BUNDLE_NAME, txs);
        vm.writeFile(artifactPath(), json);

        console2.log("==== TX BUILDER JSON BEGIN ====");
        console2.log(json);
        console2.log("==== TX BUILDER JSON END ====");
        console2.log("EU assets authoriser:", vm.toString(clone));
        console2.log("Safe:", vm.toString(safe));
        console2.log("Bundle MultiSend SafeTxHash:", vm.toString(bundleSafeTxHash));
        console2.log("Nonce:", nonce);
        console2.log("Chain:", block.chainid);
    }

    /// @notice Re-derives the bundle and checks a written artifact still
    /// matches it against current chain state, for a signer verifying a file
    /// someone else produced.
    /// @param jsonPath The artifact to check.
    function verify(string calldata jsonPath) external view {
        (address clone, address safe, address timelock) = preflight();
        SafeTx[] memory expected = grantBundle(clone, safe, timelock);
        LibSafeOps.assertParsedTxsMatch(expected, jsonPath);

        console2.log("Artifact verified against live state.");
        console2.log(
            "Bundle MultiSend SafeTxHash:",
            vm.toString(LibSafeOps.computeMultiSendSafeTxHash(IGnosisSafe(safe), expected, IGnosisSafe(safe).nonce()))
        );
    }
}
