// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeployCandidate} from "rain-deploy-0.1.30/src/abstract/RainDeploySuitesBase.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";

import {StoxDeploySuites} from "../../../src/abstract/StoxDeploySuites.sol";
import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";

/// @title StoxDeploySuitesBeaconOwnerSuitesTest
/// @notice `beaconOwnerSuites()` is exactly the candidates whose constructors read the beacon initial owner binding.
contract StoxDeploySuitesBeaconOwnerSuitesTest is Test, StoxDeploySuites {
    /// With every other address name bound and each candidate's dependencies in place, a candidate is in the list
    /// exactly when its creation code reverts on the unbound beacon initial owner, and no candidate reverts on another
    /// unbound name.
    function testBeaconOwnerSuitesAreTheCandidatesThatReadTheBinding() external {
        LibTestDeploy.etchConfigRegistry(vm);
        bytes32[6] memory others = [
            LibStoxConfig.VAULT_BEACON_NAME,
            LibStoxConfig.RECEIPT_BEACON_NAME,
            LibStoxConfig.WRAPPER_BEACON_NAME,
            LibStoxConfig.ORCHESTRATOR_BEACON_NAME,
            LibStoxConfig.TIMELOCK_INITIAL_PROPOSER_NAME,
            LibStoxConfig.ORCHESTRATOR_INITIAL_ADMIN_NAME
        ];
        for (uint256 i = 0; i < others.length; i++) {
            LibTestDeploy.bind(vm, LibRegistryAuthority.ROOT_AUTHORITY, others[i], "address", abi.encode(address(1)));
        }
        bytes memory unbound = abi.encodeWithSelector(
            IConfigRegistryV5.NameNotRegistered.selector,
            LibRegistryAuthority.ROOT_AUTHORITY,
            LibStoxConfig.BEACON_INITIAL_OWNER_NAME
        );
        DeployCandidate[] memory candidates = candidateSuites();
        uint256 reading = 0;
        for (uint256 i = 0; i < candidates.length; i++) {
            LibRainDeploy.etchDependencies(vm, candidates[i].snapshot.dependencies);
            bytes memory creationCode = candidates[i].snapshot.creationCode;
            bytes memory reverted;
            bool deployed;
            assembly ("memory-safe") {
                deployed := iszero(iszero(create(0, add(creationCode, 0x20), mload(creationCode))))
                let size := returndatasize()
                reverted := mload(0x40)
                mstore(reverted, size)
                returndatacopy(add(reverted, 0x20), 0, size)
                mstore(0x40, add(add(reverted, 0x20), size))
            }
            bool readsOwner = !deployed && keccak256(reverted) == keccak256(unbound);
            string memory suite = candidates[i].snapshot.suite;
            bytes4 selector;
            assembly ("memory-safe") {
                selector := mload(add(reverted, 0x20))
            }
            assertFalse(
                !readsOwner && !deployed && reverted.length >= 4
                    && selector == IConfigRegistryV5.NameNotRegistered.selector,
                string.concat("another unbound name read by ", suite)
            );
            assertEq(readsOwner, isBeaconOwnerSuite(keccak256(bytes(suite))), suite);
            if (readsOwner) {
                reading++;
            }
        }
        assertEq(reading, beaconOwnerSuites().length, "every listed suite is a candidate that reads the binding");
    }

    /// The membership check matches each listed key and nothing else.
    function testIsBeaconOwnerSuite() external pure {
        string[] memory suites = beaconOwnerSuites();
        for (uint256 i = 0; i < suites.length; i++) {
            assertTrue(isBeaconOwnerSuite(keccak256(bytes(suites[i]))), suites[i]);
        }
        assertFalse(isBeaconOwnerSuite(keccak256(bytes(GOVERNANCE_TIMELOCK))), "timelock");
        assertFalse(isBeaconOwnerSuite(keccak256(bytes(RECEIPT_VAULT))), "implementation");
        assertFalse(isBeaconOwnerSuite(keccak256("")), "empty");
    }
}
