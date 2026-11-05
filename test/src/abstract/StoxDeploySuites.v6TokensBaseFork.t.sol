// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";

import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {LibProdDeployCurrent} from "../../../src/generated/LibProdDeployCurrent.sol";
import {IStoxAssetIdV1} from "../../../src/interface/IStoxAssetIdV1.sol";
import {IStoxUnderlyingV1} from "../../../src/interface/IStoxUnderlyingV1.sol";
import {LibProdTokenConfig, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../../../src/lib/LibTimelockInvariants.sol";
import {ST0X_NAME_SUFFIX} from "../../../src/lib/LibUnderlying.sol";
import {V6ReleaseBaseFork} from "../../abstract/V6ReleaseBaseFork.sol";

/// @title StoxDeploySuitesV6TokensBaseForkTest
/// @notice On a Base fork, every production row deploys through its V6 token suite nameless and with its asset id, and
/// the real governance timelock names it with `setUnderlying` after the 48h delay.
contract StoxDeploySuitesV6TokensBaseForkTest is V6ReleaseBaseFork {
    bytes32 internal constant SALT = keccak256("st0x.test.v6-tokens-base-fork.first-set-underlying");

    function setUp() external {
        forkBase();
    }

    function testEveryRowDeploysNamelessAndIsNamedThroughTheTimelock() external {
        this.deployReleaseFrame();

        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        address[] memory targets = new address[](configs.length);
        uint256[] memory values = new uint256[](configs.length);
        bytes[] memory payloads = new bytes[](configs.length);
        for (uint256 i = 0; i < configs.length; i++) {
            targets[i] = this.deployRow(i);
            payloads[i] =
                abi.encodeCall(IStoxUnderlyingV1.setUnderlying, (configs[i].underlying, configs[i].underlyingName));
        }

        TimelockController timelock = TimelockController(payable(LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK));
        bytes32 id = timelock.hashOperationBatch(targets, values, payloads, bytes32(0), SALT);
        vm.prank(LibSafeInvariants.safeForChainId(block.chainid));
        timelock.scheduleBatch(targets, values, payloads, bytes32(0), SALT, LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        vm.warp(vm.getBlockTimestamp() + LibTimelockInvariants.TIMELOCK_MIN_DELAY - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector,
                id,
                bytes32(uint256(2) ** uint8(TimelockController.OperationState.Ready))
            )
        );
        timelock.executeBatch(targets, values, payloads, bytes32(0), SALT);
        vm.warp(vm.getBlockTimestamp() + 1);
        vm.prank(DEPLOYER);
        timelock.executeBatch(targets, values, payloads, bytes32(0), SALT);
        assertTrue(timelock.isOperationDone(id), "done");

        for (uint256 i = 0; i < configs.length; i++) {
            StoxReceiptVault vault = StoxReceiptVault(payable(targets[i]));
            assertEq(vault.symbol(), configs[i].symbol, configs[i].underlying);
            assertEq(vault.name(), string.concat(configs[i].underlyingName, ST0X_NAME_SUFFIX), configs[i].underlying);
            assertEq(IStoxAssetIdV1(targets[i]).assetId(), configs[i].assetId, configs[i].underlying);
        }
    }
}
