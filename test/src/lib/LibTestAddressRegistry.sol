// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.16.2/src/Vm.sol";

import {ADDRESS_REGISTRY_ROOT} from "rain-deploy-0.1.11/src/concrete/AddressRegistry.sol";
import {IAddressRegistryV1} from "rain-deploy-0.1.11/src/interface/IAddressRegistryV1.sol";
import {LibAddressRegistryDeploy} from "rain-deploy-0.1.11/src/lib/LibAddressRegistryDeploy.sol";
import {
    RUNTIME_CODE as ADDRESS_REGISTRY_RUNTIME_CODE
} from "rain-deploy-0.1.11/src/generated/candidate/AddressRegistry.sol";

/// @title LibTestAddressRegistry
/// @notice Puts the real `AddressRegistry` at its real address on a local
/// test EVM, so a contract that resolves a name in its initializer can be
/// deployed in a unit test.
///
/// The registry is etched rather than mocked. `LibAddressRegistry.resolve`
/// checks the code hash at the pinned address before reading, and the pinned
/// hash is the hash of the recorded runtime code, so the only thing that
/// satisfies it is that code at that address — a mock would have to be the
/// registry to pass, at which point it is simpler to be it. Bindings are then
/// real storage writes through `register`, which means the tests exercise the
/// reverting read on an unbound name for free rather than asserting against a
/// stub's idea of one.
library LibTestAddressRegistry {
    /// @notice Etch the registry and bind `name` to `account`.
    /// @param vm The forge VM.
    /// @param name The registry name to bind.
    /// @param account The address to bind it to.
    function etchAndBind(Vm vm, bytes32 name, address account) internal {
        etch(vm);
        bind(vm, name, account);
    }

    /// @notice Etch the registry's runtime code at its pinned address,
    /// leaving every name unbound. A `resolve` of any name then reverts
    /// `NameNotRegistered` rather than `UnexpectedAddressRegistryCodeHash`,
    /// which is what a test about an unbound name wants.
    /// @param vm The forge VM.
    function etch(Vm vm) internal {
        vm.etch(LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS, ADDRESS_REGISTRY_RUNTIME_CODE);
    }

    /// @notice Bind `name` to `account`, as the registry's root. Root is a
    /// compile-time constant in the registry's own code, so a test binds by
    /// pranking it; there is no other authority to bind with.
    /// @param vm The forge VM.
    /// @param name The registry name to bind.
    /// @param account The address to bind it to.
    function bind(Vm vm, bytes32 name, address account) internal {
        vm.prank(ADDRESS_REGISTRY_ROOT);
        IAddressRegistryV1(LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS).register(name, account);
    }

    /// @notice Leave `name` unbound, so a `resolve` of it reverts
    /// `NameNotRegistered`.
    ///
    /// The registry has no unbind — "There is no removal, no upgrade and no
    /// authority beyond root, and an implementation MUST NOT add any" — so
    /// this writes the slot directly rather than calling the contract.
    /// `etch` cannot do it: it replaces code and leaves storage, so a name
    /// bound earlier in a test stays bound through a re-etch.
    /// `sAddresses` is the registry's only state variable, hence slot 0.
    /// @param vm The forge VM.
    /// @param name The registry name to unbind.
    function unbind(Vm vm, bytes32 name) internal {
        vm.store(
            LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
            keccak256(abi.encode(name, uint256(0))),
            bytes32(0)
        );
    }
}
