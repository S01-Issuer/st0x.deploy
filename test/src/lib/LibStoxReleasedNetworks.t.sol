// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeploySuite} from "rain-deploy-0.1.38/src/abstract/RainDeploySuitesBase.sol";
import {LibReleasedSuites} from "../../../src/lib/LibReleasedSuites.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibStoxReleasedNetworks, ReleaseNotOnZerogUnknown} from "../../../src/lib/LibStoxReleasedNetworks.sol";

/// @title LibStoxReleasedNetworksTest
/// @notice Every frozen release is required on every deployment network, 0G
/// included, except the 0.1.1 payment-mint authoriser and the 0.1.30
/// orchestrator beacon-set deployer, which stay on the networks before 0G.
contract LibStoxReleasedNetworksTest is Test {
    string internal constant PAYMENT_MINT = "stox-offchain-asset-receipt-vault-payment-mint-authorizer@0_1_1";
    string internal constant ORCHESTRATOR_SET_DEPLOYER = "stox-orchestrator-beacon-set-deployer@0_1_30";

    function offZerog(string memory suite) internal pure returns (bool) {
        bytes32 key = keccak256(bytes(suite));
        return key == keccak256(bytes(PAYMENT_MINT)) || key == keccak256(bytes(ORCHESTRATOR_SET_DEPLOYER));
    }

    function testOnlyTheReleasesNotOnZerogAreNarrowed() external pure {
        DeploySuite[] memory released = LibStoxReleasedNetworks.releasedSuites();
        DeploySuite[] memory frozen = LibReleasedSuites.releasedSuites();
        string[] memory before = LibStoxDeployNetworks.networksBeforeZerog();
        assertEq(released.length, frozen.length, "every release");
        uint256 narrowed = 0;
        for (uint256 i = 0; i < released.length; i++) {
            assertEq(released[i].suite, frozen[i].suite, "release order");
            if (!offZerog(released[i].suite)) {
                assertEq(released[i].networks.length, frozen[i].networks.length, "unchanged");
                continue;
            }
            narrowed++;
            assertEq(released[i].networks.length, before.length, "networks before 0G");
            for (uint256 j = 0; j < before.length; j++) {
                assertEq(released[i].networks[j], before[j], "network");
            }
        }
        assertEq(narrowed, 2, "two releases off 0G");
    }

    /// @notice 0G runs only the audited 0.1.1 and 0.1.30 releases, so every
    /// release this repo has cut is one of them.
    function testEveryReleaseIsA0_1_1Or0_1_30Release() external pure {
        DeploySuite[] memory released = LibStoxReleasedNetworks.releasedSuites();
        for (uint256 i = 0; i < released.length; i++) {
            bytes memory key = bytes(released[i].suite);
            assertTrue(endsWith(key, "@0_1_1") || endsWith(key, "@0_1_30"), released[i].suite);
        }
    }

    function testAKeyNoReleaseHasIsRefused() external {
        string[] memory keys = new string[](1);
        keys[0] = "stox-receipt@0_1_2";
        vm.expectRevert(abi.encodeWithSelector(ReleaseNotOnZerogUnknown.selector, keys[0]));
        this.offZerog(keys);
    }

    function offZerog(string[] memory keys) external pure returns (DeploySuite[] memory) {
        return LibStoxReleasedNetworks.offZerog(LibReleasedSuites.releasedSuites(), keys);
    }

    function endsWith(bytes memory s, bytes memory suffix) internal pure returns (bool) {
        if (s.length < suffix.length) return false;
        for (uint256 i = 0; i < suffix.length; i++) {
            if (s[s.length - suffix.length + i] != suffix[i]) return false;
        }
        return true;
    }
}
