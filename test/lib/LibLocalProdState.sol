// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.29/src/lib/LibRainDeploy.sol";
import {LibSafe} from "rain-deploy-0.1.29/src/lib/LibSafe.sol";

import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {IAuthorisable} from "../../src/interface/IAuthorisable.sol";
import {IST0xOrchestratorBeaconSetDeployerV1} from "../../src/interface/IST0xOrchestratorBeaconSetDeployerV1.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibBeaconInvariants} from "../../src/lib/LibBeaconInvariants.sol";
import {LibEuAuthoriserClone} from "../../src/lib/LibEuAuthoriserClone.sol";
import {ContractRoles, LibIdealRoles} from "../../src/lib/LibIdealRoles.sol";
import {LibOrchestratorInvariants} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibProdBeacons0_1_1} from "../../src/lib/LibProdBeacons0_1_1.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "../../src/lib/LibTokenInvariants.sol";

/// @title LibLocalProdState
/// @notice A supported chain's production state built in the local EVM at the
/// pinned addresses, one facet per function, every value read from `src`.
/// Facets deploy their own Zoltu dependencies, so any subset composes.
library LibLocalProdState {
    /// @notice The chain id of every deployment network, in declaration order.
    function chainIds() internal pure returns (uint256[] memory) {
        SupportedNetwork[] memory networks =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        uint256[] memory ids = new uint256[](networks.length);
        for (uint256 i = 0; i < networks.length; i++) {
            ids[i] = networks[i].chainId;
        }
        return ids;
    }

    /// @notice Every facet on `chainId`, with the active chain id set to it.
    function build(Vm vm, uint256 chainId) internal {
        vm.clearMockedCalls();
        vm.chainId(chainId);
        safe(vm, chainId, LibSafeInvariants.expectedOwners());
        timelock(vm, chainId);
        beacons(vm, chainId);
        authorisers(vm, chainId);
        tokens(vm, chainId);
        orchestrator(vm, chainId);
    }

    /// @notice The chain's token-owner Safe: a v1.4.1 proxy over the chain's
    /// singleton, set up with `owners` at the pinned threshold and the
    /// compatibility fallback handler.
    function safe(Vm vm, uint256 chainId, address[] memory owners) internal returns (Safe) {
        // Ethereum's `setupToL2` keeps the L1 singleton; every other chain switches to L2.
        (address singleton, bytes memory singletonCode) = chainId == LibSafeInvariants.ETHEREUM_CHAIN_ID
            ? (LibSafe.SAFE_V1_4_1_L1_SINGLETON, LibSafe.SAFE_V1_4_1_L1_SINGLETON_RUNTIME_CODE)
            : (LibSafe.SAFE_V1_4_1_L2_SINGLETON, LibSafe.SAFE_V1_4_1_L2_SINGLETON_RUNTIME_CODE);
        vm.etch(singleton, singletonCode);
        vm.etch(
            LibSafe.SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER,
            LibSafe.SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER_RUNTIME_CODE
        );

        Safe chainSafe = Safe(payable(LibSafeInvariants.safeForChainId(chainId)));
        vm.etch(address(chainSafe), LibSafe.SAFE_V1_4_1_PROXY_RUNTIME_CODE);
        vm.store(address(chainSafe), bytes32(0), bytes32(uint256(uint160(singleton))));
        chainSafe.setup(
            owners,
            LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD,
            address(0),
            "",
            LibSafe.SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER,
            address(0),
            0,
            payable(address(0))
        );
        return chainSafe;
    }

    /// @notice The chain's governance timelock, Zoltu-deployed from the
    /// pinned init code with the chain's Safe as proposer.
    function timelock(Vm vm, uint256 chainId) internal returns (address) {
        LibRainDeploy.etchZoltuFactory(vm);
        return deployOnce(
            LibTimelockInvariants.timelockInitCode(LibSafeInvariants.safeForChainId(chainId)),
            LibTimelockInvariants.timelockForChainId(chainId)
        );
    }

    /// @notice The chain's four in-use beacons, each serving its expected
    /// implementation and owned by the chain's timelock. Base's V1 beacons
    /// carry the runtime and storage of their local 0.1.1 counterparts.
    function beacons(Vm vm, uint256 chainId) internal {
        LibRainDeploy.etchZoltuFactory(vm);
        deployOnce(LibProdDeployV4.STOX_RECEIPT_CREATION_CODE_0_1_1, LibProdDeployV4.STOX_RECEIPT_0_1_1);
        deployOnce(LibProdDeployV4.STOX_RECEIPT_VAULT_CREATION_CODE_0_1_1, LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_1);
        deployOnce(
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_CREATION_CODE_0_1_1, LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_0_1_1
        );
        deployOnce(
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CREATION_CODE_0_1_1,
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1
        );
        deployOnce(
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_CREATION_CODE_0_1_1,
            LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_0_1_1
        );
        deployReceiptSet0_1_30();
        deployOrchestratorSet0_1_30();

        address[4] memory local = LibProdBeacons0_1_1.beacons();
        address[4] memory live = LibBeaconInvariants.prodBeaconsForChainId(chainId);
        address[4] memory impls = LibBeaconInvariants.prodExpectedImplementationsForChainId(chainId);
        address chainTimelock = LibTimelockInvariants.timelockForChainId(chainId);
        for (uint256 i = 0; i < live.length; i++) {
            if (live[i] != local[i]) {
                vm.etch(live[i], local[i].code);
                vm.copyStorage(local[i], live[i]);
            }
            UpgradeableBeacon beacon = UpgradeableBeacon(live[i]);
            address owner = beacon.owner();
            if (beacon.implementation() != impls[i]) {
                vm.prank(owner);
                beacon.upgradeTo(impls[i]);
            }
            if (owner != chainTimelock) {
                vm.prank(owner);
                beacon.transferOwnership(chainTimelock);
            }
        }
    }

    /// @notice The chain's US and EU authoriser clones: the EIP-1167 runtime
    /// over the audited 0.1.1 authoriser at each pinned address, holding
    /// exactly the `LibIdealRoles` pairs.
    function authorisers(Vm vm, uint256 chainId) internal {
        LibRainDeploy.etchZoltuFactory(vm);
        deployOnce(
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CREATION_CODE_0_1_1,
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1
        );
        address us = LibAuthoriserInvariants.authoriserForChainId(chainId);
        address eu = LibAuthoriserInvariants.euAuthoriserForChainId(chainId);
        bytes memory cloneCode = LibEuAuthoriserClone.cloneRuntimeCode();
        vm.etch(us, cloneCode);
        vm.etch(eu, cloneCode);

        ContractRoles[] memory roles = LibIdealRoles.contractRoles(chainId);
        for (uint256 i = 0; i < roles.length; i++) {
            if (roles[i].target != us && roles[i].target != eu) continue;
            for (uint256 j = 0; j < roles[i].expected.length; j++) {
                vm.mockCall(
                    roles[i].target,
                    abi.encodeCall(IAccessControl.hasRole, (roles[i].expected[j].role, roles[i].expected[j].grantee)),
                    abi.encode(true)
                );
            }
        }
    }

    /// @notice Every production receipt vault on the chain reports its
    /// expected authoriser.
    function tokens(Vm vm, uint256 chainId) internal {
        TokenInstance[] memory table = LibTokenInvariants.productionTokensForChainId(chainId);
        address us = LibAuthoriserInvariants.authoriserForChainId(chainId);
        for (uint256 i = 0; i < table.length; i++) {
            vm.mockCall(
                table[i].receiptVault,
                abi.encodeCall(IAuthorisable.authorizer, ()),
                abi.encode(LibTokenInvariants.expectedAuthoriser(table[i].underlying, us, chainId))
            );
        }
    }

    /// @notice The orchestrator instance: the 0.1.30 set deployer's first
    /// `deploy`, administered by the chain's timelock, over the 0.1.30
    /// receipt set its vault-logic lock reads.
    function orchestrator(Vm vm, uint256 chainId) internal {
        LibRainDeploy.etchZoltuFactory(vm);
        deployReceiptSet0_1_30();
        deployOrchestratorSet0_1_30();
        if (LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE.code.length == 0) {
            IST0xOrchestratorBeaconSetDeployerV1(LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_30)
                .deploy(LibTimelockInvariants.timelockForChainId(chainId));
        }
    }

    function deployReceiptSet0_1_30() private {
        deployOnce(LibProdDeployV4.STOX_RECEIPT_CREATION_CODE_0_1_30, LibProdDeployV4.STOX_RECEIPT_0_1_30);
        deployOnce(LibProdDeployV4.STOX_RECEIPT_VAULT_CREATION_CODE_0_1_30, LibProdDeployV4.STOX_RECEIPT_VAULT_0_1_30);
        deployOnce(
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_CREATION_CODE_0_1_30,
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_30
        );
    }

    function deployOrchestratorSet0_1_30() private {
        deployOnce(LibProdDeployV4.ST0X_ORCHESTRATOR_CREATION_CODE_0_1_30, LibProdDeployV4.ST0X_ORCHESTRATOR_0_1_30);
        deployOnce(
            LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_CREATION_CODE_0_1_30,
            LibProdDeployV4.ST0X_ORCHESTRATOR_BEACON_SET_DEPLOYER_0_1_30
        );
    }

    function deployOnce(bytes memory creationCode, address pinned) private returns (address) {
        return pinned.code.length == 0 ? LibRainDeploy.deployZoltu(creationCode) : pinned;
    }
}
