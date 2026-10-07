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
    function testCloneDataIsTheChainsOwnSafe() external pure {
        uint256[5] memory chainIds = [
            LibSafeInvariants.BASE_CHAIN_ID,
            LibSafeInvariants.ETHEREUM_CHAIN_ID,
            LibSafeInvariants.HYPEREVM_CHAIN_ID,
            LibSafeInvariants.ROBINHOOD_CHAIN_ID,
            LibSafeInvariants.BSC_CHAIN_ID
        ];
        for (uint256 i = 0; i < chainIds.length; i++) {
            assertEq(
                LibEuAuthoriserClone.cloneData(chainIds[i]),
                abi.encode(LibSafeInvariants.safeForChainId(chainIds[i])),
                "init data is the chain's own Safe"
            );
        }
    }

    /// Base's token-owner Safe is a different address from the other four
    /// chains', and only exists on Base. Baking one of them into the init data
    /// for every chain would leave four clones admined by an address with no
    /// code, and the `_ADMIN` roles administer themselves, so those clones
    /// could never be administered at all.
    function testCloneAddressIsPerChain() external pure {
        address base = LibEuAuthoriserClone.cloneDeployedAddress(LibSafeInvariants.BASE_CHAIN_ID);
        address ethereum = LibEuAuthoriserClone.cloneDeployedAddress(LibSafeInvariants.ETHEREUM_CHAIN_ID);

        assertTrue(
            LibSafeInvariants.safeForChainId(LibSafeInvariants.BASE_CHAIN_ID)
                != LibSafeInvariants.safeForChainId(LibSafeInvariants.ETHEREUM_CHAIN_ID),
            "Base and Ethereum Safes differ"
        );
        assertTrue(base != ethereum, "a different initial admin is a different clone address");

        // The four non-Base chains share one Safe, so they share one address.
        assertEq(
            LibEuAuthoriserClone.cloneDeployedAddress(LibSafeInvariants.BSC_CHAIN_ID),
            ethereum,
            "chains sharing a Safe share an address"
        );
    }

    /// @notice The pinned addresses are what the derivation produces, on every
    /// chain. Either one drifting from the other is caught here rather than by
    /// a live-state read against an address nothing deployed.
    function testPinnedAddressesMatchTheDerivation() external pure {
        uint256[5] memory chainIds = [
            LibSafeInvariants.BASE_CHAIN_ID,
            LibSafeInvariants.ETHEREUM_CHAIN_ID,
            LibSafeInvariants.HYPEREVM_CHAIN_ID,
            LibSafeInvariants.ROBINHOOD_CHAIN_ID,
            LibSafeInvariants.BSC_CHAIN_ID
        ];
        for (uint256 i = 0; i < chainIds.length; i++) {
            assertEq(
                LibAuthoriserInvariants.euAuthoriserForChainId(chainIds[i]),
                LibEuAuthoriserClone.cloneDeployedAddress(chainIds[i]),
                "pin matches the derivation"
            );
        }
    }

    /// @notice The clone proxies the audited implementation: its runtime is
    /// the factory's own EIP-1167 layout over that address, so the code hash
    /// the declaration carries cannot match a proxy pointed anywhere else.
    function testCloneCodehashMatchesTheLiveProductionClone() external pure {
        // An EIP-1167 runtime is a function of the implementation address and
        // nothing else, so two clones of one implementation are byte-identical.
        // The production authoriser clone is already on chain proxying this
        // same audited 0.1.1 implementation, and its code hash is pinned from
        // that deployment — so it is an oracle this repo did not derive.
        //
        // A wrong prefix length, a wrong implementation, or a mis-assembled
        // proxy all move this hash. Comparing the slice against the slice it
        // was cut from could not catch any of them.
        assertEq(
            LibEuAuthoriserClone.cloneDeployedCodehash(),
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH,
            "EU clone code hash equals the live production clone's"
        );
        assertEq(LibEuAuthoriserClone.cloneRuntimeCode().length, 45, "EIP-1167 runtime is 45 bytes");
    }

    /// @notice The address is derived from the implementation and the init
    /// data and NOT from a caller, which is what makes it unfrontrunnable: a
    /// racer can only deploy this same clone.
    function testCloneAddressIsTheSaltAndDataNotTheCaller() external pure {
        address factory = LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS;
        address implementation = LibEuAuthoriserClone.implementation();
        bytes memory data = LibEuAuthoriserClone.cloneData(LibSafeInvariants.BASE_CHAIN_ID);

        // The declaration's address, re-derived from the same three inputs.
        assertEq(
            LibEuAuthoriserClone.cloneDeployedAddress(LibSafeInvariants.BASE_CHAIN_ID),
            LibICloneableFactoryV4.predictCloneAddress(
                factory, implementation, LibICloneableFactoryV4.effectiveOpenSalt(EU_AUTHORISER_SALT, data)
            ),
            "address is the open-salt derivation"
        );

        // Same factory, same implementation, same data, one different salt:
        // a different address. The salt is load-bearing, so a copied salt
        // cannot silently collide with another clone of this implementation.
        assertTrue(
            LibEuAuthoriserClone.cloneDeployedAddress(LibSafeInvariants.BASE_CHAIN_ID)
                != LibICloneableFactoryV4.predictCloneAddress(
                    factory, implementation, LibICloneableFactoryV4.effectiveOpenSalt(bytes32(0), data)
                ),
            "a different salt is a different address"
        );
    }
}
