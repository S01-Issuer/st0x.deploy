// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibConfigRegistry} from "rain-deploy-0.1.30/src/lib/LibConfigRegistry.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.30/src/lib/LibConfigRegistryDeploy.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";

import {LibStoxConfig, ZeroOrchestratorInitialAdmin} from "../../../src/lib/LibStoxConfig.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";

/// @title OrchestratorInitialAdminSeatTest
/// @notice Whatever seats the orchestrator initial admin seats the one the root
/// authority binds in the ConfigRegistry, on any chain, and refuses every
/// registry state that does not bind one.
abstract contract OrchestratorInitialAdminSeatTest is Test {
    /// Builds what seats the admin, in a single call or creation.
    function seat() internal virtual returns (address);

    /// Asserts `seated`, as `seat` returned it, gives governance to
    /// `admin` alone.
    function assertSeated(address seated, address admin) internal view virtual;

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
        // Deployed code never starts 0xef (EIP-3541); vm.etch reads 0xef01 as an EIP-7702 designator.
        vm.assume(code.length > 0 && code[0] != 0xef);
        vm.assume(keccak256(code) != LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH);
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
        LibTestDeploy.bindBeacons(vm, LibRegistryAuthority.ROOT_AUTHORITY);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV5.NameNotRegistered.selector,
                LibRegistryAuthority.ROOT_AUTHORITY,
                LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME
            )
        );
        seat();
    }

    function testFuzzSeatRefusesTheNameBoundUnderAnotherAuthority(address authority, address admin) external {
        vm.assume(authority != LibRegistryAuthority.ROOT_AUTHORITY && authority != address(0));
        assumeNotForgeAddress(authority);
        vm.assume(admin != address(0));
        LibTestDeploy.etchConfigRegistry(vm);
        LibTestDeploy.bind(vm, authority, LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME, "address", abi.encode(admin));
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfigRegistryV5.NameNotRegistered.selector,
                LibRegistryAuthority.ROOT_AUTHORITY,
                LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME
            )
        );
        seat();
    }

    function testFuzzSeatRefusesAValueTypeOtherThanAddress(string memory valueType, address admin) external {
        vm.assume(bytes(valueType).length > 0 && keccak256(bytes(valueType)) != keccak256("address"));
        vm.assume(admin != address(0));
        LibTestDeploy.etchConfigRegistry(vm);
        LibTestDeploy.bind(
            vm,
            LibRegistryAuthority.ROOT_AUTHORITY,
            LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME,
            valueType,
            abi.encode(admin)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.ValueTypeMismatch.selector,
                LibRegistryAuthority.ROOT_AUTHORITY,
                LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME,
                keccak256("address"),
                keccak256(bytes(valueType))
            )
        );
        seat();
    }

    function testSeatRefusesAZeroAdmin() external {
        LibTestDeploy.bindOrchestratorInitialAdmin(vm, address(0));
        vm.expectRevert(abi.encodeWithSelector(ZeroOrchestratorInitialAdmin.selector));
        seat();
    }

    function testFuzzSeatSeatsTheBoundAdminOnAnyChain(uint256 chainId, address admin) external {
        chainId = bound(chainId, 1, type(uint64).max - 1);
        vm.assume(admin != address(0) && admin != address(this));
        vm.chainId(chainId);
        LibTestDeploy.bindOrchestratorInitialAdmin(vm, admin);
        assertSeated(seat(), admin);
    }
}
