// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";

import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {SafeBundleScript} from "rain-deploy-0.1.22/src/abstract/SafeBundleScript.sol";
import {SafeTx} from "rain-deploy-0.1.22/src/lib/LibSafeTx.sol";

import {LibAuthoriserInvariants, RoleGrant} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibEuAuthoriserClone} from "../src/lib/LibEuAuthoriserClone.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";
import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {migrateGovernanceToTimelockDeclaration} from "./20260729-migrate-governance-to-timelock.s.sol";

/// @notice The EU authoriser clone is absent or carries the wrong code hash.
/// @param clone The clone address inspected.
error EuAuthoriserNotDeployed(address clone);

/// @notice The Safe does not hold the admin of a role the bundle still has to
/// grant.
/// @param clone The clone inspected.
/// @param role The missing admin role.
error SafeMissingRoleAdmin(address clone, bytes32 role);

/// @notice After the bundle, the Safe still holds an `_ADMIN` role.
/// @param role The role.
error SafeStillHoldsAdmin(bytes32 role);

/// @notice This script's declaration: the line's record after the governance
/// move to the timelock.
/// @return The declaration.
function grantEuAuthoriserRolesDeclaration() pure returns (ScriptDeclaration memory) {
    return LibStoxMigrations.migrationOnto(
        keccak256("script/20261006-grant-eu-authoriser-roles.s.sol"), migrateGovernanceToTimelockDeclaration().id
    );
}

/// @title GrantEuAuthoriserRoles
/// @notice Authors the Safe bundle that applies the pinned role map to the EU
/// assets authoriser clone, hands its governance to the timelock and records
/// it, in one atomic MultiSend: every map grant not yet held, then the
/// renounce of every `_ADMIN` the Safe still holds, then
/// `registry.applyMigrationV3(WRITER, NAMESPACE, <this script>,
/// [governance to timelock])`.
///
/// @dev Dispatch via `Actions → run-script` with
/// `script = 20261006-grant-eu-authoriser-roles` per chain.
contract GrantEuAuthoriserRoles is SafeBundleScript, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration() external pure returns (ScriptDeclaration memory) {
        return grantEuAuthoriserRolesDeclaration();
    }

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ST0x EU assets authoriser: role map and admin handover to the timelock";
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view virtual override returns (string memory) {
        return string.concat("out/20261006-grant-eu-authoriser-roles-", vm.toString(block.chainid), ".json");
    }

    /// @inheritdoc SafeBundleScript
    function safe() internal view override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    /// @notice The chain's EU authoriser clone.
    /// @return The clone.
    function clone() internal view returns (address) {
        return LibEuAuthoriserClone.cloneDeployedAddress(block.chainid);
    }

    /// @notice The chain's governance timelock.
    /// @return The timelock.
    function timelock() internal view returns (address) {
        return LibTimelockInvariants.timelockForChainId(block.chainid);
    }

    /// @notice The pinned role map, with the chain's timelock as admin holder.
    /// @return The grants.
    function grants() internal view returns (RoleGrant[] memory) {
        return LibAuthoriserInvariants.expectedEuGrants(
            timelock(), LibAuthoriserInvariants.GRANTEE_EU_MINTER, LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C
        );
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The clone is the pinned one, the Safe and timelock are what this
    /// repo pins, this is the line's next record, which the Safe may write,
    /// and the Safe holds the admin of every role still to grant.
    function preflight() internal view override {
        address eu = clone();
        if (eu.code.length == 0 || eu.codehash != LibEuAuthoriserClone.cloneDeployedCodehash()) {
            revert EuAuthoriserNotDeployed(eu);
        }
        address chainSafe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        LibTimelockInvariants.assertTimelockState(timelock(), chainSafe);
        LibStoxMigrations.assertNext(grantEuAuthoriserRolesDeclaration(), chainSafe);

        RoleGrant[] memory map = grants();
        for (uint256 i = 0; i < map.length; i++) {
            if (!IAccessControl(eu).hasRole(map[i].role, map[i].grantee)) {
                bytes32 admin = IAccessControl(eu).getRoleAdmin(map[i].role);
                if (!IAccessControl(eu).hasRole(admin, chainSafe)) {
                    revert SafeMissingRoleAdmin(eu, admin);
                }
            }
        }
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The grants not yet held, the renounces of the `_ADMIN`s the Safe
    /// still holds, then the record.
    function authorBundle() internal view override returns (SafeTx[] memory) {
        address eu = clone();
        address chainSafe = address(safe());
        RoleGrant[] memory map = grants();
        SafeTx[] memory candidates = new SafeTx[](map.length + LibAuthoriserInvariants.ADMIN_ROLE_COUNT + 1);
        uint256 count = 0;
        for (uint256 i = 0; i < map.length; i++) {
            if (!IAccessControl(eu).hasRole(map[i].role, map[i].grantee)) {
                candidates[count++] = SafeTx({
                    to: eu,
                    value: 0,
                    data: abi.encodeCall(IAccessControl.grantRole, (map[i].role, map[i].grantee)),
                    operation: Enum.Operation.Call
                });
            }
        }
        for (uint256 i = 0; i < LibAuthoriserInvariants.ADMIN_ROLE_COUNT; i++) {
            if (IAccessControl(eu).hasRole(map[i].role, chainSafe)) {
                candidates[count++] = SafeTx({
                    to: eu,
                    value: 0,
                    data: abi.encodeCall(IAccessControl.renounceRole, (map[i].role, chainSafe)),
                    operation: Enum.Operation.Call
                });
            }
        }
        candidates[count++] = LibStoxMigrations.recordTx(grantEuAuthoriserRolesDeclaration());
        SafeTx[] memory txs = new SafeTx[](count);
        for (uint256 i = 0; i < count; i++) {
            txs[i] = candidates[i];
        }
        return txs;
    }

    /// @inheritdoc SafeBundleScript
    /// @dev The record is this bundle's, the map holds with the timelock as
    /// admin holder, and the Safe holds no `_ADMIN`.
    function assertPostState() internal view override {
        LibStoxMigrations.assertRecorded(grantEuAuthoriserRolesDeclaration());
        address eu = clone();
        LibAuthoriserInvariants.assertExpectedEuGrants(eu, timelock(), LibAuthoriserInvariants.GRANTEE_EU_MINTER);
        RoleGrant[] memory map = grants();
        for (uint256 i = 0; i < LibAuthoriserInvariants.ADMIN_ROLE_COUNT; i++) {
            if (IAccessControl(eu).hasRole(map[i].role, address(safe()))) {
                revert SafeStillHoldsAdmin(map[i].role);
            }
        }
        LibSafeInvariants.assertTokenOwnerSafePolicy(safe());
    }
}
