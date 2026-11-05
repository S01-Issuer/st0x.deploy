// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IMulticall3} from "forge-std-1.17.0/src/interfaces/IMulticall3.sol";
import {DeployDeclaration, DeploySuite} from "rain-deploy-0.1.30/src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {LibConfigRegistryRegister} from "rain-deploy-0.1.30/src/lib/LibConfigRegistryRegister.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {DEPLOYED_ADDRESS as CONFIG_REGISTRY_ADDRESS} from "rain-deploy-0.1.30/src/generated/0_1_29/ConfigRegistry.sol";
import {IAuthorizeV1} from "rain-vats-0.2.20/src/interface/IAuthorizeV1.sol";
import {
    OffchainAssetReceiptVaultRbacV1,
    OFFCHAIN_ASSET_RECEIPT_VAULT_RBAC_V1_VALUE_TYPE
} from "rain-vats-0.2.20/src/lib/LibOffchainAssetReceiptVaultRbac.sol";

import {StoxDeploySuites} from "../../src/abstract/StoxDeploySuites.sol";
import {StoxReceiptVault} from "../../src/concrete/StoxReceiptVault.sol";
import {LibProdDeployCurrent} from "../../src/generated/LibProdDeployCurrent.sol";
import {IStoxAssetIdV1} from "../../src/interface/IStoxAssetIdV1.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibProdTokenConfig, Region, TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {LibProdTokenParams} from "../../src/lib/LibProdTokenParams.sol";
import {LibListing, LISTING_AUTHORITY, LISTING_SIGNER_NAME} from "../../src/lib/LibListing.sol";
import {LibListingTree, ListingRow} from "../../src/lib/LibListingTree.sol";
import {ST0X_NAME_SUFFIX} from "../../src/lib/LibUnderlying.sol";
import {LibTestListingMulticall, MULTICALL3} from "../lib/LibTestListingMulticall.sol";
import {DeployPreDeployCheckHarness} from "../script/DeployPreDeployCheckHarness.sol";

/// @title V6ReleaseBaseFork
/// @notice A Base fork pinned at `BASE_BLOCK`, where no V6 registry name is bound and no V6 suite is deployed, and the
/// release the V6 path needs on it: each name bound as the root authority and each suite deployed through the real
/// `Deploy` pre-flight, with each token deployed and named from a test-signed listing in one Multicall3 transaction.
/// @dev Each suite runs the broadcaster's chain id and dependency checks and `preDeployCheck`, not its seat checks.
abstract contract V6ReleaseBaseFork is Test, StoxDeploySuites {
    /// A Base block before any V6 binding or deploy.
    uint256 internal constant BASE_BLOCK = 53585734;

    address internal constant DEPLOYER = address(uint160(uint256(keccak256("st0x.test.v6-tokens-base-fork.deployer"))));

    /// The test key that signs listings on the fork.
    uint256 internal constant LISTING_SIGNER_KEY = uint256(keccak256("st0x.test.v6-tokens-base-fork.listing-signer"));

    DeployPreDeployCheckHarness internal harness;
    SupportedNetwork internal base;

    /// Selects the pinned Base fork and the harness that runs the real `Deploy` pre-flight.
    function forkBase() internal {
        vm.createSelectFork(LibRainDeploy.BASE, BASE_BLOCK);
        harness = new DeployPreDeployCheckHarness();
        SupportedNetwork[] memory networks = harness.deployNetworkConfigs();
        for (uint256 i = 0; i < networks.length; i++) {
            if (networks[i].chainId == block.chainid) {
                base = networks[i];
            }
        }
        assertEq(base.chainId, LibSafeInvariants.BASE_CHAIN_ID, "base network");
    }

    /// Whether the root authority has bound `name`; only the registry's `NameNotRegistered` reads as unbound.
    function isBound(bytes32 name) internal view returns (bool) {
        (, uint256 registeredAt,) = LibConfigRegistryRegister.currentBinding(LibRegistryAuthority.ROOT_AUTHORITY, name);
        return registeredAt != 0;
    }

    /// Binds `name` as the root authority; it is unbound at the pinned block.
    function bind(bytes32 name, string memory valueType, bytes memory value) internal {
        assertFalse(isBound(name), "bound at the pinned block");
        vm.warp(vm.getBlockTimestamp() + 1);
        vm.prank(LibRegistryAuthority.ROOT_AUTHORITY);
        IConfigRegistryV5(CONFIG_REGISTRY_ADDRESS)
            .registerV5(LibRegistryAuthority.ROOT_AUTHORITY, name, valueType, value, "");
    }

    function bindRbac(bytes32 name, address authorizer) internal {
        bind(
            name,
            OFFCHAIN_ASSET_RECEIPT_VAULT_RBAC_V1_VALUE_TYPE,
            abi.encode(
                OffchainAssetReceiptVaultRbacV1({
                    owner: LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK, authorizer: IAuthorizeV1(authorizer)
                })
            )
        );
    }

    /// Deploys suite `name`, which has no code at the pinned block, after the broadcaster's fork checks and the real
    /// pre-flight.
    function dispatch(DeployDeclaration memory declared, string memory name) internal returns (address) {
        DeploySuite memory suite = checkedSuite(declared, name);
        address deployed =
            deployStep(declared, suite)(vm, base.name, DEPLOYER, deployStepData(declared, suite, base.chainId));
        assertEq(deployed, suite.storedDeployedAddress, name);
        assertEq(deployed.codehash, suite.storedBytecodeHash, name);
        return deployed;
    }

    /// Suite `name`, which has no code at the pinned block, after the broadcaster's fork checks and the real pre-flight.
    function checkedSuite(DeployDeclaration memory declared, string memory name) internal returns (DeploySuite memory) {
        DeploySuite memory suite = suiteByName(declared, name);
        assertEq(suite.storedDeployedAddress.code.length, 0, name);
        LibRainDeploy.selectCheckedFork(vm, base, vm.activeFork(), suite.dependencies);
        harness.exposedPreDeployCheck(suite, base);
        return suite;
    }

    /// The release: the timelock, the implementations and the beacons, with their registry names.
    function deployRelease(DeployDeclaration memory declared) internal {
        bind(
            LibStoxConfig.TIMELOCK_INITIAL_PROPOSER_NAME,
            "address",
            abi.encode(LibSafeInvariants.safeForChainId(base.chainId))
        );
        assertEq(dispatch(declared, GOVERNANCE_TIMELOCK), LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK, "timelock");
        bind(
            LibStoxConfig.BEACON_INITIAL_OWNER_NAME,
            "address",
            abi.encode(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK)
        );
        dispatch(declared, FACET);
        dispatch(declared, RECEIPT);
        dispatch(declared, RECEIPT_VAULT);
        address receiptBeacon = dispatch(declared, RECEIPT_BEACON);
        address vaultBeacon = dispatch(declared, RECEIPT_VAULT_BEACON);
        bind(LibStoxConfig.VAULT_BEACON_NAME, "address", abi.encode(vaultBeacon));
        bind(LibStoxConfig.RECEIPT_BEACON_NAME, "address", abi.encode(receiptBeacon));
        bindRbac(LibStoxConfig.RBAC_US_NAME, LibAuthoriserInvariants.authoriserForChainId(base.chainId));
        bindRbac(LibStoxConfig.RBAC_EU_NAME, LibAuthoriserInvariants.euAuthoriserForChainId(base.chainId));
    }

    function deployReleaseFrame() external {
        deployRelease(declaration());
    }

    /// The test listing signer, bound under the governance timelock as the timelock.
    function bindListingSigner() internal {
        vm.warp(vm.getBlockTimestamp() + 1);
        vm.prank(LISTING_AUTHORITY);
        IConfigRegistryV5(CONFIG_REGISTRY_ADDRESS)
            .registerV5(LISTING_AUTHORITY, LISTING_SIGNER_NAME, "address", abi.encode(vm.addr(LISTING_SIGNER_KEY)), "");
    }

    /// The listing of every production row.
    function listing() internal pure returns (ListingRow[] memory) {
        return LibListingTree.rows(LibProdTokenConfig.productionTokenConfigs());
    }

    /// `key`'s signature over `root`'s listing digest.
    function signListing(uint256 key, bytes32 root) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, LibListing.digest(root));
        return abi.encodePacked(r, s, v);
    }

    /// The row's token has its asset id, its listed name and symbol, the timelock as owner and its region's authorizer.
    function assertNamed(TokenConfig memory config, address token) internal view {
        StoxReceiptVault vault = StoxReceiptVault(payable(token));
        assertEq(IStoxAssetIdV1(token).assetId(), config.assetId, config.underlying);
        assertEq(vault.symbol(), config.symbol, config.underlying);
        assertEq(vault.name(), string.concat(config.underlyingName, ST0X_NAME_SUFFIX), config.underlying);
        assertEq(vault.owner(), LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK, config.underlying);
        assertEq(
            address(vault.authorizer()),
            config.region == Region.US
                ? LibAuthoriserInvariants.authoriserForChainId(base.chainId)
                : LibAuthoriserInvariants.euAuthoriserForChainId(base.chainId),
            config.underlying
        );
    }

    /// One row's token suite, through the broadcaster's fork checks and the real pre-flight, deployed and named from
    /// the signed listing in one `aggregate3`, in its own call frame: the declaration is large and memory is only freed
    /// when a frame returns.
    function deployAndNameRow(uint256 index) external returns (address) {
        return deployAndName(LibProdTokenConfig.productionTokenConfigs()[index], listing(), index);
    }

    /// `config`'s token suite, through the fork checks and the pre-flight, deployed and named from row `index` of
    /// `listed`, signed by the test listing signer, in one `aggregate3`.
    function deployAndName(TokenConfig memory config, ListingRow[] memory listed, uint256 index)
        internal
        returns (address)
    {
        DeploySuite memory suite = checkedSuite(declaration(), string.concat(TOKEN_PREFIX, lowercase(config.symbol)));
        bytes32 root = LibListingTree.root(listed);
        IMulticall3.Call3[] memory calls = LibTestListingMulticall.deployAndName(
            LibProdTokenParams.tokenParam(config),
            listed[index],
            LibListingTree.proof(listed, index),
            root,
            signListing(LISTING_SIGNER_KEY, root)
        );
        vm.prank(DEPLOYER);
        IMulticall3.Result[] memory results = IMulticall3(MULTICALL3).aggregate3(calls);
        assertEq(abi.decode(results[0].returnData, (address)), suite.storedDeployedAddress, config.underlying);
        assertEq(listed[index].token, suite.storedDeployedAddress, config.underlying);
        assertEq(suite.storedDeployedAddress.codehash, suite.storedBytecodeHash, config.underlying);
        assertNamed(config, suite.storedDeployedAddress);
        return suite.storedDeployedAddress;
    }
}
