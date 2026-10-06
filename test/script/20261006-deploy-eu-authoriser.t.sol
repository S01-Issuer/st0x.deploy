// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {DEPLOYED_ADDRESS as CLONE_FACTORY_V4} from "rain-factory-deploy-0.1.10/src/generated/0_1_10/CloneFactory.sol";
import {
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.1.6/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {LibRainDeploy} from "rain-deploy-0.1.12/src/lib/LibRainDeploy.sol";

import {
    DeployEuAuthoriser,
    EU_AUTHORISER_SALT,
    EuAuthoriserPinAlreadyHydrated,
    EuImplNotReady,
    EuCloneFactoryNotReady,
    EuSafeNotInitialAdmin
} from "../../script/20261006-deploy-eu-authoriser.s.sol";
import {PinnedDeployEuAuthoriserHarness} from "./PinnedDeployEuAuthoriserHarness.sol";
import {UnpinnedDeployEuAuthoriserHarness} from "./UnpinnedDeployEuAuthoriserHarness.sol";
import {ICloneableFactoryV4} from "../../src/interface/ICloneableFactoryV4.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {
    LibEuAuthoriserInvariants,
    EuForbiddenGrant,
    UnsupportedChainForEuAuthoriser
} from "../../src/lib/LibEuAuthoriserInvariants.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {SafeTx} from "../../src/lib/LibSafeOps.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";

contract DeployEuAuthoriserTest is Test {
    function _predicted(DeployEuAuthoriser script) internal view returns (address) {
        (address safe,, address impl, address factory) = script.preflight();
        return script.predictedClone(factory, impl, safe);
    }

    function _runOnFork(string memory network, uint256 chainId) internal returns (address clone) {
        vm.createSelectFork(network);
        assertEq(block.chainid, chainId, "RPC is not the expected chain");
        DeployEuAuthoriser script = new UnpinnedDeployEuAuthoriserHarness();
        clone = _predicted(script);
        assertEq(clone.code.length, 0, "predicted address already has code");

        script.run();

        assertEq(clone.codehash, LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH, "not the audited clone");
        _assertRoleMap(clone, chainId);
    }

    function _assertRoleMap(address clone, uint256 chainId) internal view {
        IAccessControl acl = IAccessControl(clone);
        address safe = LibSafeInvariants.safeForChainId(chainId);
        address timelock = LibTimelockInvariants.timelockForChainId(chainId);
        address minter = LibEuAuthoriserInvariants.GRANTEE_EU_MINTER;
        address service = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;
        address orchestrator = LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR;

        bytes32[7] memory admins = LibEuAuthoriserInvariants.adminRoles();
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
        assertFalse(acl.hasRole(keccak256("DEPOSIT"), service), "3d0c must not DEPOSIT tMC");
        assertFalse(acl.hasRole(keccak256("WITHDRAW"), service), "3d0c must not WITHDRAW tMC");

        assertFalse(acl.hasRole(keccak256("DEPOSIT"), orchestrator), "orchestrator must not DEPOSIT tMC");
        assertFalse(acl.hasRole(keccak256("WITHDRAW"), orchestrator), "orchestrator must not WITHDRAW tMC");

        address[5] memory named = [timelock, safe, minter, service, orchestrator];
        for (uint256 i = 0; i < named.length; i++) {
            assertFalse(acl.hasRole(bytes32(0), named[i]), "DEFAULT_ADMIN_ROLE held");
        }

        LibEuAuthoriserInvariants.assertExpectedGrants(clone, safe, timelock);
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

    function testFrontRunDeploysTheSameClone() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        DeployEuAuthoriser script = new UnpinnedDeployEuAuthoriserHarness();
        (address safe,, address impl, address factory) = script.preflight();
        address clone = _predicted(script);

        vm.prank(address(0xBAD));
        address frontRun =
            ICloneableFactoryV4(factory).cloneDeterministicOpenSalt(impl, script.cloneData(safe), EU_AUTHORISER_SALT);
        assertEq(frontRun, clone);

        script.run();
        _assertRoleMap(clone, LibSafeInvariants.BASE_CHAIN_ID);
    }

    function testOtherInitialAdminLandsElsewhere() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        DeployEuAuthoriser script = new UnpinnedDeployEuAuthoriserHarness();
        (,, address impl, address factory) = script.preflight();
        address clone = _predicted(script);

        bytes memory squat = abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: address(0xBAD)}));
        vm.prank(address(0xBAD));
        address squatted = ICloneableFactoryV4(factory).cloneDeterministicOpenSalt(impl, squat, EU_AUTHORISER_SALT);
        assertTrue(squatted != clone);
        assertEq(clone.code.length, 0);
    }

    function testInitialStateRefusesASafeMissingAnAdmin() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        DeployEuAuthoriser script = new UnpinnedDeployEuAuthoriserHarness();
        (address safe,, address impl, address factory) = script.preflight();
        address clone =
            ICloneableFactoryV4(factory).cloneDeterministicOpenSalt(impl, script.cloneData(safe), EU_AUTHORISER_SALT);
        script.assertInitialState(clone, safe);

        vm.prank(safe);
        IAccessControl(clone).renounceRole(keccak256("DEPOSIT_ADMIN"), safe);
        vm.expectRevert(abi.encodeWithSelector(EuSafeNotInitialAdmin.selector, clone, keccak256("DEPOSIT_ADMIN")));
        script.assertInitialState(clone, safe);
    }

    function testBundleRenouncesEveryAdminLast() external {
        DeployEuAuthoriser script = new DeployEuAuthoriser();
        address clone = address(0xC10E);
        address safe = address(0x5AFE);
        address timelock = address(0x71CE);
        SafeTx[] memory txs = script.handoverBundle(clone, safe, timelock);
        assertEq(txs.length, LibEuAuthoriserInvariants.EXPECTED_GRANT_COUNT + 7);

        bytes32[7] memory admins = LibEuAuthoriserInvariants.adminRoles();
        for (uint256 i = 0; i < admins.length; i++) {
            SafeTx memory renounce = txs[LibEuAuthoriserInvariants.EXPECTED_GRANT_COUNT + i];
            assertEq(renounce.to, clone);
            assertEq(renounce.data, abi.encodeCall(IAccessControl.renounceRole, (admins[i], safe)));
        }
        for (uint256 i = 0; i < txs.length; i++) {
            assertEq(txs[i].operation, 0);
            assertEq(txs[i].value, 0);
        }
    }

    function testInvariantCatchesServiceSignerDepositOnFork() external {
        address clone = _runOnFork(LibRainDeploy.BASE, LibSafeInvariants.BASE_CHAIN_ID);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        vm.prank(timelock);
        IAccessControl(clone).grantRole(keccak256("DEPOSIT"), LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C);
        vm.expectRevert(
            abi.encodeWithSelector(
                EuForbiddenGrant.selector, clone, keccak256("DEPOSIT"), LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C
            )
        );
        this.externalAssertExpectedGrants(clone, safe, timelock);
    }

    function testPreflightRefusesAPinnedChain() external {
        vm.chainId(LibSafeInvariants.BASE_CHAIN_ID);
        DeployEuAuthoriser script = new PinnedDeployEuAuthoriserHarness();
        vm.expectRevert(abi.encodeWithSelector(EuAuthoriserPinAlreadyHydrated.selector, address(0xE0A0)));
        script.preflight();
    }

    function testPreflightRejectsUnknownChain() external {
        vm.chainId(123456);
        DeployEuAuthoriser script = new DeployEuAuthoriser();
        vm.expectRevert(abi.encodeWithSelector(UnsupportedChainForEuAuthoriser.selector, 123456));
        script.preflight();
    }

    function testPreflightRejectsMissingImpl() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        vm.etch(LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1, hex"00");
        DeployEuAuthoriser script = new UnpinnedDeployEuAuthoriserHarness();
        vm.expectRevert(
            abi.encodeWithSelector(
                EuImplNotReady.selector, LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1
            )
        );
        script.preflight();
    }

    function testPreflightRejectsReplacedFactory() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        vm.etch(CLONE_FACTORY_V4, hex"00");
        DeployEuAuthoriser script = new UnpinnedDeployEuAuthoriserHarness();
        vm.expectRevert(abi.encodeWithSelector(EuCloneFactoryNotReady.selector, CLONE_FACTORY_V4));
        script.preflight();
    }

    function externalAssertExpectedGrants(address clone, address safe, address timelock) external view {
        LibEuAuthoriserInvariants.assertExpectedGrants(clone, safe, timelock);
    }
}
