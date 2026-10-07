// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";

import {
    IMigrationRegistryV2,
    MIGRATION_HEAD_GENESIS,
    Prerequisite
} from "rain-deploy-0.1.15/src/interface/IMigrationRegistryV2.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.15/src/lib/LibMigrationRegistryDeploy.sol";

import {IGnosisSafe} from "../src/interface/IGnosisSafe.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibEuAuthoriserClone} from "../src/lib/LibEuAuthoriserClone.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibSafeOps, SafeTx} from "../src/lib/LibSafeOps.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";

/// @notice The EU authoriser clone is absent or carries the wrong code hash.
/// @param clone The clone address inspected.
error EuAuthoriserNotDeployed(address clone);

/// @notice The Safe does not hold an `_ADMIN` role the bundle grants with.
/// @param clone The clone inspected.
/// @param role The missing role.
error SafeMissingRoleAdmin(address clone, bytes32 role);

/// @title GrantEuAuthoriserRoles
/// @notice Authors the Safe bundle that applies the pinned role map to the EU
/// assets authoriser clone and hands governance to the timelock. Broadcasts
/// nothing; writes Safe Tx Builder JSON and prints the MultiSend `SafeTxHash`.
contract GrantEuAuthoriserRoles is Script {
    string internal constant BUNDLE_NAME = "ST0x EU assets authoriser: role map and admin handover to the timelock";

    bytes32 internal constant EU_AUTHORISER_NAMESPACE = keccak256("st0x.eu-assets-authoriser");

    bytes32 internal constant EU_AUTHORISER_MIGRATION = keccak256("st0x.eu-assets-authoriser.grant-and-handover");

    /// @notice Where the JSON is written, per chain.
    /// @return The artifact path.
    function artifactPath() internal view virtual returns (string memory) {
        return string.concat("out/20261006-grant-eu-authoriser-roles-", vm.toString(block.chainid), ".json");
    }

    /// @notice Asserts the clone, Safe and timelock are ready.
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

        bytes32[7] memory admins = adminRoles();
        for (uint256 i = 0; i < admins.length; i++) {
            if (!IAccessControl(clone).hasRole(admins[i], safe)) {
                revert SafeMissingRoleAdmin(clone, admins[i]);
            }
        }
    }

    /// @notice The seven `_ADMIN` roles, in map order.
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

    /// @notice The migration registration, then the map, then the renounce.
    /// @param clone The authoriser the roles are on.
    /// @param safe The Safe executing the bundle.
    /// @param timelock The admin holder the bundle hands governance to.
    /// @return txs The transactions, in execution order.
    function grantBundle(address clone, address safe, address timelock) public pure returns (SafeTx[] memory txs) {
        RoleGrant[] memory grants =
            LibAuthoriserInvariants.expectedGrants(safe, timelock, LibAuthoriserInvariants.GRANTEE_EU_MINTER);
        bytes32[7] memory admins = adminRoles();

        txs = new SafeTx[](1 + grants.length + admins.length);

        Prerequisite[] memory prerequisites = new Prerequisite[](1);
        prerequisites[0] =
            Prerequisite({writer: safe, namespace: EU_AUTHORISER_NAMESPACE, migration: MIGRATION_HEAD_GENESIS});

        txs[0] = SafeTx({
            to: LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS,
            value: 0,
            data: abi.encodeCall(
                IMigrationRegistryV2.applyMigration, (EU_AUTHORISER_NAMESPACE, EU_AUTHORISER_MIGRATION, prerequisites)
            ),
            operation: 0
        });

        for (uint256 i = 0; i < grants.length; i++) {
            txs[1 + i] = SafeTx({
                to: clone,
                value: 0,
                data: abi.encodeCall(IAccessControl.grantRole, (grants[i].role, grants[i].grantee)),
                operation: 0
            });
        }

        for (uint256 i = 0; i < admins.length; i++) {
            txs[1 + grants.length + i] = SafeTx({
                to: clone, value: 0, data: abi.encodeCall(IAccessControl.renounceRole, (admins[i], safe)), operation: 0
            });
        }
    }

    /// @notice Authors the bundle, simulates it, asserts the post-state, writes
    /// the JSON.
    function run() external {
        (address clone, address safe, address timelock) = preflight();

        SafeTx[] memory txs = grantBundle(clone, safe, timelock);
        IGnosisSafe gnosisSafe = IGnosisSafe(safe);
        uint256 nonce = gnosisSafe.nonce();
        bytes32 bundleSafeTxHash = LibSafeOps.computeMultiSendSafeTxHash(gnosisSafe, txs, nonce);

        for (uint256 i = 0; i < txs.length; i++) {
            LibSafeOps.simulateExternalCall(gnosisSafe, txs[i].to, txs[i].data);
        }

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

    /// @notice Re-derives the bundle and checks a written artifact matches it.
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
