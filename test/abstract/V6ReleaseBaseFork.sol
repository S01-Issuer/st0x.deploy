// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeployDeclaration, DeploySuite} from "rain-deploy-0.1.30/src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {DEPLOYED_ADDRESS as CONFIG_REGISTRY_ADDRESS} from "rain-deploy-0.1.30/src/generated/0_1_29/ConfigRegistry.sol";
import {IAuthorizeV1} from "rain-vats-0.2.18/src/interface/IAuthorizeV1.sol";
import {
    OffchainAssetReceiptVaultRbacV1,
    OFFCHAIN_ASSET_RECEIPT_VAULT_RBAC_V1_VALUE_TYPE
} from "rain-vats-0.2.18/src/lib/LibOffchainAssetReceiptVaultRbac.sol";

import {StoxDeploySuites} from "../../src/abstract/StoxDeploySuites.sol";
import {StoxReceiptVault} from "../../src/concrete/StoxReceiptVault.sol";
import {LibProdDeployCurrent} from "../../src/generated/LibProdDeployCurrent.sol";
import {IStoxAssetIdV1} from "../../src/interface/IStoxAssetIdV1.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibProdTokenConfig, Region, TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {DeployPreDeployCheckHarness} from "../script/DeployPreDeployCheckHarness.sol";

/// @title V6ReleaseBaseFork
/// @notice A Base fork, pinned before any V6 deploy, with the release the V6 path needs. Nothing of the V6 path is live there, so this
/// does what the release does: it binds each registry name the root authority has not bound (the timelock's proposer
/// is the Base Safe, the beacon owner and RBAC owner are the governance timelock, the authorisers are the live ones)
/// and dispatches the timelock, implementation, beacon and token suites, each through the real `Deploy` pre-flight.
/// It never overrides a live binding or redeploys live code.
abstract contract V6ReleaseBaseFork is Test, StoxDeploySuites {
    /// A Base block from before any V6 binding or deploy, so the fixture keeps
    /// working once the release lands and the V6 tokens are named on Base.
    uint256 internal constant BASE_BLOCK = 53585734;

    address internal constant DEPLOYER = address(uint160(uint256(keccak256("st0x.test.v6-tokens-base-fork.deployer"))));

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

    function isBound(bytes32 name) internal view returns (bool) {
        try IConfigRegistryV5(CONFIG_REGISTRY_ADDRESS).getV5(LibStoxConfig.ROOT_AUTHORITY, name) returns (
            bytes memory, uint256, bytes32
        ) {
            return true;
        } catch {
            return false;
        }
    }

    /// Binds `name` as the root authority, only where it is not bound yet, so the test never overrides a live
    /// binding.
    function bindIfUnbound(bytes32 name, string memory valueType, bytes memory value) internal {
        if (isBound(name)) {
            return;
        }
        vm.warp(vm.getBlockTimestamp() + 1);
        vm.prank(LibStoxConfig.ROOT_AUTHORITY);
        IConfigRegistryV5(CONFIG_REGISTRY_ADDRESS).registerV5(LibStoxConfig.ROOT_AUTHORITY, name, valueType, value, "");
    }

    function bindRbacIfUnbound(bytes32 name, address authorizer) internal {
        bindIfUnbound(
            name,
            OFFCHAIN_ASSET_RECEIPT_VAULT_RBAC_V1_VALUE_TYPE,
            abi.encode(
                OffchainAssetReceiptVaultRbacV1({
                    owner: LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK, authorizer: IAuthorizeV1(authorizer)
                })
            )
        );
    }

    /// Runs the real pre-flight, then the suite's deploy step unless its address already holds code.
    function dispatch(DeployDeclaration memory declared, string memory name) internal returns (address) {
        DeploySuite memory suite = suiteByName(declared, name);
        harness.exposedPreDeployCheck(suite, base);
        if (suite.storedDeployedAddress.code.length != 0) {
            assertEq(suite.storedDeployedAddress.codehash, suite.storedBytecodeHash, name);
            return suite.storedDeployedAddress;
        }
        address deployed =
            deployStep(declared, suite)(vm, base.name, DEPLOYER, deployStepData(declared, suite, base.chainId));
        assertEq(deployed, suite.storedDeployedAddress, name);
        assertEq(deployed.codehash, suite.storedBytecodeHash, name);
        return deployed;
    }

    /// The release: the timelock, the implementations and the beacons, with their registry names.
    function deployRelease(DeployDeclaration memory declared) internal {
        bindIfUnbound(
            LibStoxConfig.TIMELOCK_INITIAL_PROPOSER_NAME,
            "address",
            abi.encode(LibSafeInvariants.safeForChainId(block.chainid))
        );
        assertEq(dispatch(declared, GOVERNANCE_TIMELOCK), LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK, "timelock");
        bindIfUnbound(
            LibStoxConfig.BEACON_INITIAL_OWNER_NAME,
            "address",
            abi.encode(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK)
        );
        dispatch(declared, FACET);
        dispatch(declared, RECEIPT);
        dispatch(declared, RECEIPT_VAULT);
        address receiptBeacon = dispatch(declared, RECEIPT_BEACON);
        address vaultBeacon = dispatch(declared, RECEIPT_VAULT_BEACON);
        bindIfUnbound(LibStoxConfig.VAULT_BEACON_NAME, "address", abi.encode(vaultBeacon));
        bindIfUnbound(LibStoxConfig.RECEIPT_BEACON_NAME, "address", abi.encode(receiptBeacon));
        bindRbacIfUnbound(LibStoxConfig.RBAC_US_NAME, LibAuthoriserInvariants.authoriserForChainId(block.chainid));
        bindRbacIfUnbound(LibStoxConfig.RBAC_EU_NAME, LibAuthoriserInvariants.euAuthoriserForChainId(block.chainid));
    }

    /// One row's token suite, through the pre-flight, in its own call frame: the declaration is large and memory is
    /// only freed when a frame returns.
    function deployRow(uint256 index) external returns (address) {
        TokenConfig memory config = LibProdTokenConfig.productionTokenConfigs()[index];
        address token = dispatch(declaration(), string.concat(TOKEN_PREFIX, lowercase(config.symbol)));
        StoxReceiptVault vault = StoxReceiptVault(payable(token));
        assertEq(IStoxAssetIdV1(token).assetId(), config.assetId, config.underlying);
        assertEq(vault.name(), "", config.underlying);
        assertEq(vault.symbol(), "", config.underlying);
        assertEq(vault.owner(), LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK, config.underlying);
        assertEq(
            address(vault.authorizer()),
            config.region == Region.US
                ? LibAuthoriserInvariants.authoriserForChainId(block.chainid)
                : LibAuthoriserInvariants.euAuthoriserForChainId(block.chainid),
            config.underlying
        );
        return token;
    }

    function deployReleaseFrame() external {
        deployRelease(declaration());
    }

    /// Every production row's token, deployed in table order, each in its own call frame.
    function deployAllRows() internal returns (address[] memory tokens) {
        this.deployReleaseFrame();
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        tokens = new address[](configs.length);
        for (uint256 i = 0; i < configs.length; i++) {
            tokens[i] = this.deployRow(i);
        }
    }
}
