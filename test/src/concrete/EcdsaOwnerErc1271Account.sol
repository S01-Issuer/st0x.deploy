// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {IERC1271} from "@openzeppelin-contracts-5.7.0/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin-contracts-5.7.0/utils/cryptography/ECDSA.sol";

/// @dev An ERC-1271 account whose valid signatures are its owner key's ECDSA
/// signatures over the exact hash asked about.
contract EcdsaOwnerErc1271Account is IERC1271 {
    address internal immutable I_OWNER;

    constructor(address owner) {
        I_OWNER = owner;
    }

    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4) {
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(hash, signature);
        return err == ECDSA.RecoverError.NoError && recovered == I_OWNER
            ? IERC1271.isValidSignature.selector
            : bytes4(0xffffffff);
    }
}
