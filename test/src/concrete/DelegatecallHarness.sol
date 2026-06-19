// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibCorporateAction} from "../../../src/lib/LibCorporateAction.sol";
import {IAuthorizeV1} from "rain-vats-0.1.6/src/interface/IAuthorizeV1.sol";

/// @dev Minimal harness that delegates calls to a facet. Also exposes an
/// `authorizer()` function so the facet's `OffchainAssetReceiptVault(address
/// (this)).authorizer()` lookup resolves to a test-controlled mock instead of
/// a real rain.vats authorizer.
contract DelegatecallHarness {
    address public immutable FACET;
    IAuthorizeV1 public authorizer;
    uint8 public constant decimals = 18;

    constructor(address facet_) {
        FACET = facet_;
    }

    function setAuthorizer(IAuthorizeV1 authorizer_) external {
        authorizer = authorizer_;
    }

    /// @dev Schedule directly via the library, bypassing auth and
    /// `resolveActionType` validation. Runs in this harness's storage so that
    /// a subsequent delegatecalled `getActionParameters` (which also runs in
    /// this harness's storage) observes the write. Exists purely to support
    /// fuzzing arbitrary `bytes` payloads that the normal facet path would
    /// reject.
    function scheduleRaw(uint256 actionType, uint64 effectiveTime, bytes memory parameters) external returns (uint256) {
        return LibCorporateAction.schedule(actionType, effectiveTime, parameters);
    }

    fallback() external payable {
        address target = FACET;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let success := delegatecall(gas(), target, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch success
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}
}
