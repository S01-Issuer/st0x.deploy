// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {SupportedNetwork} from "rain-deploy-0.1.41/src/lib/LibRainDeploy.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {DeployPreDeployCheckHarness} from "./DeployPreDeployCheckHarness.sol";

/// @title DeployZerogNetworksTest
/// @notice A run reaches 0G only for the suites 0G runs: the audited 0.1.1
/// and 0.1.30 releases but the 0.1.1 payment-mint authoriser, and the EU and
/// US authoriser clones.
/// Every other release and candidate runs on the other deployment networks.
contract DeployZerogNetworksTest is Test {
    DeployPreDeployCheckHarness internal harness;

    function setUp() public {
        harness = new DeployPreDeployCheckHarness();
    }

    function onZerog(SupportedNetwork[] memory networks) internal pure returns (bool) {
        for (uint256 i = 0; i < networks.length; i++) {
            if (networks[i].chainId == LibSafeInvariants.ZEROG_CHAIN_ID) return true;
        }
        return false;
    }

    /// @dev `networks` is exactly `expected`, in order.
    function assertNetworks(SupportedNetwork[] memory networks, string[] memory expected, string memory suite)
        internal
        pure
    {
        assertEq(networks.length, expected.length, suite);
        for (uint256 i = 0; i < networks.length; i++) {
            assertEq(networks[i].name, expected[i], suite);
        }
    }

    function assertEveryNetwork(SupportedNetwork[] memory networks, string memory suite) internal pure {
        assertNetworks(networks, LibStoxDeployNetworks.deploymentNetworks(), suite);
        assertTrue(onZerog(networks), suite);
    }

    /// @dev A candidate kept off 0G: every other deployment network.
    function assertOffZerog(SupportedNetwork[] memory networks, string memory suite) internal pure {
        assertNetworks(networks, LibStoxDeployNetworks.networksWithout(LibStoxDeployNetworks.ZEROG), suite);
        assertFalse(onZerog(networks), suite);
    }

    /// @dev A release kept off 0G: the networks it was cut for.
    function assertBeforeZerog(SupportedNetwork[] memory networks, string memory suite) internal pure {
        assertNetworks(networks, LibStoxDeployNetworks.networksBeforeZerog(), suite);
        assertFalse(onZerog(networks), suite);
    }

    function assertZerogAlone(SupportedNetwork[] memory networks, string memory suite) internal pure {
        assertEq(networks.length, 1, suite);
        assertEq(networks[0].chainId, LibSafeInvariants.ZEROG_CHAIN_ID, suite);
    }

    function assertRunsOnEveryNetwork(string memory suite) internal view {
        assertEveryNetwork(harness.deployNetworkConfigsFor(suite), suite);
    }

    function assertRunsOffZerog(string memory suite) internal view {
        assertOffZerog(harness.deployNetworkConfigsFor(suite), suite);
    }

    function assertRunsBeforeZerog(string memory suite) internal view {
        assertBeforeZerog(harness.deployNetworkConfigsFor(suite), suite);
    }

    /// @notice `declaration()` itself narrows a run to the networks of the suite
    /// it deploys: a 0G-only suite to 0G alone, a suite kept off 0G to the
    /// other networks, and no suite or an unknown one to every network.
    function testDeclarationNarrowsToTheRequestedSuite() external {
        harness.setRequestedSuite("stox-us-assets-authoriser");
        assertZerogAlone(harness.deployNetworkConfigs(), "stox-us-assets-authoriser");

        harness.setRequestedSuite("stox-eu-assets-authoriser");
        assertEveryNetwork(harness.deployNetworkConfigs(), "stox-eu-assets-authoriser");

        harness.setRequestedSuite("stox-token-tmstr");
        assertOffZerog(harness.deployNetworkConfigs(), "stox-token-tmstr");

        harness.setRequestedSuite("stox-receipt-vault");
        assertOffZerog(harness.deployNetworkConfigs(), "stox-receipt-vault");

        harness.setRequestedSuite("stox-offchain-asset-receipt-vault-payment-mint-authorizer@0_1_1");
        assertBeforeZerog(harness.deployNetworkConfigs(), "payment-mint authoriser release");

        harness.setRequestedSuite("stox-orchestrator-beacon-set-deployer@0_1_30");
        assertEveryNetwork(harness.deployNetworkConfigs(), "orchestrator beacon-set deployer release");

        harness.setRequestedSuite("not-a-suite");
        assertEveryNetwork(harness.deployNetworkConfigs(), "not-a-suite");
    }

    /// @notice A run's suite is what `DEPLOYMENT_SUITE` holds, read by
    /// `Deploy` itself. `vm.setEnv` is process-wide, so this is the only test
    /// that sets the variable and the only harness that reads it.
    function testDeclarationNarrowsToTheDeploymentSuiteVariable() external {
        harness.readRequestedSuiteFromEnv();

        vm.setEnv("DEPLOYMENT_SUITE", "stox-us-assets-authoriser");
        assertZerogAlone(harness.deployNetworkConfigs(), "stox-us-assets-authoriser");

        vm.setEnv("DEPLOYMENT_SUITE", "stox-token-tmstr");
        assertOffZerog(harness.deployNetworkConfigs(), "stox-token-tmstr");

        vm.setEnv("DEPLOYMENT_SUITE", "");
        assertEveryNetwork(harness.deployNetworkConfigs(), "no suite");
    }

    /// @notice With no suite named, a run's networks are every deployment network.
    function testNoSuiteRunsOnEveryDeploymentNetwork() external view {
        assertEq(harness.deployNetworkConfigs().length, LibStoxDeployNetworks.deploymentNetworks().length);
        assertEq(harness.deployNetworkConfigsFor("").length, LibStoxDeployNetworks.deploymentNetworks().length);
    }

    function testTheZerogReleasesRunOnZerog() external view {
        string[15] memory releases = [
            "stox-corporate-actions-facet@0_1_1",
            "stox-receipt@0_1_1",
            "stox-receipt-vault@0_1_1",
            "stox-wrapped-token-vault@0_1_1",
            "stox-wrapped-token-vault-beacon@0_1_1",
            "stox-wrapped-token-vault-beacon-set-deployer@0_1_1",
            "stox-offchain-asset-receipt-vault-beacon-set-deployer@0_1_1",
            "stox-unified-deployer@0_1_1",
            "stox-offchain-asset-receipt-vault-authorizer@0_1_1",
            "stox-corporate-actions-facet@0_1_30",
            "stox-receipt@0_1_30",
            "stox-receipt-vault@0_1_30",
            "stox-offchain-asset-receipt-vault-beacon-set-deployer@0_1_30",
            "stox-orchestrator@0_1_30",
            "stox-orchestrator-beacon-set-deployer@0_1_30"
        ];
        for (uint256 i = 0; i < releases.length; i++) {
            assertRunsOnEveryNetwork(releases[i]);
        }
    }

    function testTheEuAuthoriserCloneRunsOnZerog() external view {
        assertRunsOnEveryNetwork("stox-eu-assets-authoriser");
    }

    /// @notice The US authoriser clone runs on 0G alone: every other chain's
    /// US clone is the first `clone` of the 0.1.1 factory.
    function testTheUsAuthoriserCloneRunsOnZerogAlone() external view {
        assertZerogAlone(harness.deployNetworkConfigsFor("stox-us-assets-authoriser"), "stox-us-assets-authoriser");
    }

    /// @notice The 0.1.1 payment-mint authoriser never runs on 0G: no 0G token
    /// mints through it.
    function testTheReleasesNotOnZerogRunOffZerog() external view {
        assertRunsBeforeZerog("stox-offchain-asset-receipt-vault-payment-mint-authorizer@0_1_1");
    }

    /// @notice The V4 candidates, the token suites and the orchestrator proxy
    /// never run on 0G.
    function testTheCandidatesRunOffZerog() external view {
        string[8] memory candidates = [
            "stox-receipt-vault",
            "stox-governance-timelock",
            "stox-receipt-beacon",
            "stox-orchestrator",
            "stox-offchain-asset-receipt-vault-payment-mint-authorizer",
            "stox-orchestrator-proxy",
            "stox-token-tmstr",
            "stox-token-tmstr-wrapper"
        ];
        for (uint256 i = 0; i < candidates.length; i++) {
            assertRunsOffZerog(candidates[i]);
        }
    }
}
