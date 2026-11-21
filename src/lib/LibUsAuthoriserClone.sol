// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {LibICloneableFactoryV5} from "rain-factory-0.2.18/src/lib/LibICloneableFactoryV5.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY_ADDRESS
} from "rain-factory-deploy-0.2.14/src/generated/0_1_15/CloneFactory.sol";

import {LibEuAuthoriserClone} from "./LibEuAuthoriserClone.sol";

// The open salt for the US assets authoriser on a chain that has no clone yet.
// Open for the same reason as the EU salt: the digest covers the
// implementation and the init data and NOT the caller, so a frontrunner can
// only deploy the clone we specified, with the chain's Safe as initial admin.
bytes32 constant US_AUTHORISER_SALT = keccak256("st0x.us-assets-authoriser");

/// @title LibUsAuthoriserClone
/// @notice Where the US assets authoriser clone lands on a chain whose clone
/// comes from CloneFactory 0.1.15's open-salt path, starting with 0G. The
/// earlier chains' US clones are the first `CloneFactory.clone` of the 0.1.1
/// factory, an address any caller can take with any init data, so a new
/// chain does not reuse that path.
///
/// The clone is the EU clone's twin: the same audited 0.1.1 implementation
/// and the same init data (the chain's token-owner Safe as initial admin),
/// under another salt. So the code hash is the shared clone code hash, and
/// whoever deploys it, the Safe is its only initial admin.
library LibUsAuthoriserClone {
    /// @notice The address the clone lands at on one chain.
    /// @param chainId The chain the clone is for.
    /// @return The predicted clone address.
    function cloneDeployedAddress(uint256 chainId) internal pure returns (address) {
        return LibICloneableFactoryV5.predictCloneAddress(
            CLONE_FACTORY_ADDRESS,
            LibEuAuthoriserClone.implementation(),
            LibICloneableFactoryV5.effectiveOpenSalt(US_AUTHORISER_SALT, LibEuAuthoriserClone.cloneData(chainId))
        );
    }
}
