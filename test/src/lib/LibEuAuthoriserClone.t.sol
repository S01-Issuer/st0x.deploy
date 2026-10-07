// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibICloneableFactoryV4} from "rain-factory-0.1.30/src/lib/LibICloneableFactoryV4.sol";

import {EU_AUTHORISER_SALT, LibEuAuthoriserClone} from "../../../src/lib/LibEuAuthoriserClone.sol";
import {LibCloneFactoryDeploy} from "rain-factory-deploy-0.1.15/src/lib/LibCloneFactoryDeploy.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../../../src/lib/LibAuthoriserInvariants.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../../../src/lib/LibTimelockInvariants.sol";

/// @title LibEuAuthoriserCloneTest
/// @notice The EU assets authoriser is the production authoriser's own
/// implementation with one grantee changed. These pin that, fork-free.
contract LibEuAuthoriserCloneTest is Test {
    /// @notice The EU map and the US map differ in exactly two pairs, both the
    /// minter's, and in no other slot. This is what "the same authoriser with
    /// a different minter" means, and it fails if a second map ever drifts
    /// from the first.
    function testEuMapDiffersFromUsMapOnlyInTheMinter() external pure {
        address safe = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
        address timelock = LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK;

        RoleGrant[] memory us = LibAuthoriserInvariants.expectedGrants(safe, timelock);
        RoleGrant[] memory eu =
            LibAuthoriserInvariants.expectedGrants(safe, timelock, LibAuthoriserInvariants.GRANTEE_EU_MINTER);

        assertEq(us.length, eu.length, "map length");

        uint256 differing = 0;
        for (uint256 i = 0; i < us.length; i++) {
            assertEq(us[i].role, eu[i].role, "role order");
            if (us[i].grantee != eu[i].grantee) {
                differing++;
                assertEq(eu[i].grantee, LibAuthoriserInvariants.GRANTEE_EU_MINTER, "differing grantee is the minter");
                assertEq(us[i].grantee, LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C, "US grantee is the signer");
                assertTrue(
                    us[i].role == keccak256("DEPOSIT") || us[i].role == keccak256("WITHDRAW"),
                    "differing role is mint or redeem"
                );
            }
        }
        assertEq(differing, 2, "exactly DEPOSIT and WITHDRAW differ");
    }

    /// @notice The minter holds mint and redeem and never an `_ADMIN` role.
    /// The admin slice tracks the admin holder; a minter inside it could grant
    /// itself anything.
    function testMinterHoldsNoAdminRole() external pure {
        RoleGrant[] memory eu = LibAuthoriserInvariants.expectedGrants(
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE,
            LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK,
            LibAuthoriserInvariants.GRANTEE_EU_MINTER
        );
        for (uint256 i = 0; i < LibAuthoriserInvariants.ADMIN_ROLE_COUNT; i++) {
            assertTrue(eu[i].grantee != LibAuthoriserInvariants.GRANTEE_EU_MINTER, "minter in the admin slice");
        }
    }

    /// @notice The init data is the initial admin alone, so the minter is role
    /// state granted afterwards and cannot move the clone's address.
    function testCloneDataIsTheInitialAdminOnly() external pure {
        assertEq(
            LibEuAuthoriserClone.cloneData(),
            abi.encode(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE),
            "init data is one address"
        );
    }

    /// @notice The clone proxies the audited implementation: its runtime is
    /// the factory's own EIP-1167 layout over that address, so the code hash
    /// the declaration carries cannot match a proxy pointed anywhere else.
    function testCloneRuntimeEmbedsTheAuditedImplementation() external pure {
        bytes memory runtime = LibEuAuthoriserClone.cloneRuntimeCode();
        bytes memory expected = LibICloneableFactoryV4.cloneCreationCode(
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1
        );
        assertEq(runtime.length, expected.length - 10, "runtime is the initcode tail");
        for (uint256 i = 0; i < runtime.length; i++) {
            assertEq(runtime[i], expected[i + 10], "runtime byte");
        }
        assertEq(LibEuAuthoriserClone.cloneDeployedCodehash(), keccak256(runtime), "codehash is of the runtime");
    }

    /// @notice The address is derived from the implementation and the init
    /// data and NOT from a caller, which is what makes it the same on every
    /// network and unfrontrunnable: a racer can only deploy this same clone.
    function testCloneAddressIsTheSaltAndDataNotTheCaller() external pure {
        address factory = LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS;
        address implementation = LibEuAuthoriserClone.implementation();
        bytes memory data = LibEuAuthoriserClone.cloneData();

        // The declaration's address, re-derived from the same three inputs.
        assertEq(
            LibEuAuthoriserClone.cloneDeployedAddress(),
            LibICloneableFactoryV4.predictCloneAddress(
                factory, implementation, LibICloneableFactoryV4.effectiveOpenSalt(EU_AUTHORISER_SALT, data)
            ),
            "address is the open-salt derivation"
        );

        // Same factory, same implementation, same data, one different salt:
        // a different address. The salt is load-bearing, so a copied salt
        // cannot silently collide with another clone of this implementation.
        assertTrue(
            LibEuAuthoriserClone.cloneDeployedAddress()
                != LibICloneableFactoryV4.predictCloneAddress(
                    factory, implementation, LibICloneableFactoryV4.effectiveOpenSalt(bytes32(0), data)
                ),
            "a different salt is a different address"
        );
    }
}
