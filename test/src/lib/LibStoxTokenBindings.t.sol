// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.29/src/lib/LibRainDeploy.sol";
import {LibConfigRegistry} from "rain-deploy-0.1.29/src/lib/LibConfigRegistry.sol";
import {IAuthorizeV1} from "rain-vats-0.2.16/src/interface/IAuthorizeV1.sol";
import {
    OffchainAssetReceiptVaultRbacV1,
    OFFCHAIN_ASSET_RECEIPT_VAULT_RBAC_V1_VALUE_TYPE,
    OFFCHAIN_ASSET_RECEIPT_VAULT_RBAC_V1_VALUE_TYPE_HASH
} from "rain-vats-0.2.16/src/lib/LibOffchainAssetReceiptVaultRbac.sol";

import {LibStoxTokenBindings, TokenBindingMismatch} from "../../../src/lib/LibStoxTokenBindings.sol";
import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";
import {LibAuthoriserInvariants} from "../../../src/lib/LibAuthoriserInvariants.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";

/// @title LibStoxTokenBindingsTest
/// @notice On a local ConfigRegistry, the token-binding check accepts the
/// root's bindings when they resolve, typed, to the declared beacon and to
/// each region's RBAC of the bound governance timelock and that region's
/// authoriser, and refuses each field that differs.
contract LibStoxTokenBindingsTest is Test {
    function externalCheck(string memory network, address beacon) external view {
        LibStoxTokenBindings.check(network, beacon);
    }

    function networks() internal pure returns (SupportedNetwork[] memory) {
        return LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
    }

    function bind(bytes32 name, string memory valueType, bytes memory value) internal {
        LibTestDeploy.bind(vm, LibStoxConfig.ROOT_AUTHORITY, name, valueType, value);
    }

    function bindRbac(bytes32 name, address owner, address authorizer) internal {
        bind(
            name,
            OFFCHAIN_ASSET_RECEIPT_VAULT_RBAC_V1_VALUE_TYPE,
            abi.encode(OffchainAssetReceiptVaultRbacV1({owner: owner, authorizer: IAuthorizeV1(authorizer)}))
        );
    }

    /// Selects `chainId` and binds the declared beacon, the timelock and both
    /// regions' RBAC as the declaration expects there.
    function bindDeclared(uint256 chainId, address beacon, address timelock) internal {
        vm.chainId(chainId);
        bind(LibStoxConfig.VAULT_BEACON_NAME, "address", abi.encode(beacon));
        bind(LibStoxConfig.GOVERNANCE_TIMELOCK_NAME, "address", abi.encode(timelock));
        bindRbac(LibStoxConfig.RBAC_US_NAME, timelock, LibAuthoriserInvariants.authoriserForChainId(chainId));
        bindRbac(LibStoxConfig.RBAC_EU_NAME, timelock, LibAuthoriserInvariants.euAuthoriserForChainId(chainId));
    }

    function expectMismatch(string memory network, bytes32 name, string memory field, address expected, address actual)
        internal
    {
        vm.expectRevert(abi.encodeWithSelector(TokenBindingMismatch.selector, network, name, field, expected, actual));
    }

    function setUp() external {
        LibTestDeploy.etchConfigRegistry(vm);
    }

    function testAcceptsBindingsThatResolveToTheDeclarationOnEveryNetwork(address beacon, address timelock) external {
        SupportedNetwork[] memory declared = networks();
        for (uint256 i = 0; i < declared.length; i++) {
            bindDeclared(declared[i].chainId, beacon, timelock);
            this.externalCheck(declared[i].name, beacon);
        }
    }

    function testRefusesAVaultBeaconBindingOtherThanTheDeclaredBeacon(address beacon, address bound, address timelock)
        external
    {
        vm.assume(bound != beacon);
        SupportedNetwork[] memory declared = networks();
        for (uint256 i = 0; i < declared.length; i++) {
            bindDeclared(declared[i].chainId, beacon, timelock);
            bind(LibStoxConfig.VAULT_BEACON_NAME, "address", abi.encode(bound));
            expectMismatch(declared[i].name, LibStoxConfig.VAULT_BEACON_NAME, "beacon", beacon, bound);
            this.externalCheck(declared[i].name, beacon);
        }
    }

    function testRefusesAUsRbacOwnerOtherThanTheGovernanceTimelock(address beacon, address timelock, address owner)
        external
    {
        vm.assume(owner != timelock);
        SupportedNetwork[] memory declared = networks();
        for (uint256 i = 0; i < declared.length; i++) {
            bindDeclared(declared[i].chainId, beacon, timelock);
            bindRbac(
                LibStoxConfig.RBAC_US_NAME, owner, LibAuthoriserInvariants.authoriserForChainId(declared[i].chainId)
            );
            expectMismatch(declared[i].name, LibStoxConfig.RBAC_US_NAME, "owner", timelock, owner);
            this.externalCheck(declared[i].name, beacon);
        }
    }

    function testRefusesAUsRbacAuthorizerOtherThanTheUsAuthoriser(address beacon, address timelock, address authorizer)
        external
    {
        SupportedNetwork[] memory declared = networks();
        for (uint256 i = 0; i < declared.length; i++) {
            address expected = LibAuthoriserInvariants.authoriserForChainId(declared[i].chainId);
            vm.assume(authorizer != expected);
            bindDeclared(declared[i].chainId, beacon, timelock);
            bindRbac(LibStoxConfig.RBAC_US_NAME, timelock, authorizer);
            expectMismatch(declared[i].name, LibStoxConfig.RBAC_US_NAME, "authorizer", expected, authorizer);
            this.externalCheck(declared[i].name, beacon);
        }
    }

    function testRefusesAnEuRbacOwnerOtherThanTheGovernanceTimelock(address beacon, address timelock, address owner)
        external
    {
        vm.assume(owner != timelock);
        SupportedNetwork[] memory declared = networks();
        for (uint256 i = 0; i < declared.length; i++) {
            bindDeclared(declared[i].chainId, beacon, timelock);
            bindRbac(
                LibStoxConfig.RBAC_EU_NAME, owner, LibAuthoriserInvariants.euAuthoriserForChainId(declared[i].chainId)
            );
            expectMismatch(declared[i].name, LibStoxConfig.RBAC_EU_NAME, "owner", timelock, owner);
            this.externalCheck(declared[i].name, beacon);
        }
    }

    function testRefusesAnEuRbacAuthorizerOtherThanTheEuAuthoriser(address beacon, address timelock, address authorizer)
        external
    {
        SupportedNetwork[] memory declared = networks();
        for (uint256 i = 0; i < declared.length; i++) {
            address expected = LibAuthoriserInvariants.euAuthoriserForChainId(declared[i].chainId);
            vm.assume(authorizer != expected);
            bindDeclared(declared[i].chainId, beacon, timelock);
            bindRbac(LibStoxConfig.RBAC_EU_NAME, timelock, authorizer);
            expectMismatch(declared[i].name, LibStoxConfig.RBAC_EU_NAME, "authorizer", expected, authorizer);
            this.externalCheck(declared[i].name, beacon);
        }
    }

    /// The US authoriser in the EU binding, as a swapped region would bind it.
    function testRefusesTheUsAuthoriserInTheEuRbac(address beacon, address timelock) external {
        SupportedNetwork[] memory declared = networks();
        for (uint256 i = 0; i < declared.length; i++) {
            address us = LibAuthoriserInvariants.authoriserForChainId(declared[i].chainId);
            address eu = LibAuthoriserInvariants.euAuthoriserForChainId(declared[i].chainId);
            bindDeclared(declared[i].chainId, beacon, timelock);
            bindRbac(LibStoxConfig.RBAC_EU_NAME, timelock, us);
            expectMismatch(declared[i].name, LibStoxConfig.RBAC_EU_NAME, "authorizer", eu, us);
            this.externalCheck(declared[i].name, beacon);
        }
    }

    function testRefusesAVaultBeaconBindingThatIsNotAnAddress(address beacon, address timelock) external {
        bindDeclared(LibSafeInvariants.BASE_CHAIN_ID, beacon, timelock);
        bind(LibStoxConfig.VAULT_BEACON_NAME, "bytes32", abi.encode(beacon));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.ValueTypeMismatch.selector,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.VAULT_BEACON_NAME,
                keccak256("address"),
                keccak256("bytes32")
            )
        );
        this.externalCheck(LibRainDeploy.BASE, beacon);
    }

    function testRefusesATimelockBindingThatIsNotAnAddress(address beacon, address timelock) external {
        bindDeclared(LibSafeInvariants.BASE_CHAIN_ID, beacon, timelock);
        bind(LibStoxConfig.GOVERNANCE_TIMELOCK_NAME, "bytes32", abi.encode(timelock));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.ValueTypeMismatch.selector,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.GOVERNANCE_TIMELOCK_NAME,
                keccak256("address"),
                keccak256("bytes32")
            )
        );
        this.externalCheck(LibRainDeploy.BASE, beacon);
    }

    function testRefusesAnRbacBindingThatIsNotAnRbac(address beacon, address timelock) external {
        bindDeclared(LibSafeInvariants.BASE_CHAIN_ID, beacon, timelock);
        bind(LibStoxConfig.RBAC_US_NAME, "address", abi.encode(timelock));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.ValueTypeMismatch.selector,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.RBAC_US_NAME,
                OFFCHAIN_ASSET_RECEIPT_VAULT_RBAC_V1_VALUE_TYPE_HASH,
                keccak256("address")
            )
        );
        this.externalCheck(LibRainDeploy.BASE, beacon);
    }
}
