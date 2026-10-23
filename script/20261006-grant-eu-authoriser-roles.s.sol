// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";

import {
    IMigrationRegistryV3,
    MIGRATION_HEAD_GENESIS,
    Prerequisite
} from "rain-deploy-0.1.22/src/interface/IMigrationRegistryV3.sol";
import {LibMigrationRegistry} from "rain-deploy-0.1.22/src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "rain-deploy-0.1.22/src/lib/LibMigrationRegistryDeploy.sol";

import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibEuAuthoriserClone} from "../src/lib/LibEuAuthoriserClone.sol";
import {LibRbacMigration} from "../src/lib/LibRbacMigration.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {LibSafeTx, SafeTx} from "rain-deploy-0.1.22/src/lib/LibSafeTx.sol";
import {LibSafeFork} from "rain-deploy-0.1.22/src/lib/LibSafeFork.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.22/src/lib/LibSafeTxBuilderJson.sol";
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
        // MultiSendCallOnly raw-calls `txs[0]`, so a registry that is not on
        // this chain records nothing and returns success. Without this the
        // bundle's run-once guard silently does not exist.
        LibMigrationRegistry.checkCodeHash();

        clone = LibEuAuthoriserClone.cloneDeployedAddress(block.chainid);
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
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedEuGrants(
            LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK,
            LibAuthoriserInvariants.GRANTEE_EU_MINTER,
            LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C
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
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedEuGrants(
            timelock, LibAuthoriserInvariants.GRANTEE_EU_MINTER, LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C
        );
        bytes32[7] memory admins = adminRoles();

        txs = new SafeTx[](1 + grants.length + admins.length);

        // Genesis, not the line's live head. A signed bundle names the state
        // it was approved against, so another RBAC migration landing first
        // must refuse this one rather than silently re-base onto it.
        Prerequisite[] memory prerequisites = new Prerequisite[](1);
        prerequisites[0] = Prerequisite({
            writer: safe, namespace: LibRbacMigration.STOX_RBAC_NAMESPACE, migration: MIGRATION_HEAD_GENESIS
        });

        txs[0] = SafeTx({
            to: LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS,
            value: 0,
            data: abi.encodeCall(
                IMigrationRegistryV3.applyMigrationV3,
                (
                    safe,
                    LibRbacMigration.STOX_RBAC_NAMESPACE,
                    LibRbacMigration.EU_AUTHORISER_GRANT_AND_HANDOVER,
                    prerequisites
                )
            ),
            operation: Enum.Operation.Call
        });

        for (uint256 i = 0; i < grants.length; i++) {
            txs[1 + i] = SafeTx({
                to: clone,
                value: 0,
                data: abi.encodeCall(IAccessControl.grantRole, (grants[i].role, grants[i].grantee)),
                operation: Enum.Operation.Call
            });
        }

        for (uint256 i = 0; i < admins.length; i++) {
            txs[1 + grants.length + i] = SafeTx({
                to: clone,
                value: 0,
                data: abi.encodeCall(IAccessControl.renounceRole, (admins[i], safe)),
                operation: Enum.Operation.Call
            });
        }
    }

    /// @notice Authors the bundle, simulates it, asserts the post-state, writes
    /// the JSON.
    function run() external {
        (address clone, address safe, address timelock) = preflight();

        SafeTx[] memory txs = grantBundle(clone, safe, timelock);
        Safe gnosisSafe = Safe(payable(safe));
        uint256 nonce = gnosisSafe.nonce();
        bytes32 bundleSafeTxHash = LibSafeTx.multiSendSafeTxHash(gnosisSafe, txs, nonce);

        for (uint256 i = 0; i < txs.length; i++) {
            LibSafeFork.simulateCall(vm, gnosisSafe, txs[i].to, txs[i].data);
        }

        LibAuthoriserInvariants.assertExpectedEuGrants(clone, timelock, LibAuthoriserInvariants.GRANTEE_EU_MINTER);

        string memory json = LibSafeTxBuilderJson.toJson(vm, safe, block.chainid, BUNDLE_NAME, txs);
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
        LibSafeTxBuilderJson.requireMatches(vm, vm.readFile(jsonPath), safe, expected);

        console2.log("Artifact verified against live state.");
        console2.log(
            "Bundle MultiSend SafeTxHash:",
            vm.toString(LibSafeTx.multiSendSafeTxHash(Safe(payable(safe)), expected, Safe(payable(safe)).nonce()))
        );
    }
}
