// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {SafeProxyFactory} from "safe-global-safe-smart-account-1.4.1-3/contracts/proxies/SafeProxyFactory.sol";
import {DeployDependency, DeploySuite} from "rain-deploy-0.1.38/src/abstract/RainDeploySuitesBase.sol";
import {MIGRATION_HEAD_GENESIS} from "rain-deploy-0.1.38/src/interface/IMigrationRegistryV5.sol";
import {LibRainDeploy} from "rain-deploy-0.1.38/src/lib/LibRainDeploy.sol";
import {LibSafe} from "rain-deploy-0.1.38/src/lib/LibSafe.sol";
import {LibSafeFork} from "rain-deploy-0.1.38/src/lib/LibSafeFork.sol";
import {ICloneableFactoryV4} from "rain-factory-0.2.18/src/interface/deprecated/ICloneableFactoryV4.sol";
import {
    CREATION_CODE as CLONE_FACTORY_0_1_15_CREATION_CODE,
    DEPLOYED_ADDRESS as CLONE_FACTORY_0_1_15
} from "rain-factory-deploy-0.2.14/src/generated/0_1_15/CloneFactory.sol";
import {
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.2.25/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";

import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibBeaconInvariants} from "../../src/lib/LibBeaconInvariants.sol";
import {EU_AUTHORISER_SALT} from "../../src/lib/LibEuAuthoriserClone.sol";
import {LibReleasedSuites} from "../../src/lib/LibReleasedSuites.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {US_AUTHORISER_SALT} from "../../src/lib/LibUsAuthoriserClone.sol";
import {RoleGrant} from "../../src/lib/RoleGrant.sol";
import {LibTestRootLine} from "../lib/LibTestRootLine.sol";
import {BackfillMigrationRegistryV5Harness} from "./BackfillMigrationRegistryV5Harness.sol";

/// @title ZerogTokenCreationFixture
/// @notice 0G at a pinned block, where none of this exists yet, brought to the state the token creation runs against:
/// the released 0.1.1 and 0.1.30 suites through the live Zoltu factory, the token-owner Safe from the live v1.4.1
/// factory at its pinned address with the policy threshold, its timelock, the beacons repointed and handed to it as
/// rainlang.eth would, the US and EU authoriser clones at their 0G pins with the role maps `LibIdealRoles` expects and
/// the timelock as admin, and a `MigrationRegistry` whose root approves the Safe, with 0G's root line still empty.
abstract contract ZerogTokenCreationFixture is Test {
    uint256 internal constant ZEROG_BLOCK = 50746000;

    function buildZerog() internal {
        vm.createSelectFork(LibStoxDeployNetworks.ZEROG, ZEROG_BLOCK);
        deployReleased("stox-receipt@0_1_1");
        deployReleased("stox-corporate-actions-facet@0_1_1");
        deployReleased("stox-receipt-vault@0_1_1");
        deployReleased("stox-wrapped-token-vault@0_1_1");
        deployReleased("stox-wrapped-token-vault-beacon@0_1_1");
        deployReleased("stox-wrapped-token-vault-beacon-set-deployer@0_1_1");
        deployReleased("stox-offchain-asset-receipt-vault-beacon-set-deployer@0_1_1");
        deployReleased("stox-unified-deployer@0_1_1");
        deployReleased("stox-corporate-actions-facet@0_1_30");
        deployReleased("stox-receipt@0_1_30");
        deployReleased("stox-receipt-vault@0_1_30");
        deployReleased("stox-orchestrator@0_1_30");
        deployReleased("stox-orchestrator-beacon-set-deployer@0_1_30");
        deployReleased("stox-offchain-asset-receipt-vault-authorizer@0_1_1");

        address safe = address(
            SafeProxyFactory(LibSafe.SAFE_V1_4_1_PROXY_FACTORY)
                .createProxyWithNonce(
                    LibSafe.SAFE_V1_4_1_L1_SINGLETON,
                    LibSafeInvariants.tokenOwnerSafeInitializer(),
                    LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_CREATION_SALT_NONCE
                )
        );
        assertEq(safe, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ZEROG, "Safe at its pinned address");
        vm.prank(safe);
        Safe(payable(safe)).changeThreshold(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD);

        address timelock = LibRainDeploy.deployZoltu(LibTimelockInvariants.timelockInitCode(safe));
        assertEq(timelock, LibTimelockInvariants.STOX_GOVERNANCE_TIMELOCK_ZEROG, "timelock at its pinned address");
        handBeaconsTo(timelock);
        buildAuthorisers(safe, timelock);

        LibTestRootLine.etchRegistry(vm);
        LibTestRootLine.approve(vm, safe);
    }

    /// @notice What rainlang.eth signs on 0G before any token exists: the receipt and receipt-vault beacons onto
    /// 0.1.30, then all four beacons to the timelock.
    /// @param timelock The 0G timelock.
    function handBeaconsTo(address timelock) internal {
        address[4] memory beacons = LibBeaconInvariants.prodBeaconsForChainId(LibSafeInvariants.ZEROG_CHAIN_ID);
        vm.startPrank(LibProdDeployV4.BEACON_INITIAL_OWNER);
        UpgradeableBeacon(beacons[LibBeaconInvariants.RECEIPT_BEACON_INDEX])
            .upgradeTo(LibProdDeployV4.STOX_RECEIPT_0_1_30);
        UpgradeableBeacon(beacons[LibBeaconInvariants.RECEIPT_VAULT_BEACON_INDEX])
            .upgradeTo(LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30);
        for (uint256 i = 0; i < beacons.length; i++) {
            Ownable(beacons[i]).transferOwnership(timelock);
        }
        vm.stopPrank();
    }

    /// @notice The two 0G authoriser clones at their open-salt addresses, each initialised with the Safe as admin,
    /// deployed here by a stranger since the address fixes the init data whoever deploys. The Safe then grants each
    /// clone's role map, with every `_ADMIN` on the timelock, and renounces its own `_ADMIN` roles.
    /// @param safe The 0G Safe.
    /// @param timelock The 0G timelock.
    function buildAuthorisers(address safe, address timelock) internal {
        address impl = LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1;
        bytes memory data = abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: safe}));

        assertEq(LibRainDeploy.deployZoltu(CLONE_FACTORY_0_1_15_CREATION_CODE), CLONE_FACTORY_0_1_15, "0.1.15 factory");
        vm.prank(address(0xBEEF));
        address us =
            ICloneableFactoryV4(CLONE_FACTORY_0_1_15).cloneDeterministicOpenSalt(impl, data, US_AUTHORISER_SALT);
        assertEq(us, LibAuthoriserInvariants.authoriserForChainId(LibSafeInvariants.ZEROG_CHAIN_ID), "US clone pin");

        vm.prank(address(0xBEEF));
        address eu =
            ICloneableFactoryV4(CLONE_FACTORY_0_1_15).cloneDeterministicOpenSalt(impl, data, EU_AUTHORISER_SALT);
        assertEq(eu, LibAuthoriserInvariants.euAuthoriserForChainId(LibSafeInvariants.ZEROG_CHAIN_ID), "EU clone pin");

        grantAndRenounce(
            us, LibAuthoriserInvariants.expectedGrantsOn(LibSafeInvariants.ZEROG_CHAIN_ID, safe, timelock), safe
        );
        grantAndRenounce(
            eu,
            LibAuthoriserInvariants.expectedEuGrants(
                timelock, LibAuthoriserInvariants.GRANTEE_EU_MINTER, LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C
            ),
            safe
        );
    }

    /// @notice As the Safe: grants every pair of `grants`, then renounces the `_ADMIN` roles that lead it.
    /// @param clone The clone.
    /// @param grants Its role map, `_ADMIN` roles first.
    /// @param safe The Safe, the clone's initial admin.
    function grantAndRenounce(address clone, RoleGrant[] memory grants, address safe) internal {
        vm.startPrank(safe);
        for (uint256 i = 0; i < grants.length; i++) {
            IAccessControl(clone).grantRole(grants[i].role, grants[i].grantee);
        }
        for (uint256 i = 0; i < LibAuthoriserInvariants.ADMIN_ROLE_COUNT; i++) {
            IAccessControl(clone).renounceRole(grants[i].role, safe);
        }
        vm.stopPrank();
    }

    /// @notice Zoltu-deploys the released suite `name` as `manual-sol-artifacts` would, etching any declared
    /// dependency not yet on the fork.
    /// @param name The suite.
    function deployReleased(string memory name) internal {
        DeploySuite[] memory suites = LibReleasedSuites.releasedSuites();
        for (uint256 i = 0; i < suites.length; i++) {
            if (keccak256(bytes(suites[i].suite)) != keccak256(bytes(name))) continue;
            DeployDependency[] memory dependencies = suites[i].dependencies;
            for (uint256 d = 0; d < dependencies.length; d++) {
                if (dependencies[d].deployedAddress.code.length == 0) {
                    vm.etch(dependencies[d].deployedAddress, dependencies[d].runtimeCode);
                }
            }
            assertEq(LibRainDeploy.deployZoltu(suites[i].creationCode), suites[i].storedDeployedAddress, name);
            assertEq(suites[i].storedDeployedAddress.codehash, suites[i].storedBytecodeHash, name);
            return;
        }
        revert(string.concat("no released suite ", name));
    }

    /// @notice The V5 backfill as the 0G Safe executes it before the token creation: 0G ran none of the history, so
    /// the bundle writes every earlier record record-only, then its own.
    function landZerogBackfill() internal {
        BackfillMigrationRegistryV5Harness backfill = new BackfillMigrationRegistryV5Harness("zerog-fixture");
        backfill.callPreflight();
        LibSafeFork.executeBundle(
            vm, Safe(payable(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ZEROG)), backfill.callAuthorBundle()
        );
        backfill.callAssertPostState();
        assertEq(LibStoxMigrations.head(), LibStoxMigrations.BACKFILL_MIGRATION_REGISTRY_V5, "0G line at the backfill");
    }

    /// @notice The history the backfill writes off Base, in its order, written by `safe` on a chain standing in for
    /// another: the line up to the backfill's own record.
    /// @param safe The writer.
    function writeOffBaseHistory(address safe) internal {
        bytes32[7] memory line = [
            LibStoxMigrations.MULTISIG_THRESHOLD,
            LibStoxMigrations.GOVERNANCE_TIMELOCK,
            LibStoxMigrations.GRANT_EU_AUTHORISER_ROLES,
            LibStoxMigrations.ORCHESTRATOR_EMERGENCY,
            LibStoxMigrations.TIMELOCK_REHEARSAL_SCHEDULE,
            LibStoxMigrations.TIMELOCK_REHEARSAL_CANCEL,
            LibStoxMigrations.EXECUTE_TIMELOCK_OPERATIONS
        ];
        bytes32 head = MIGRATION_HEAD_GENESIS;
        for (uint256 i = 0; i < line.length; i++) {
            LibTestRootLine.write(vm, safe, line[i], head);
            head = line[i];
        }
    }
}
