// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {SafeTx} from "rain-deploy-0.1.43/src/lib/LibSafeTx.sol";

import {StoxSafeBundleScript} from "../../src/abstract/StoxSafeBundleScript.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";

contract StoxSafeBundleScriptHarness is StoxSafeBundleScript {
    function safe() internal view override returns (Safe) {
        return Safe(payable(LibSafeInvariants.safeForChainId(block.chainid)));
    }

    function preflight() internal pure override {}

    function authorBundle() internal pure override returns (SafeTx[] memory) {
        return new SafeTx[](0);
    }

    function assertPostState() internal pure override {}

    function artifactPath() internal pure override returns (string memory) {
        return "out/stox-safe-bundle-script-harness.json";
    }

    function bundleName() internal pure override returns (string memory) {
        return "StoxSafeBundleScriptHarness";
    }
}
