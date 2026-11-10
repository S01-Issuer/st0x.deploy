// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibV6Listing} from "../../../src/lib/LibV6Listing.sol";
import {V6ReleaseBaseFork} from "../../abstract/V6ReleaseBaseFork.sol";

/// @title LibV6ListingBaseForkTest
/// @notice On a Base fork, the frozen V6 listing, signed by a test listing signer, deploys and names every token it
/// lists, the test tokens included, each in one transaction.
contract LibV6ListingBaseForkTest is V6ReleaseBaseFork {
    function setUp() external {
        forkBase();
    }

    /// Listed row `index`, deployed and named from `LibV6Listing.ROOT`, in its own call frame.
    function deployAndNameListed(uint256 index) external returns (address) {
        return deployAndName(LibV6Listing.configs()[index], LibV6Listing.rows(), index);
    }

    function testTheListingNamesEveryListedToken() external {
        this.deployReleaseFrame();
        bindListingSigner();
        TokenConfig[] memory listed = LibV6Listing.configs();
        for (uint256 i = 0; i < listed.length; i++) {
            this.deployAndNameListed(i);
        }
    }
}
