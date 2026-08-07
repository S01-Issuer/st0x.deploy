// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {Clones} from "@openzeppelin-contracts-5.6.1/proxy/Clones.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {ICloneableFactoryV3} from "rain-factory-0.1.5/src/interface/ICloneableFactoryV3.sol";
import {LibCloneFactoryDeploy} from "rain-factory-0.1.5/src/lib/LibCloneFactoryDeploy.sol";
import {ERC1167_PREFIX, ERC1167_SUFFIX} from "rain-extrospection-0.1.1/src/lib/LibExtrospectERC1167Proxy.sol";
import {
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.1.7/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";

import {
    DeployDeterministicV4AuthoriserClone,
    DeterministicFactoryNotDeployed,
    DeterministicFactoryCodehashMismatch,
    DeterministicV4ImplCodehashMismatch,
    SafeMissingAdminRole,
    TargetOccupiedByForeignCode
} from "../../script/20260804-deploy-deterministic-v4-authoriser-clone.s.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";

/// @title DeployDeterministicV4AuthoriserCloneTest
/// @notice Offline pin-consistency checks plus Base-fork drives of the
/// 20260804 deterministic clone deploy. The migration target has no live code
/// yet — EXPECTED until the script broadcasts — so live-state tests assert
/// the pinned shape only when code is present.
contract DeployDeterministicV4AuthoriserCloneTest is Test {
    DeployDeterministicV4AuthoriserClone internal script;

    function selectBaseFork() internal {
        vm.createSelectFork(LibRainDeploy.BASE);
        script = new DeployDeterministicV4AuthoriserClone();
    }

    /// @notice The pinned target re-derives offline from (impl, salt,
    /// deployer, factory) with the factory's deployer-namespaced CREATE2
    /// salt. No fork required — pure CREATE2 math.
    function testTargetPinRederivesOffline() external pure {
        bytes32 effSalt = keccak256(
            abi.encode(
                LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC_DEPLOYER,
                LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC_SALT
            )
        );
        address predicted = Clones.predictDeterministicAddress(
            LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1,
            effSalt,
            LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS
        );
        assertEq(
            predicted,
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC,
            "pinned deterministic target does not re-derive from its inputs"
        );
    }

    /// @notice The pinned runtime bytecode re-derives as the EIP-1167 shape
    /// around the pinned V4 impl.
    function testTargetPinCodeRederives() external pure {
        assertEq(
            abi.encodePacked(
                ERC1167_PREFIX, LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1, ERC1167_SUFFIX
            ),
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC_CODE,
            "pinned clone bytecode is not the EIP-1167 shape around the pinned impl"
        );
    }

    /// @notice The pinned deployer is the EOA that created the live Base
    /// clone via the nonce factory (Base tx
    /// `0x26519d1c9090e6236cbd6e9c7f5d6eee7cf633da3a6653742914b3c17fe7d236`)
    /// — the account the CI deploy key resolves to — and NOT the retired
    /// `0x8E4bdeec…` EOA that `BEACON_INITIAL_OWNER` records.
    function testDeployerPinIsTheLiveCloneCreator() external pure {
        assertEq(
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC_DEPLOYER,
            0xE8c6eDE25f0E7fAfE8fBc34770FaBa27d56c0E76,
            "deterministic deployer pin drifted from the live clone's creation-tx sender"
        );
        assertTrue(
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC_DEPLOYER
                != LibProdDeployV4.BEACON_INITIAL_OWNER,
            "deterministic deployer pin must not be the retired beacon-owner EOA"
        );
    }

    /// @notice The pinned codehash is the keccak of the pinned bytecode.
    function testTargetPinCodehashMatchesCode() external pure {
        assertEq(
            keccak256(LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC_CODE),
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC_CODEHASH,
            "pinned codehash is not keccak256 of the pinned bytecode"
        );
    }

    /// @notice On the live Base fork, the factory's own prediction lands on
    /// the pin, and the target either has no code yet (EXPECTED pre-deploy)
    /// or already carries the pinned clone.
    function testBaseLiveFactoryPredictsPin() external {
        selectBaseFork();
        address factory = LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS;
        assertGt(factory.code.length, 0, "deterministic factory missing on Base");
        assertEq(
            factory.codehash, LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_CODEHASH, "factory codehash drift on Base"
        );
        address predicted = ICloneableFactoryV3(factory)
            .predictDeterministicAddress(
                LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1,
                LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC_SALT,
                LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC_DEPLOYER
            );
        assertEq(predicted, LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC, "live prediction != pin");

        address target = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC;
        if (target.code.length != 0) {
            assertEq(
                target.codehash,
                LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC_CODEHASH,
                "target occupied by foreign code"
            );
        }
    }

    /// @notice Against the REAL factory on the Base fork: a deterministic
    /// clone deployed from the pinned deployer/salt lands exactly on the pin
    /// and the script's post-state assertions hold. Once the broadcast has
    /// happened for real, the live clone at the target must satisfy the same
    /// post-state instead — the property is asserted either way.
    function testCloneFromPinnedDeployerLandsOnPin() external {
        selectBaseFork();
        address target = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC;
        address safe = LibSafeInvariants.safeForChainId(block.chainid);

        if (target.code.length == 0) {
            address deployer = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC_DEPLOYER;
            vm.deal(deployer, 1 ether);
            vm.prank(deployer, deployer);
            address clone = ICloneableFactoryV3(LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS)
                .cloneDeterministic(
                    LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1,
                    abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: safe})),
                    LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC_SALT
                );
            assertEq(clone, target, "clone did not land on the pinned target");
            script.assertPostState(clone, safe);
        } else {
            script.assertPostState(target, safe);
        }
    }

    /// @notice `run()` no-ops (no revert, no broadcast) when a properly
    /// initialized pinned clone already occupies the target — a real factory
    /// deploy from the pinned deployer, not an etch, so the idempotent path
    /// sees genuine initialized state.
    function testRunNoOpsWhenTargetAlreadyHydrated() external {
        selectBaseFork();
        address target = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC;
        if (target.code.length == 0) {
            address deployer = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC_DEPLOYER;
            address safe = LibSafeInvariants.safeForChainId(block.chainid);
            vm.deal(deployer, 1 ether);
            vm.prank(deployer, deployer);
            ICloneableFactoryV3(LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS)
                .cloneDeterministic(
                    LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1,
                    abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: safe})),
                    LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC_SALT
                );
        }
        script.run();
    }

    /// @notice `run()` rejects a shape-matching clone at the target whose
    /// initialized state is missing the Safe's admin grants — the codehash
    /// alone is not proof of correct initialization.
    ///
    /// Only testable while the target is empty: `vm.etch` replaces code but
    /// keeps storage, so once the broadcast has hydrated the target for real
    /// the etched clone inherits the live grants and `run()` correctly
    /// no-ops — the uninitialized shape this test fabricates no longer
    /// exists at this address. The hydrated target's post-state is asserted
    /// by `testRunNoOpsWhenTargetAlreadyHydrated` and
    /// `testCloneFromPinnedDeployerLandsOnPin` instead.
    function testRunRejectsUninitializedCloneAtTarget() external {
        selectBaseFork();
        address target = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC;
        if (target.code.length != 0) {
            return;
        }
        vm.etch(target, LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC_CODE);
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeMissingAdminRole.selector,
                script.autoGrantedAdminRoles()[0],
                LibSafeInvariants.safeForChainId(LibSafeInvariants.BASE_CHAIN_ID)
            )
        );
        script.run();
    }

    /// @notice `run()` rejects a target occupied by anything other than the
    /// pinned clone shape.
    function testRunRejectsForeignCodeAtTarget() external {
        selectBaseFork();
        address target = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC;
        vm.etch(target, hex"fe");
        vm.expectRevert(
            abi.encodeWithSelector(
                TargetOccupiedByForeignCode.selector,
                target,
                LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC_CODEHASH,
                target.codehash
            )
        );
        script.run();
    }

    /// @notice `run()` rejects a missing deterministic factory.
    function testRunRejectsMissingFactory() external {
        selectBaseFork();
        address factory = LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS;
        vm.etch(factory, "");
        vm.expectRevert(abi.encodeWithSelector(DeterministicFactoryNotDeployed.selector, factory));
        script.run();
    }

    /// @notice `run()` rejects a factory whose codehash drifts from the
    /// rain-factory 0.1.5 pin.
    function testRunRejectsFactoryCodehashDrift() external {
        selectBaseFork();
        address factory = LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS;
        vm.etch(factory, hex"fe");
        vm.expectRevert(
            abi.encodeWithSelector(
                DeterministicFactoryCodehashMismatch.selector,
                factory,
                LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_CODEHASH,
                factory.codehash
            )
        );
        script.run();
    }

    /// @notice `run()` rejects a V4 impl whose codehash drifts from the pin.
    function testRunRejectsImplCodehashDrift() external {
        selectBaseFork();
        address impl = LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1;
        vm.etch(impl, hex"fe");
        vm.expectRevert(
            abi.encodeWithSelector(
                DeterministicV4ImplCodehashMismatch.selector,
                impl,
                LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CODEHASH_0_1_1,
                impl.codehash
            )
        );
        script.run();
    }

    /// @notice On the Ethereum fork the same pin holds: prediction matches
    /// when the factory is present; while it is not yet Zoltu-deployed there,
    /// `run()` fail-safes with the typed factory-missing error.
    function testEthereumFactoryGate() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        script = new DeployDeterministicV4AuthoriserClone();
        address factory = LibCloneFactoryDeploy.CLONE_FACTORY_DEPLOYED_ADDRESS;
        if (factory.code.length == 0) {
            vm.expectRevert(abi.encodeWithSelector(DeterministicFactoryNotDeployed.selector, factory));
            script.run();
        } else {
            address predicted = ICloneableFactoryV3(factory)
                .predictDeterministicAddress(
                    LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1,
                    LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC_SALT,
                    LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC_DEPLOYER
                );
            assertEq(
                predicted, LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_DETERMINISTIC, "Ethereum prediction != pin"
            );
        }
    }
}
