// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IAuthorizeV1} from "ethgild/interface/IAuthorizeV1.sol";
import {
    EffectiveTimeMustBeFuture,
    ActionNotScheduled,
    ActionNotYetEffective,
    ActionDoesNotExist
} from "../error/ErrCorporateActionRegistry.sol";

/// @dev Well known action type for name/symbol updates.
bytes32 constant ACTION_TYPE_NAME_SYMBOL = keccak256("NAME_SYMBOL");

/// @dev Permission for updating name/symbol on a vault. The registry must hold
/// this role in the authorizer to execute name/symbol corporate actions.
bytes32 constant UPDATE_NAME_SYMBOL = keccak256("UPDATE_NAME_SYMBOL");

/// @dev Admin role for UPDATE_NAME_SYMBOL permission.
bytes32 constant UPDATE_NAME_SYMBOL_ADMIN = keccak256("UPDATE_NAME_SYMBOL_ADMIN");

/// Represents the lifecycle of a corporate action.
/// SCHEDULED: Action has been registered and is pending execution.
/// IN_PROGRESS: Action is currently being executed (transient during tx).
/// COMPLETE: Action has been fully executed.
enum ActionState {
    NONE,
    SCHEDULED,
    IN_PROGRESS,
    COMPLETE
}

/// All data stored per corporate action.
/// @param actionType The type of action, e.g. keccak256("NAME_SYMBOL").
/// @param state The current lifecycle state of the action.
/// @param data ABI-encoded action-specific payload. For NAME_SYMBOL this is
/// (string newName, string newSymbol).
/// @param effectiveTime The timestamp at which this action becomes executable.
/// @param scheduledAt The timestamp at which this action was registered.
struct Action {
    bytes32 actionType;
    ActionState state;
    bytes data;
    uint256 effectiveTime;
    uint256 scheduledAt;
}

/// Represents the state change when a corporate action is scheduled.
/// Provided to the authorization contract so it can make decisions based on
/// the specifics of the scheduling.
/// @param token The token this action targets.
/// @param actionType The type of corporate action.
/// @param number The sequential number for this action type on this token.
/// @param data The action-specific payload.
/// @param effectiveTime When the action takes effect.
struct ScheduleStateChange {
    address token;
    bytes32 actionType;
    uint256 number;
    bytes data;
    uint256 effectiveTime;
}

/// Represents the state change when a corporate action is executed.
/// Provided to the authorization contract so it can make decisions based on
/// the specifics of the execution.
/// @param token The token this action targets.
/// @param actionType The type of corporate action.
/// @param number The sequential number for this action type on this token.
struct ExecuteStateChange {
    address token;
    bytes32 actionType;
    uint256 number;
}

/// @title CorporateActionRegistry
/// @notice A token-agnostic registry for scheduling and executing corporate
/// actions against st0x receipt vault tokens. The registry is NOT just an event
/// log — it stores onchain readable state that other contracts (lending
/// protocols, oracles, strategies) can query to reason about upcoming and
/// in-progress corporate actions and adjust behaviour accordingly.
///
/// This is critical for composability: downstream protocols can make independent
/// risk decisions without offchain coordination. For example, a lending protocol
/// can pause new borrows when a stock split is SCHEDULED, or an oracle consumer
/// can verify that its price feed accounts for the latest corporate action.
///
/// Action IDs are namespaced per token and per action type. This means action
/// number 1 for NAME_SYMBOL on token A is entirely separate from action number
/// 1 for SPLIT on token A, or NAME_SYMBOL number 1 on token B.
///
/// The registry itself does NOT hold privileged roles. Instead, when it
/// dispatches an action to a token contract, the token's authorizer checks that
/// the registry (as `msg.sender` to the token) holds the appropriate permission.
/// This follows the same daisy-chain authorizer pattern used throughout ethgild.
contract CorporateActionRegistry {
    /// Emitted when a corporate action is scheduled for future execution.
    /// @param sender The address that scheduled the action.
    /// @param token The token this action targets.
    /// @param actionType The type of corporate action.
    /// @param number The sequential number for this action type on this token.
    /// @param effectiveTime When the action becomes executable.
    event CorporateActionScheduled(
        address indexed sender, address indexed token, bytes32 indexed actionType, uint256 number, uint256 effectiveTime
    );

    /// Emitted when a corporate action is executed.
    /// @param sender The address that executed the action.
    /// @param token The token this action targets.
    /// @param actionType The type of corporate action.
    /// @param number The sequential number for this action type on this token.
    event CorporateActionExecuted(
        address indexed sender, address indexed token, bytes32 indexed actionType, uint256 number
    );

    /// Per-token, per-action-type sequential counters. The next action number
    /// for a given (token, actionType) pair is `counters[token][actionType] + 1`.
    mapping(address token => mapping(bytes32 actionType => uint256)) public counters;

    /// Per-token, per-action-type, per-number action storage. This is the
    /// core readable state that makes the registry useful to downstream
    /// protocols — not just events.
    mapping(address token => mapping(bytes32 actionType => mapping(uint256 number => Action))) internal sActions;

    /// Schedule a corporate action for a token. The action will be registered
    /// in SCHEDULED state and can be executed by anyone after its effective time
    /// passes.
    ///
    /// Authorization is checked via the token's authorizer. The caller must
    /// hold the relevant permission for the action type being scheduled. This
    /// ensures that scheduling is subject to the same RBAC governance as all
    /// other privileged operations on the vault.
    ///
    /// @param token The token this action targets.
    /// @param actionType The type of corporate action (e.g. ACTION_TYPE_NAME_SYMBOL).
    /// @param data ABI-encoded action-specific payload.
    /// @param effectiveTime The timestamp at which the action becomes executable.
    /// Must be strictly in the future.
    /// @return number The sequential number assigned to this action.
    function schedule(address token, bytes32 actionType, bytes calldata data, uint256 effectiveTime)
        external
        returns (uint256 number)
    {
        if (effectiveTime <= block.timestamp) {
            revert EffectiveTimeMustBeFuture(effectiveTime, block.timestamp);
        }

        number = ++counters[token][actionType];

        sActions[token][actionType][number] = Action({
            actionType: actionType,
            state: ActionState.SCHEDULED,
            data: data,
            effectiveTime: effectiveTime,
            scheduledAt: block.timestamp
        });

        // Authorization check. The caller must hold the appropriate permission
        // for scheduling this action type. We check AFTER writing state so the
        // authorizer can inspect the action if needed, matching the ethgild
        // pattern where authorize is called after state changes.
        _authorizeSchedule(token, actionType, number, data, effectiveTime);

        emit CorporateActionScheduled(msg.sender, token, actionType, number, effectiveTime);
    }

    /// Execute a previously scheduled action once its effective time has passed.
    /// Anyone can call execute — the permission check happened at schedule time,
    /// and the registry itself is trusted by the token's authorizer to dispatch.
    ///
    /// The registry dispatches to the token contract based on action type. The
    /// token contract verifies that msg.sender (this registry) holds the
    /// required role in its authorizer.
    ///
    /// @param token The token this action targets.
    /// @param actionType The type of corporate action.
    /// @param number The sequential number of the action to execute.
    function execute(address token, bytes32 actionType, uint256 number) external {
        Action storage action = sActions[token][actionType][number];

        if (action.state != ActionState.SCHEDULED) {
            revert ActionNotScheduled(token, actionType, number);
        }
        if (block.timestamp < action.effectiveTime) {
            revert ActionNotYetEffective(action.effectiveTime, block.timestamp);
        }

        action.state = ActionState.IN_PROGRESS;

        // Dispatch to the token contract based on action type.
        _dispatch(token, actionType, number, action.data);

        action.state = ActionState.COMPLETE;

        emit CorporateActionExecuted(msg.sender, token, actionType, number);
    }

    /// Read the full action struct for a given (token, actionType, number).
    /// Reverts if the action does not exist (number is beyond the counter).
    /// @param token The token address.
    /// @param actionType The type of corporate action.
    /// @param number The sequential number.
    /// @return The Action struct.
    function getAction(address token, bytes32 actionType, uint256 number) external view returns (Action memory) {
        _requireActionExists(token, actionType, number);
        return sActions[token][actionType][number];
    }

    /// Read just the state of an action.
    /// @param token The token address.
    /// @param actionType The type of corporate action.
    /// @param number The sequential number.
    /// @return The ActionState enum value.
    function getActionState(address token, bytes32 actionType, uint256 number) external view returns (ActionState) {
        _requireActionExists(token, actionType, number);
        return sActions[token][actionType][number].state;
    }

    /// Internal dispatch that routes the action to the appropriate function
    /// on the token contract. The token's authorizer will verify that this
    /// registry holds the required role.
    ///
    /// Adding new action types requires extending this function. This is
    /// intentionally not a generic delegatecall/proxy — each action type has
    /// explicit, auditable dispatch logic.
    /// @param token The token to dispatch to.
    /// @param actionType The action type being executed.
    /// @param number The action number.
    /// @param data The action-specific payload.
    function _dispatch(address token, bytes32 actionType, uint256 number, bytes memory data) internal {
        if (actionType == ACTION_TYPE_NAME_SYMBOL) {
            (string memory newName, string memory newSymbol) = abi.decode(data, (string, string));
            IStoxReceiptVaultV2(token).updateNameSymbol(actionType, number, newName, newSymbol);
        }
        // Future action types (SPLIT, REVERSE_SPLIT, etc.) will be added here
        // as new `else if` branches with their own dispatch logic.
    }

    /// Authorize the scheduling of a corporate action. The caller must hold
    /// the relevant permission in the token's authorizer for the action type
    /// being scheduled.
    /// @param token The token whose authorizer to check.
    /// @param actionType The action type.
    /// @param number The action number.
    /// @param data The action payload.
    /// @param effectiveTime The effective time.
    function _authorizeSchedule(
        address token,
        bytes32 actionType,
        uint256 number,
        bytes memory data,
        uint256 effectiveTime
    ) internal {
        // Map action types to their corresponding permissions.
        bytes32 permission;
        if (actionType == ACTION_TYPE_NAME_SYMBOL) {
            permission = UPDATE_NAME_SYMBOL;
        } else {
            // Unknown action types revert. This is intentionally strict —
            // the registry only supports known, audited action types.
            revert ActionDoesNotExist(token, actionType, number);
        }

        IAuthorizeV1 auth = IAuthorizerReader(token).authorizer();
        auth.authorize(
            msg.sender,
            permission,
            abi.encode(
                ScheduleStateChange({
                    token: token, actionType: actionType, number: number, data: data, effectiveTime: effectiveTime
                })
            )
        );
    }

    /// Revert if an action does not exist.
    function _requireActionExists(address token, bytes32 actionType, uint256 number) internal view {
        if (number == 0 || number > counters[token][actionType]) {
            revert ActionDoesNotExist(token, actionType, number);
        }
    }
}

/// @dev Minimal interface to read the authorizer from OffchainAssetReceiptVault.
/// Separated from IStoxReceiptVaultV2 to avoid Solidity inheritance conflicts
/// when StoxReceiptVault inherits both OffchainAssetReceiptVault and the interface.
interface IAuthorizerReader {
    function authorizer() external view returns (IAuthorizeV1);
}

/// @dev Interface for the st0x-specific functions that the registry dispatches to.
/// authorizer() is NOT included here because it's already declared on
/// OffchainAssetReceiptVault, and redeclaring it would cause Solidity to require
/// an explicit override in StoxReceiptVault.
interface IStoxReceiptVaultV2 {
    /// @notice Update the vault's name and symbol. Called by the registry
    /// during corporate action execution.
    /// @param actionType The corporate action type.
    /// @param number The action number.
    /// @param newName The new token name.
    /// @param newSymbol The new token symbol.
    function updateNameSymbol(bytes32 actionType, uint256 number, string memory newName, string memory newSymbol)
        external;
}
