// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibCloneFactoryDeploy} from "rain-factory-0.1.1/src/lib/LibCloneFactoryDeploy.sol";
import {LibRainDeploy} from "rain-deploy-0.1.10/src/lib/LibRainDeploy.sol";

import {
    DeployLvmhAuthoriser,
    LvmhImplNotReady,
    LvmhCloneFactoryNotReady,
    LvmhDeployerStillHoldsRole
} from "../../script/20261006-deploy-lvmh-authoriser.s.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {
    LibLvmhAuthoriserInvariants,
    LvmhForbiddenGrant,
    UnsupportedChainForLvmhAuthoriser
} from "../../src/lib/LibLvmhAuthoriserInvariants.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";

/// @title DeployLvmhAuthoriserTest
/// @notice Runs `20261006-deploy-lvmh-authoriser` end to end against an
/// unpinned head fork of every target chain, then re-asserts the resulting
/// role map from the test side — including the ABSENCE of DEPOSIT/WITHDRAW on
/// the shared service signer and the orchestrator.
contract DeployLvmhAuthoriserTest is Test {
    address constant DEPLOY_KEY = address(0xDEB01);

    /// @notice Run the script on the active fork and return the new clone,
    /// read off the factory's CREATE address at the pre-run nonce.
    function _runOnFork(string memory network, uint256 chainId) internal returns (address clone) {
        vm.createSelectFork(network);
        assertEq(block.chainid, chainId, "RPC is not the expected chain");
        address factory = LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS;
        address predicted = vm.computeCreateAddress(factory, vm.getNonce(factory));
        assertEq(predicted.code.length, 0, "predicted address already has code");

        DeployLvmhAuthoriser script = new DeployLvmhAuthoriser();
        script.run();

        clone = predicted;
        assertEq(clone.codehash, LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH, "not the audited clone");
        _assertRoleMap(clone, chainId);
    }

    /// @notice The role map, asserted independently of the lib's own loops.
    function _assertRoleMap(address clone, uint256 chainId) internal view {
        IAccessControl acl = IAccessControl(clone);
        address safe = LibSafeInvariants.safeForChainId(chainId);
        address timelock = LibTimelockInvariants.timelockForChainId(chainId);
        address minter = LibLvmhAuthoriserInvariants.GRANTEE_LVMH_MINTER;
        address service = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;
        address orchestrator = LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR;

        bytes32[7] memory admins = LibLvmhAuthoriserInvariants.adminRoles();
        for (uint256 i = 0; i < admins.length; i++) {
            assertTrue(acl.hasRole(admins[i], timelock), "timelock missing an _ADMIN");
            assertFalse(acl.hasRole(admins[i], safe), "Safe holds an _ADMIN");
            assertFalse(acl.hasRole(admins[i], minter), "minter holds an _ADMIN");
            assertFalse(acl.hasRole(admins[i], service), "3d0c holds an _ADMIN");
            assertFalse(acl.hasRole(admins[i], orchestrator), "orchestrator holds an _ADMIN");
        }

        assertTrue(acl.hasRole(keccak256("DEPOSIT"), safe), "Safe DEPOSIT");
        assertTrue(acl.hasRole(keccak256("WITHDRAW"), safe), "Safe WITHDRAW");
        assertTrue(acl.hasRole(keccak256("CERTIFY"), safe), "Safe CERTIFY");

        assertTrue(acl.hasRole(keccak256("DEPOSIT"), minter), "minter DEPOSIT");
        assertTrue(acl.hasRole(keccak256("WITHDRAW"), minter), "minter WITHDRAW");
        assertFalse(acl.hasRole(keccak256("CERTIFY"), minter), "minter CERTIFY");

        assertTrue(acl.hasRole(keccak256("CERTIFY"), service), "3d0c CERTIFY");
        assertFalse(acl.hasRole(keccak256("DEPOSIT"), service), "3d0c must not DEPOSIT tLVMH");
        assertFalse(acl.hasRole(keccak256("WITHDRAW"), service), "3d0c must not WITHDRAW tLVMH");

        assertFalse(acl.hasRole(keccak256("DEPOSIT"), orchestrator), "orchestrator must not DEPOSIT tLVMH");
        assertFalse(acl.hasRole(keccak256("WITHDRAW"), orchestrator), "orchestrator must not WITHDRAW tLVMH");

        address[5] memory named = [timelock, safe, minter, service, orchestrator];
        for (uint256 i = 0; i < named.length; i++) {
            assertFalse(acl.hasRole(bytes32(0), named[i]), "DEFAULT_ADMIN_ROLE held");
        }

        LibLvmhAuthoriserInvariants.assertExpectedGrants(clone, safe, timelock);
    }

    function testRunOnBaseFork() external {
        _runOnFork(LibRainDeploy.BASE, LibSafeInvariants.BASE_CHAIN_ID);
    }

    function testRunOnEthereumFork() external {
        _runOnFork(LibStoxDeployNetworks.ETHEREUM, LibSafeInvariants.ETHEREUM_CHAIN_ID);
    }

    function testRunOnHyperEvmFork() external {
        _runOnFork(LibStoxDeployNetworks.HYPEREVM, LibSafeInvariants.HYPEREVM_CHAIN_ID);
    }

    function testRunOnRobinhoodFork() external {
        _runOnFork(LibStoxDeployNetworks.ROBINHOOD, LibSafeInvariants.ROBINHOOD_CHAIN_ID);
    }

    function testRunOnBscFork() external {
        _runOnFork(LibStoxDeployNetworks.BSC, LibSafeInvariants.BSC_CHAIN_ID);
    }

    /// @notice A role-map drift after deploy — someone granting the shared
    /// service signer DEPOSIT on the tLVMH authoriser via the timelock — is
    /// caught by the invariant.
    function testInvariantCatchesServiceSignerDepositOnFork() external {
        address clone = _runOnFork(LibRainDeploy.BASE, LibSafeInvariants.BASE_CHAIN_ID);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        vm.prank(timelock);
        IAccessControl(clone).grantRole(keccak256("DEPOSIT"), LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C);
        vm.expectRevert(
            abi.encodeWithSelector(
                LvmhForbiddenGrant.selector, clone, keccak256("DEPOSIT"), LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C
            )
        );
        this.externalAssertExpectedGrants(clone, safe, timelock);
    }

    /// @notice A deploy key that kept a role is caught by the post-state.
    function testPostStateCatchesDeployerResidue() external {
        address clone = _runOnFork(LibRainDeploy.BASE, LibSafeInvariants.BASE_CHAIN_ID);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address deployer = DEPLOY_KEY;
        vm.prank(timelock);
        IAccessControl(clone).grantRole(keccak256("WITHDRAW"), deployer);
        DeployLvmhAuthoriser script = new DeployLvmhAuthoriser();
        vm.expectRevert(abi.encodeWithSelector(LvmhDeployerStillHoldsRole.selector, keccak256("WITHDRAW"), deployer));
        script.assertPostState(clone, deployer, safe, timelock);
    }

    /// @notice A chain with no slot is a dispatch error.
    function testPreflightRejectsUnknownChain() external {
        vm.chainId(123456);
        DeployLvmhAuthoriser script = new DeployLvmhAuthoriser();
        vm.expectRevert(abi.encodeWithSelector(UnsupportedChainForLvmhAuthoriser.selector, 123456));
        script.preflight();
    }

    /// @notice With the audited implementation missing at its pin, the run
    /// refuses before broadcasting.
    function testPreflightRejectsMissingImpl() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        vm.etch(LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1, hex"00");
        DeployLvmhAuthoriser script = new DeployLvmhAuthoriser();
        vm.expectRevert(
            abi.encodeWithSelector(
                LvmhImplNotReady.selector, LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1
            )
        );
        script.preflight();
    }

    /// @notice A replaced CloneFactory is refused.
    function testPreflightRejectsReplacedFactory() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        vm.etch(LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS, hex"00");
        DeployLvmhAuthoriser script = new DeployLvmhAuthoriser();
        vm.expectRevert(
            abi.encodeWithSelector(
                LvmhCloneFactoryNotReady.selector, LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS
            )
        );
        script.preflight();
    }

    /// @dev External hop so `expectRevert` sees the library revert.
    function externalAssertExpectedGrants(address clone, address safe, address timelock) external view {
        LibLvmhAuthoriserInvariants.assertExpectedGrants(clone, safe, timelock);
    }
}
