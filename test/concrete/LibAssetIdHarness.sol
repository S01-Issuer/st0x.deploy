// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {LibAssetId} from "../../src/lib/LibAssetId.sol";

contract LibAssetIdHarness {
    function decodeMetadata(bytes memory metadata) external pure returns (string memory) {
        return LibAssetId.decodeMetadata(metadata);
    }
}
