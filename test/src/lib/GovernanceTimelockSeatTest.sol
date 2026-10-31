// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibConfigRegistry} from "rain-deploy-0.1.29/src/lib/LibConfigRegistry.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.29/src/lib/LibConfigRegistryDeploy.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.29/src/interface/IConfigRegistryV5.sol";

import {LibStoxConfig, ZeroGovernanceTimelock} from "../../../src/lib/LibStoxConfig.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";

/// @title GovernanceTimelockSeatTest
/// @notice Whatever seats the governance timelock seats the one the root
/// authority binds in the ConfigRegistry, on any chain, and refuses every
/// registry state that does not bind one.
abstract contract GovernanceTimelockSeatTest is Test {
    /// Builds what seats the timelock, in a single call or creation.
    function seat() internal virtual returns (address);

    /// Asserts `seated`, as `seat` returned it, gives governance to
    /// `timelock` alone.
    function assertSeated(address seated, address timelock) internal view virtual;

    function testSeatRefusesAnAbsentRegistry() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.UnexpectedConfigRegistryCodeHash.selector,
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        seat();
    }

    function testSeatRefusesAFundedCodelessRegistryAddress() external {
        vm.deal(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS, 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.UnexpectedConfigRegistryCodeHash.selector,
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH,
                keccak256("")
            )
        );
        seat();
    }

    function testFuzzSeatRefusesOtherCodeAtTheRegistry(bytes memory code) external {
        vm.assume(code.length > 0 && keccak256(code) != LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH);
        vm.etch(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS, code);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.UnexpectedConfigRegistryCodeHash.selector,
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH,
                keccak256(code)
            )
        );
        seat();
    }

    /// The root authority's other st0x bindings do not stand in for it.
    function testSeatRefusesAnUnboundName() external {
        LibTestDeploy.etchConfigRegistry(vm);
        LibTestDeploy.bindBeacons(vm, LibStoxConfig.ROOT_AUTHORITY);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV5.NameNotRegistered.selector,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.GOVERNANCE_TIMELOCK_NAME
            )
        );
        seat();
    }

    function testFuzzSeatRefusesTheNameBoundUnderAnotherAuthority(address authority, address timelock) external {
        vm.assume(authority != LibStoxConfig.ROOT_AUTHORITY && authority != address(0));
        assumeNotForgeAddress(authority);
        vm.assume(timelock != address(0));
        LibTestDeploy.etchConfigRegistry(vm);
        LibTestDeploy.bind(vm, authority, LibStoxConfig.GOVERNANCE_TIMELOCK_NAME, "address", abi.encode(timelock));
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV5.NameNotRegistered.selector,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.GOVERNANCE_TIMELOCK_NAME
            )
        );
        seat();
    }

    function testFuzzSeatRefusesAValueTypeOtherThanAddress(string memory valueType, address timelock) external {
        vm.assume(bytes(valueType).length > 0 && keccak256(bytes(valueType)) != keccak256("address"));
        vm.assume(timelock != address(0));
        LibTestDeploy.etchConfigRegistry(vm);
        LibTestDeploy.bind(
            vm, LibStoxConfig.ROOT_AUTHORITY, LibStoxConfig.GOVERNANCE_TIMELOCK_NAME, valueType, abi.encode(timelock)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.ValueTypeMismatch.selector,
                LibStoxConfig.ROOT_AUTHORITY,
                LibStoxConfig.GOVERNANCE_TIMELOCK_NAME,
                keccak256("address"),
                keccak256(bytes(valueType))
            )
        );
        seat();
    }

    function testSeatRefusesAZeroTimelock() external {
        LibTestDeploy.bindGovernanceTimelock(vm, address(0));
        vm.expectRevert(abi.encodeWithSelector(ZeroGovernanceTimelock.selector));
        seat();
    }

    function testFuzzSeatSeatsTheBoundTimelockOnAnyChain(uint256 chainId, address timelock) external {
        chainId = bound(chainId, 1, type(uint64).max - 1);
        vm.assume(timelock != address(0) && timelock != address(this));
        vm.chainId(chainId);
        LibTestDeploy.bindGovernanceTimelock(vm, timelock);
        assertSeated(seat(), timelock);
    }
}
