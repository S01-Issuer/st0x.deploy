// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.2/src/Script.sol";
import {console2} from "forge-std-1.16.2/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {ICloneableFactoryV2} from "rain-factory-0.1.1/src/interface/ICloneableFactoryV2.sol";
import {LibCloneFactoryDeploy} from "rain-factory-0.1.1/src/lib/LibCloneFactoryDeploy.sol";
import {
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.1.6/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";

import {LibAuthoriserInvariants, RoleGrant} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibLvmhAuthoriserInvariants} from "../src/lib/LibLvmhAuthoriserInvariants.sol";
import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";

/// @notice The active chain's tLVMH authoriser pin is already set. The script
/// deploys a NEW clone, so a second run would leave a clone nothing pins.
/// @param pinned The hydrated pin.
error LvmhAuthoriserPinAlreadyHydrated(address pinned);

/// @notice The audited 0.1.1 authoriser implementation is missing or carries
/// different code on this chain.
/// @param impl The pinned implementation address.
error LvmhImplNotReady(address impl);

/// @notice The canonical `CloneFactory` is missing or carries different code.
/// @param factory The pinned factory address.
error LvmhCloneFactoryNotReady(address factory);

/// @notice The broadcasting deploy key still holds a role on the new
/// authoriser after the renounce loop.
/// @param role The role it still holds.
/// @param deployer The deploy key.
error LvmhDeployerStillHoldsRole(bytes32 role, address deployer);

/// @title DeployLvmhAuthoriser
/// @notice Deploys tLVMH's dedicated authoriser on the chain it is dispatched
/// against: a clone of the SAME audited 0.1.1 authoriser implementation the
/// shared V4 authoriser clones, carrying the role map pinned in
/// `LibLvmhAuthoriserInvariants.expectedGrants`.
///
/// One deploy-key broadcast, no Safe signature, modelled on the (executed,
/// since deleted) `20260619-deploy-v4-authoriser-clone`:
///
///   1. `CloneFactory.clone(impl, initialAdmin = deploy key)` — the 0.1.1
///      `initialize` grants the seven `_ADMIN` roles to the deploy key.
///   2. Grant the six action grants: Safe DEPOSIT/WITHDRAW/CERTIFY, tLVMH
///      minter DEPOSIT/WITHDRAW, service signer 3d0c CERTIFY only.
///   3. Grant the seven `_ADMIN` roles to the chain's governance timelock
///      (`LibTimelockInvariants.timelockForChainId`) — the holder the shared
///      authoriser's admins have sat on since the governance migration.
///   4. Renounce the seven `_ADMIN` roles from the deploy key.
///
/// Post-state: EIP-1167 codehash equals the shared clone's, the full map
/// holds, every forbidden grant is absent (3d0c and the orchestrator hold no
/// DEPOSIT/WITHDRAW; the Safe holds no `_ADMIN`; nobody named holds
/// `DEFAULT_ADMIN_ROLE`), and the deploy key holds nothing.
///
/// Because the deploy key holds every `_ADMIN` in the window between steps 1
/// and 4, no timelock operation is needed to set the map up — the admins go
/// straight to the timelock in step 3, and from then on every change to the
/// map is a 48h timelock operation.
///
/// @dev Dispatch: `Actions → manual-broadcast`,
/// `script = 20261006-deploy-lvmh-authoriser`, once per `network` (base,
/// ethereum, hyperevm, robinhood, bsc). Then pin the logged address into that
/// chain's `LibLvmhAuthoriserInvariants.LVMH_AUTHORISER_*`; a re-dispatch
/// against a pinned chain refuses with `LvmhAuthoriserPinAlreadyHydrated`.
///
/// The clone lands at CREATE(CloneFactory, factory nonce); the script logs the
/// predicted address before broadcasting. The factory is permissionless, so
/// the prediction is advisory — pin what the run logs.
contract DeployLvmhAuthoriser is Script {
    function run() external {
        (address safe, address timelock, address impl, address factory) = preflight();

        console2.log("Predicted tLVMH authoriser:", vm.toString(vm.computeCreateAddress(factory, vm.getNonce(factory))));

        vm.startBroadcast();
        // The broadcasting key, read from the cheatcode state rather than
        // `msg.sender` so it is the same address under `forge script` and in
        // a fork test.
        (, address deployer,) = vm.readCallers();
        address clone = deployAndConfigure(factory, impl, deployer, safe, timelock);
        vm.stopBroadcast();

        assertPostState(clone, deployer, safe, timelock);

        console2.log("==== tLVMH AUTHORISER DEPLOYED ====");
        console2.log("chain id:", block.chainid);
        console2.log("authoriser:", vm.toString(clone));
        console2.log("codehash:", vm.toString(clone.codehash));
        console2.log("Pin it into LibLvmhAuthoriserInvariants.LVMH_AUTHORISER_* for this chain.");
    }

    /// @notice Every pre-broadcast gate. Public so a test can drive it.
    /// @return safe The chain's token-owner Safe.
    /// @return timelock The chain's governance timelock.
    /// @return impl The audited 0.1.1 authoriser implementation.
    /// @return factory The canonical CloneFactory.
    function preflight() public view returns (address safe, address timelock, address impl, address factory) {
        // Reverts for a chain without a slot; refuses a hydrated slot.
        address pinned = LibLvmhAuthoriserInvariants.lvmhAuthoriserForChainId(block.chainid);
        if (pinned != address(0)) revert LvmhAuthoriserPinAlreadyHydrated(pinned);

        safe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        LibTimelockInvariants.assertTimelockState(timelock, safe);

        impl = LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1;
        if (
            impl.code.length == 0
                || impl.codehash != LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CODEHASH_0_1_1
        ) {
            revert LvmhImplNotReady(impl);
        }

        factory = LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS;
        if (factory.code.length == 0 || factory.codehash != LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_CODEHASH) {
            revert LvmhCloneFactoryNotReady(factory);
        }
    }

    /// @notice Steps 1-4. Called inside the broadcast, as `deployer`.
    /// @param factory The CloneFactory.
    /// @param impl The authoriser implementation to clone.
    /// @param deployer The broadcasting key (the transient `initialAdmin`).
    /// @param safe The chain's token-owner Safe.
    /// @param timelock The chain's governance timelock.
    /// @return clone The configured authoriser.
    function deployAndConfigure(address factory, address impl, address deployer, address safe, address timelock)
        internal
        returns (address clone)
    {
        clone = ICloneableFactoryV2(factory)
            .clone(impl, abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: deployer})));
        IAccessControl acl = IAccessControl(clone);

        RoleGrant[] memory grants = LibLvmhAuthoriserInvariants.expectedGrants(safe, timelock);
        // Entries 0..6 are the `_ADMIN` slice (granted to the timelock below,
        // in the same loop); 7.. are the action grants.
        for (uint256 i = 0; i < grants.length; i++) {
            acl.grantRole(grants[i].role, grants[i].grantee);
        }

        bytes32[7] memory admins = LibLvmhAuthoriserInvariants.adminRoles();
        for (uint256 i = 0; i < admins.length; i++) {
            acl.renounceRole(admins[i], deployer);
        }
    }

    /// @notice The post-state every broadcast must leave. Public so a test can
    /// drive it against a clone it configured under a prank.
    /// @param clone The configured authoriser.
    /// @param deployer The deploy key.
    /// @param safe The chain's token-owner Safe.
    /// @param timelock The chain's governance timelock.
    function assertPostState(address clone, address deployer, address safe, address timelock) public view {
        LibLvmhAuthoriserInvariants.assertIsAuditedClone(clone);
        LibLvmhAuthoriserInvariants.assertExpectedGrants(clone, safe, timelock);

        IAccessControl acl = IAccessControl(clone);
        bytes32[7] memory admins = LibLvmhAuthoriserInvariants.adminRoles();
        for (uint256 i = 0; i < admins.length; i++) {
            if (acl.hasRole(admins[i], deployer)) revert LvmhDeployerStillHoldsRole(admins[i], deployer);
        }
        bytes32[3] memory actions = LibLvmhAuthoriserInvariants.actionRoles();
        for (uint256 i = 0; i < actions.length; i++) {
            if (acl.hasRole(actions[i], deployer)) revert LvmhDeployerStillHoldsRole(actions[i], deployer);
        }
        if (acl.hasRole(LibAuthoriserInvariants.DEFAULT_ADMIN_ROLE, deployer)) {
            revert LvmhDeployerStillHoldsRole(LibAuthoriserInvariants.DEFAULT_ADMIN_ROLE, deployer);
        }
    }
}
