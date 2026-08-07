// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title LibNonceCloneFactory
/// @notice Pins for the nonce-based `CloneFactory` (rain-factory 0.1.1) that
/// every live V4 authoriser clone was deployed through. rain-factory 0.1.5's
/// `LibCloneFactoryDeploy` pins the deterministic-only factory, which exposes
/// no `clone(address,bytes)` — the clone-deploy script must keep targeting the
/// nonce-based factory these pins describe.
library LibNonceCloneFactory {
    /// The address of the nonce-based `CloneFactory` when deployed with the
    /// rain standard zoltu deployer.
    address constant CLONE_FACTORY_DEPLOYED_ADDRESS = address(0x444acC29d63fa643E8adCC35FD9aa6DE111dCb39);

    /// The code hash of the nonce-based `CloneFactory` when deployed with the
    /// rain standard zoltu deployer. This can be used to verify that the
    /// deployed contract has the expected bytecode, which provides stronger
    /// guarantees than just checking the address.
    bytes32 constant CLONE_FACTORY_DEPLOYED_CODEHASH =
        bytes32(0xf21b813c7075a1621285df3a8369d0652c31ea80cb807be1aaadafeecd134475);

    /// The full runtime bytecode of the nonce-based `CloneFactory` as deployed,
    /// read from the live Base deploy. The codehash pin alone cannot recreate
    /// historical behavior once compiler/optimizer drift makes the source
    /// unable to reproduce it; the embedded code can.
    /// `CLONE_FACTORY_DEPLOYED_CODEHASH == keccak256(CLONE_FACTORY_DEPLOYED_CODE)`.
    bytes constant CLONE_FACTORY_DEPLOYED_CODE =
        hex"608060405234801561000f575f80fd5b5060043610610029575f3560e01c80630fbe133c1461002d575b5f80fd5b61004061003b3660046102fb565b610069565b60405173ffffffffffffffffffffffffffffffffffffffff909116815260200160405180910390f35b5f8373ffffffffffffffffffffffffffffffffffffffff163b5f036100ba576040517ff432283200000000000000000000000000000000000000000000000000000000815260040160405180910390fd5b5f6100c485610213565b6040805133815273ffffffffffffffffffffffffffffffffffffffff888116602083015283168183015290519192507f274b5f356634f32a865af65bdc3d8205939d9413d75e1f367652e4f3b24d0c3a919081900360600190a16040517f439fab910000000000000000000000000000000000000000000000000000000081527fe0e57eda3f08f2a93bbe980d3df7f9c315eac41181f58b865a13d917fe769fc39073ffffffffffffffffffffffffffffffffffffffff83169063439fab91906101949088908890600401610391565b6020604051808303815f875af11580156101b0573d5f803e3d5ffd5b505050506040513d601f19601f820116820180604052508101906101d491906103dd565b1461020b576040517f19b991a800000000000000000000000000000000000000000000000000000000815260040160405180910390fd5b949350505050565b5f61021e825f610224565b92915050565b5f8147101561026c576040517fcf4791810000000000000000000000000000000000000000000000000000000081524760048201526024810183905260440160405180910390fd5b763d602d80600a3d3981f3363d3d373d3d3d363d730000008360601b60e81c175f526e5af43d82803e903d91602b57fd5bf38360781b176020526037600983f0905073ffffffffffffffffffffffffffffffffffffffff811661021e576040517fb06ebf3d00000000000000000000000000000000000000000000000000000000815260040160405180910390fd5b5f805f6040848603121561030d575f80fd5b833573ffffffffffffffffffffffffffffffffffffffff81168114610330575f80fd5b9250602084013567ffffffffffffffff8082111561034c575f80fd5b818601915086601f83011261035f575f80fd5b81358181111561036d575f80fd5b87602082850101111561037e575f80fd5b6020830194508093505050509250925092565b60208152816020820152818360408301375f818301604090810191909152601f9092017fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe0160101919050565b5f602082840312156103ed575f80fd5b505191905056";
}
