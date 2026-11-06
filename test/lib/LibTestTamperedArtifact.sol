// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.30/src/lib/LibSafeTxBuilderJson.sol";

interface IArtifactVerifier {
    function verify(string calldata jsonPath) external view;
}

library LibTestTamperedArtifact {
    /// @dev `verify` accepts `json` and refuses `tampered` on its calldata.
    /// Each is written to its own path so no other test's artifact is read.
    function assertVerifyRefusesTamper(
        Vm vm,
        address verifier,
        string memory json,
        string memory tampered,
        string memory stem
    ) internal {
        string memory chain = vm.toString(block.chainid);
        string memory cleanPath = string.concat("out/", stem, "-clean-", chain, ".json");
        vm.writeFile(cleanPath, json);
        IArtifactVerifier(verifier).verify(cleanPath);
        vm.assertNotEq(keccak256(bytes(tampered)), keccak256(bytes(json)), "tamper did not apply");
        string memory tamperedPath = string.concat("out/", stem, "-tampered-", chain, ".json");
        vm.writeFile(tamperedPath, tampered);
        vm.expectRevert(abi.encodeWithSelector(LibSafeTxBuilderJson.ArtifactMismatch.selector, "data"));
        IArtifactVerifier(verifier).verify(tamperedPath);
    }
}
