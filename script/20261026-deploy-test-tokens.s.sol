// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {IERC4626} from "@openzeppelin-contracts-5.7.0/interfaces/IERC4626.sol";
import {ICloneableFactoryV6} from "rain-factory-0.2.5/src/interface/ICloneableFactoryV6.sol";
import {LibICloneableFactoryV6} from "rain-factory-0.2.5/src/lib/LibICloneableFactoryV6.sol";
import {LibCloneFactoryDeploy} from "rain-factory-deploy-0.2.2/src/lib/LibCloneFactoryDeploy.sol";
import {IConfigRegistryV3} from "rain-deploy-0.1.22/src/interface/IConfigRegistryV3.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.22/src/lib/LibConfigRegistryDeploy.sol";
import {
    LibOffchainAssetReceiptVaultRbac,
    OffchainAssetReceiptVaultRbacV1
} from "rain-vats-0.2.9/src/lib/LibOffchainAssetReceiptVaultRbac.sol";
import {IAuthorizableV1} from "rain-vats-0.2.9/src/interface/IAuthorizableV1.sol";
import {IReceiptVaultV3} from "rain-vats-0.2.9/src/interface/IReceiptVaultV3.sol";

import {IStoxScript, ScriptDeclaration} from "../src/interface/IStoxScript.sol";
import {LibProdDeployCurrent} from "../src/generated/LibProdDeployCurrent.sol";
import {LibAuthoriserInvariants} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibBeaconInvariants} from "../src/lib/LibBeaconInvariants.sol";
import {Region} from "../src/lib/LibProdTokenConfig.sol";
import {LibStoxConfig} from "../src/lib/LibStoxConfig.sol";
import {LibStoxMigrations} from "../src/lib/LibStoxMigrations.sol";
import {LibStoxTestTokens, TestTokenAddresses} from "../src/lib/LibStoxTestTokens.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";

/// @notice A pinned dependency is not deployed with its pinned code hash.
/// @param target The pinned address.
/// @param expected The pinned code hash.
/// @param actual The code hash there.
error DependencyNotDeployed(address target, bytes32 expected, bytes32 actual);

/// @notice A beacon name under the root authority is not bound to the chain's
/// production beacon.
/// @param name The beacon name.
/// @param expected The chain's production beacon.
/// @param actual The bound beacon.
error BeaconBindingMismatch(bytes32 name, address expected, address actual);

/// @notice A beacon does not serve the implementation the orchestrator pins.
/// @param beacon The beacon.
/// @param expected The implementation the orchestrator pins.
/// @param actual The implementation it serves.
error BeaconImplementationMismatch(address beacon, address expected, address actual);

/// @notice A region's RBAC owner is not the chain's governance timelock.
/// @param region The region.
/// @param expected The chain's governance timelock.
/// @param actual The bound owner.
error RbacOwnerMismatch(Region region, address expected, address actual);

/// @notice A region's RBAC authorizer is not the chain's authoriser for that
/// region.
/// @param region The region.
/// @param expected The region's authoriser on this chain.
/// @param actual The bound authorizer.
error RbacAuthoriserMismatch(Region region, address expected, address actual);

/// @notice The factory built a region's token or wrapper off its pin.
/// @param region The region.
/// @param expected The pinned address.
/// @param actual The address built.
error TestTokenOffPin(Region region, address expected, address actual);

/// @notice A region's token, receipt or wrapper is not as pinned after the run.
/// @param region The region.
/// @param target The address checked.
error TestTokenNotLanded(Region region, address target);

/// @notice A region's token is not owned by the chain's governance timelock.
/// @param region The region.
/// @param expected The chain's governance timelock.
/// @param actual The token's owner.
error TestTokenOwnerMismatch(Region region, address expected, address actual);

/// @notice A region's token is not on the chain's authoriser for that region.
/// @param region The region.
/// @param expected The region's authoriser on this chain.
/// @param actual The token's authorizer.
error TestTokenAuthoriserMismatch(Region region, address expected, address actual);

/// @title DeployTestTokens
/// @notice Builds the US and EU test tokens and their wrappers through the V6
/// clone factory, from the root authority's bindings, on whichever chain it is
/// dispatched against. Each lands at its `LibStoxTestTokens` pin, which is the
/// same on every chain.
///
/// The factory is permissionless and every address commits to its init data,
/// so whoever builds a token gets the one pinned here. A token, receipt or
/// wrapper already at its pin is not built again, so a re-dispatch only re-runs
/// the checks.
///
/// Pre-flight, per chain:
/// - the clone factory and ConfigRegistry are at their pinned code hashes;
/// - the vault, receipt and wrapper beacon names are bound to the chain's
///   production beacons (`LibBeaconInvariants.prodBeaconsForChainId`), the
///   ones the orchestrator's version lock covers;
/// - the vault and receipt beacons serve the implementations the orchestrator
///   pins, so this waits on the token beacon upgrade;
/// - each region's RBAC is bound, owned by the chain's governance timelock,
///   with the chain's authoriser for that region.
///
/// After the run, each token, receipt and wrapper is at its pin, and each
/// token reports the timelock as owner and its region's authoriser.
///
/// @dev Dispatch via `Actions → manual-broadcast` with
/// `script = 20261026-deploy-test-tokens` and `network` set to the chain.
contract DeployTestTokens is Script, IStoxScript {
    /// @inheritdoc IStoxScript
    function declaration() external pure returns (ScriptDeclaration memory) {
        return LibStoxMigrations.notAMigration();
    }

    /// @notice The chain's authoriser for a region.
    /// @param region The region.
    /// @return The authoriser.
    function regionAuthoriser(Region region) public view returns (address) {
        return region == Region.EU
            ? LibAuthoriserInvariants.euAuthoriserForChainId(block.chainid)
            : LibAuthoriserInvariants.authoriserForChainId(block.chainid);
    }

    /// @notice Reverts unless the chain is ready for the test tokens.
    function preflight() public view {
        assertDeployed(
            LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS, LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_CODEHASH
        );
        assertDeployed(
            LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS,
            LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH
        );

        address[4] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(block.chainid);
        address vaultBeacon = assertBeaconBinding(
            LibStoxConfig.VAULT_BEACON_NAME, beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX]
        );
        address receiptBeacon =
            assertBeaconBinding(LibStoxConfig.RECEIPT_BEACON_NAME, beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX]);
        assertBeaconBinding(
            LibStoxConfig.WRAPPER_BEACON_NAME, beacons[LibBeaconInvariants.WRAPPED_TOKEN_VAULT_BEACON_INDEX]
        );
        assertBeaconServes(vaultBeacon, LibProdDeployCurrent.STOX_RECEIPT_VAULT);
        assertBeaconServes(receiptBeacon, LibProdDeployCurrent.STOX_RECEIPT);

        assertRbac(Region.US);
        assertRbac(Region.EU);
    }

    /// @notice Reverts unless `target` has code hashing to `codehash`.
    /// @param target The pinned address.
    /// @param codehash The pinned code hash.
    function assertDeployed(address target, bytes32 codehash) internal view {
        if (target.codehash != codehash) {
            revert DependencyNotDeployed(target, codehash, target.codehash);
        }
    }

    /// @notice Reverts unless `name` is bound to `expected` under the root
    /// authority.
    /// @param name The beacon name.
    /// @param expected The chain's production beacon.
    /// @return The bound beacon.
    function assertBeaconBinding(bytes32 name, address expected) internal view returns (address) {
        address bound = LibICloneableFactoryV6.resolveBeacon(
            LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS, LibStoxConfig.ROOT_AUTHORITY, name
        );
        if (bound != expected) {
            revert BeaconBindingMismatch(name, expected, bound);
        }
        return bound;
    }

    /// @notice Reverts unless `beacon` serves `expected`.
    /// @param beacon The beacon.
    /// @param expected The implementation the orchestrator pins.
    function assertBeaconServes(address beacon, address expected) internal view {
        address actual = IBeacon(beacon).implementation();
        if (actual != expected) {
            revert BeaconImplementationMismatch(beacon, expected, actual);
        }
    }

    /// @notice Reverts unless `region`'s RBAC is bound, owned by the chain's
    /// timelock, with the chain's authoriser for `region`.
    /// @param region The region.
    function assertRbac(Region region) internal view {
        bytes32 name = LibStoxConfig.rbacName(region);
        // When the binding was written does not matter here.
        //slither-disable-next-line unused-return
        (bytes memory value,) = IConfigRegistryV3(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
            .getV3(LibStoxConfig.ROOT_AUTHORITY, name);
        OffchainAssetReceiptVaultRbacV1 memory rbac =
            LibOffchainAssetReceiptVaultRbac.decodeCanonical(LibStoxConfig.ROOT_AUTHORITY, name, value);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        if (rbac.owner != timelock) {
            revert RbacOwnerMismatch(region, timelock, rbac.owner);
        }
        address authoriser = regionAuthoriser(region);
        if (address(rbac.authorizer) != authoriser) {
            revert RbacAuthoriserMismatch(region, authoriser, address(rbac.authorizer));
        }
    }

    /// @notice Builds `region`'s token and wrapper where they are not yet at
    /// their pins.
    /// @param region The region.
    function build(Region region) internal {
        TestTokenAddresses memory pinned = LibStoxTestTokens.addresses(region);
        ICloneableFactoryV6 factory = ICloneableFactoryV6(LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS);
        if (pinned.token.code.length == 0) {
            address token = factory.registryBeaconProxy(
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.VAULT_BEACON_NAME,
                LibStoxTestTokens.vaultData(region),
                bytes32(0)
            );
            if (token != pinned.token) {
                revert TestTokenOffPin(region, pinned.token, token);
            }
        }
        if (pinned.wrapper.code.length == 0) {
            address wrapper = factory.registryBeaconProxy(
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.WRAPPER_BEACON_NAME,
                abi.encode(pinned.token),
                bytes32(0)
            );
            if (wrapper != pinned.wrapper) {
                revert TestTokenOffPin(region, pinned.wrapper, wrapper);
            }
        }
    }

    /// @notice Reverts unless `region`'s token, receipt and wrapper are at
    /// their pins, and the token has the timelock as owner and its region's
    /// authoriser.
    /// @param region The region.
    function assertLanded(Region region) public view {
        TestTokenAddresses memory pinned = LibStoxTestTokens.addresses(region);
        if (pinned.token.code.length == 0) {
            revert TestTokenNotLanded(region, pinned.token);
        }
        if (address(IReceiptVaultV3(payable(pinned.token)).receipt()) != pinned.receipt) {
            revert TestTokenNotLanded(region, pinned.receipt);
        }
        if (pinned.wrapper.code.length == 0 || IERC4626(pinned.wrapper).asset() != pinned.token) {
            revert TestTokenNotLanded(region, pinned.wrapper);
        }
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        address owner = Ownable(pinned.token).owner();
        if (owner != timelock) {
            revert TestTokenOwnerMismatch(region, timelock, owner);
        }
        address authoriser = regionAuthoriser(region);
        address authorizer = address(IAuthorizableV1(pinned.token).authorizer());
        if (authorizer != authoriser) {
            revert TestTokenAuthoriserMismatch(region, authoriser, authorizer);
        }
    }

    /// @notice Pre-flights the chain, builds both regions' test tokens from the
    /// broadcaster, and checks they landed.
    function run() external {
        preflight();
        vm.startBroadcast();
        build(Region.US);
        build(Region.EU);
        vm.stopBroadcast();
        assertLanded(Region.US);
        assertLanded(Region.EU);
        for (uint256 i = 0; i < 2; i++) {
            Region region = Region(i);
            TestTokenAddresses memory pinned = LibStoxTestTokens.addresses(region);
            console2.log(region == Region.EU ? "EU" : "US");
            console2.log("  token:", pinned.token);
            console2.log("  receipt:", pinned.receipt);
            console2.log("  wrapper:", pinned.wrapper);
        }
    }
}
