// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IMulticall3} from "forge-std-1.17.0/src/interfaces/IMulticall3.sol";

import {LibProdTokenConfig, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibProdTokenParams} from "../../../src/lib/LibProdTokenParams.sol";
import {LibListingTree, ListingRow} from "../../../src/lib/LibListingTree.sol";
import {LibTestListingMulticall, MULTICALL3, MULTICALL3_CODEHASH} from "../../lib/LibTestListingMulticall.sol";
import {V6ReleaseBaseFork} from "../../abstract/V6ReleaseBaseFork.sol";

/// @title StoxDeploySuitesV6TokensBaseForkTest
/// @notice On a Base fork, every production row deploys through its V6 token suite and is named from a signed listing
/// in the same Multicall3 transaction; a refused naming leaves no token behind.
contract StoxDeploySuitesV6TokensBaseForkTest is V6ReleaseBaseFork {
    uint256 internal constant OTHER_KEY = uint256(keccak256("st0x.test.v6-tokens-base-fork.other-signer"));

    function setUp() external {
        forkBase();
    }

    /// Every row deploys and is named in its own one-transaction `aggregate3`.
    function testEveryRowDeploysAndIsNamedInOneTransaction() external {
        assertEq(MULTICALL3.codehash, MULTICALL3_CODEHASH, "Multicall3 at the pinned block");
        this.deployReleaseFrame();
        bindListingSigner();
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        for (uint256 i = 0; i < configs.length; i++) {
            this.deployAndNameRow(i);
        }
    }

    /// A token someone else deployed first makes the two-call transaction revert; its naming alone then names it.
    function testAFrontRunDeployIsNamedAlone() external {
        this.deployReleaseFrame();
        bindListingSigner();
        ListingRow[] memory listed = listing();
        bytes32 root = LibListingTree.root(listed);
        bytes memory signature = signListing(LISTING_SIGNER_KEY, root);
        TokenConfig memory config = LibProdTokenConfig.productionTokenConfigs()[0];
        IMulticall3.Call3[] memory calls = LibTestListingMulticall.deployAndName(
            LibProdTokenParams.tokenParam(config), listed[0], LibListingTree.proof(listed, 0), root, signature
        );
        vm.prank(address(uint160(uint256(keccak256("st0x.test.v6-tokens-base-fork.front-runner")))));
        (bool deployed,) = calls[0].target.call(calls[0].callData);
        assertTrue(deployed, "front-run deploy");

        vm.prank(DEPLOYER);
        vm.expectRevert(bytes("Multicall3: call failed"));
        IMulticall3(MULTICALL3).aggregate3(calls);

        IMulticall3.Call3[] memory nameOnly = new IMulticall3.Call3[](1);
        nameOnly[0] = calls[1];
        vm.prank(DEPLOYER);
        IMulticall3(MULTICALL3).aggregate3(nameOnly);
        assertNamed(config, listed[0].token);
    }

    /// A naming the bound signer did not sign reverts the whole transaction, so the token is not deployed.
    function testARefusedNamingDeploysNothing() external {
        this.deployReleaseFrame();
        bindListingSigner();
        ListingRow[] memory listed = listing();
        bytes32 root = LibListingTree.root(listed);
        TokenConfig memory config = LibProdTokenConfig.productionTokenConfigs()[0];
        IMulticall3.Call3[] memory calls = LibTestListingMulticall.deployAndName(
            LibProdTokenParams.tokenParam(config),
            listed[0],
            LibListingTree.proof(listed, 0),
            root,
            signListing(OTHER_KEY, root)
        );
        vm.prank(DEPLOYER);
        vm.expectRevert(bytes("Multicall3: call failed"));
        IMulticall3(MULTICALL3).aggregate3(calls);
        assertEq(listed[0].token.code.length, 0, "no token");
    }
}
