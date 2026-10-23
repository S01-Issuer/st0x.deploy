// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {IConfigRegistryV3} from "rain-deploy-0.1.21/src/interface/IConfigRegistryV3.sol";
import {LibRainDeploy} from "rain-deploy-0.1.21/src/lib/LibRainDeploy.sol";
import {ICloneableFactoryV5} from "rain-factory-0.2.4/src/interface/ICloneableFactoryV5.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY,
    RUNTIME_CODE as CLONE_FACTORY_RUNTIME_CODE
} from "rain-factory-deploy-0.2.1/src/generated/0_2_1/CloneFactory.sol";

import {AuthoriserAdminNotTimelock} from "../../script/20261022-deploy-authoriser-clone.s.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    DEPLOYED_ADDRESS as AUTHORISER
} from "../../src/generated/candidate/StoxOffchainAssetReceiptVaultAuthorizerV1.pointers.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {ScriptDeclaration} from "../../src/interface/IStoxScript.sol";
import {AUTHORISER_CLONE_SALT, LibAuthoriserClone} from "../../src/lib/LibAuthoriserClone.sol";
import {
    DeployKeyHoldsRole,
    ExpectedGrantMissing,
    LibAuthoriserInvariants
} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibStoxConfig} from "../../src/lib/LibStoxConfig.sol";
import {LibStoxConfigFork} from "../../src/lib/LibStoxConfigFork.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {DeployAuthoriserCloneHarness} from "./DeployAuthoriserCloneHarness.sol";

contract DeployAuthoriserCloneTest is Test {
    DeployAuthoriserCloneHarness internal script;
    address internal timelock;

    function setUp() external {
        vm.chainId(8453);
        timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        script = new DeployAuthoriserCloneHarness();
        LibRainDeploy.etchZoltuFactory(vm);
        vm.etch(CLONE_FACTORY, CLONE_FACTORY_RUNTIME_CODE);
        LibStoxConfigFork.etchConfigRegistry(vm);
    }

    function deployImplementation() internal returns (address) {
        return script.callBoundZoltuDeployStep(
            "base", address(this), type(StoxOffchainAssetReceiptVaultAuthorizerV1).creationCode
        );
    }

    function testDeclarationIsNotAMigration() external view {
        ScriptDeclaration memory declared = script.declaration();
        assertFalse(declared.migration);
        assertEq(declared.prerequisites.length, 0);
        assertEq(declared.id, bytes32(0));
    }

    function testStepsRefuseAnUnboundChain() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV3.NameNotRegistered.selector,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.AUTHORISER_ADMIN
            )
        );
        deployImplementation();
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV3.NameNotRegistered.selector,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.AUTHORISER_ADMIN
            )
        );
        script.callBoundCloneStep("base", address(this), LibAuthoriserClone.cloneData());
    }

    function testFuzzStepsRefuseAnAdminOtherThanTheTimelock(address admin) external {
        vm.assume(admin != timelock);
        LibStoxConfigFork.bindAuthoriserAdmin(vm, admin);
        vm.expectRevert(abi.encodeWithSelector(AuthoriserAdminNotTimelock.selector, "base", admin));
        deployImplementation();
        vm.expectRevert(abi.encodeWithSelector(AuthoriserAdminNotTimelock.selector, "base", admin));
        script.callBoundCloneStep("base", address(this), LibAuthoriserClone.cloneData());
    }

    function testStepsDeployThePinnedCloneOnABoundChain() external {
        LibStoxConfigFork.bindAuthoriserAdmin(vm, timelock);
        assertEq(deployImplementation(), AUTHORISER);
        address clone = script.callBoundCloneStep("base", address(this), LibAuthoriserClone.cloneData());
        assertEq(clone, LibProdDeployV4.STOX_AUTHORISER_V4_REGISTRY_CLONE);
        assertEq(clone.codehash, LibProdDeployV4.STOX_AUTHORISER_V4_REGISTRY_CLONE_CODEHASH);
        assertEq(clone.code, LibProdDeployV4.STOX_AUTHORISER_V4_REGISTRY_CLONE_CODE);
        script.callAssertCloneState(clone);
    }

    function testCloneStateRefusesAnotherAdmin() external {
        address other = address(0xBEEF);
        LibStoxConfigFork.bindAuthoriserAdmin(vm, timelock);
        deployImplementation();
        LibStoxConfigFork.bindAuthoriserAdmin(vm, other);
        address clone = ICloneableFactoryV5(CLONE_FACTORY)
            .cloneDeterministicOpenSalt(AUTHORISER, LibAuthoriserClone.cloneData(), AUTHORISER_CLONE_SALT);
        vm.expectRevert(
            abi.encodeWithSelector(ExpectedGrantMissing.selector, clone, keccak256("DEPOSIT_ADMIN"), timelock)
        );
        script.callAssertCloneState(clone);
    }

    function testCloneStateRefusesADeployKeyRole() external {
        LibStoxConfigFork.bindAuthoriserAdmin(vm, timelock);
        deployImplementation();
        address clone = script.callBoundCloneStep("base", address(this), LibAuthoriserClone.cloneData());
        vm.prank(timelock);
        IAccessControl(clone).grantRole(keccak256("CERTIFY"), LibAuthoriserInvariants.DEPLOY_HOT_KEY);
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployKeyHoldsRole.selector, clone, keccak256("CERTIFY"), LibAuthoriserInvariants.DEPLOY_HOT_KEY
            )
        );
        script.callAssertCloneState(clone);
    }
}
