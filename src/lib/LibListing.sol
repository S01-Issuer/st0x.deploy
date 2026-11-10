// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity ^0.8.25;

import {MessageHashUtils} from "@openzeppelin-contracts-5.7.0/utils/cryptography/MessageHashUtils.sol";
import {LibConfigRegistry} from "rain-deploy-0.1.30/src/lib/LibConfigRegistry.sol";
import {LibProdDeployCurrent} from "../generated/LibProdDeployCurrent.sol";
import {ListingSignerBindingMalformed} from "../error/ErrListing.sol";

/// @dev `abi.encode(address)`: the listing signer, bound under `LISTING_AUTHORITY`.
bytes32 constant LISTING_SIGNER_NAME = keccak256("st0x.listing-signer.v1");

/// @dev The authority the listing signer is bound under: the V6 governance timelock, so every bind is a timelock
/// operation.
address constant LISTING_AUTHORITY = LibProdDeployCurrent.STOX_GOVERNANCE_TIMELOCK;

/// @dev The EIP-712 domain type of a listing: no chain id and no verifying contract, so one signature holds on every
/// chain.
bytes32 constant LISTING_DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version)");

/// @dev The EIP-712 domain name of a listing.
string constant LISTING_DOMAIN_NAME = "ST0x Listing";

/// @dev The EIP-712 domain version of a listing.
string constant LISTING_DOMAIN_VERSION = "1";

/// @dev The EIP-712 domain separator of a listing.
bytes32 constant LISTING_DOMAIN_SEPARATOR = keccak256(
    abi.encode(LISTING_DOMAIN_TYPEHASH, keccak256(bytes(LISTING_DOMAIN_NAME)), keccak256(bytes(LISTING_DOMAIN_VERSION)))
);

/// @dev The EIP-712 struct type the listing signer signs.
bytes32 constant LISTING_TYPEHASH = keccak256("Listing(bytes32 root)");

/// @title LibListing
/// @notice The leaf, the signed digest and the signer binding of a listing (see `IStoxListingV1`).
library LibListing {
    /// @notice The OpenZeppelin `StandardMerkleTree` leaf of `(address,string,string,string)`.
    /// @param token The token the leaf names.
    /// @param assetId The token's asset id.
    /// @param ticker The underlying ticker.
    /// @param name The underlying name.
    /// @return The leaf.
    function leaf(address token, string memory assetId, string memory ticker, string memory name)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(bytes.concat(keccak256(abi.encode(token, assetId, ticker, name))));
    }

    /// @notice The EIP-712 digest the listing signer signs for `root`.
    /// @param root The listing root.
    /// @return The digest.
    function digest(bytes32 root) internal pure returns (bytes32) {
        return MessageHashUtils.toTypedDataHash(LISTING_DOMAIN_SEPARATOR, keccak256(abi.encode(LISTING_TYPEHASH, root)));
    }

    /// @notice The bound listing signer; reverts unless the binding is one canonically encoded `address`.
    /// @return The signer.
    function signer() internal view returns (address) {
        // slither-disable-next-line unused-return
        (bytes memory value,) = LibConfigRegistry.resolve(LISTING_AUTHORITY, LISTING_SIGNER_NAME, keccak256("address"));
        if (value.length != 0x20) revert ListingSignerBindingMalformed(value);
        uint256 word = abi.decode(value, (uint256));
        if (word >> 160 != 0) revert ListingSignerBindingMalformed(value);
        // forge-lint: disable-next-line(unsafe-typecast)
        return address(uint160(word));
    }
}
