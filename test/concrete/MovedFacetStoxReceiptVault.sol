// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {StoxReceiptVault} from "../../src/concrete/StoxReceiptVault.sol";

/// A vault implementation whose fallback delegatecalls a corporate-actions facet at another address, the shape of a
/// facet upgrade.
contract MovedFacetStoxReceiptVault is StoxReceiptVault {
    address internal immutable I_FACET;

    // forge-lint: disable-next-line(missing-zero-check)
    constructor(address facet) {
        I_FACET = facet;
    }

    fallback() external payable override {
        address facet = I_FACET;
        assembly ("memory-safe") {
            calldatacopy(0, 0, calldatasize())
            let success := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch success
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}
