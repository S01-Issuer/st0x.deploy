// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RevokeFireblocksServiceSigner} from "../../script/20260810-revoke-fireblocks-service-signer.s.sol";

/// @title RevokeFireblocksServiceSignerRemainderHarness
/// @notice The partial-re-dispatch fixture's script: identical to the
/// production script except the artifact lands on a dedicated path. The
/// partial test's bundle content DIFFERS from the full-bundle tests' on
/// the same chain, and forge runs tests in parallel, so writing the
/// canonical path would race with them. Its own file because Rain
/// convention is one contract per .sol.
contract RevokeFireblocksServiceSignerRemainderHarness is RevokeFireblocksServiceSigner {
    /// @notice The dedicated remainder-artifact path, exposed so the test
    /// parses exactly the file this fixture wrote.
    /// @return path The remainder artifact path for the ACTIVE chain.
    function remainderArtifactPath() public view returns (string memory path) {
        path = string.concat("out/20260810-revoke-remainder-", vm.toString(block.chainid), ".json");
    }

    function artifactPath() internal view override returns (string memory path) {
        path = remainderArtifactPath();
    }
}
