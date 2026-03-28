# Mint Recipient Whitelist Security Enhancement

## Overview

Enhance security by restricting mints to a whitelist of approved recipient addresses, preventing compromised mint keys from directly minting to attacker-controlled addresses.

## Security Model

### Two-Key Requirement
- **Hot wallet**: Can mint to whitelisted addresses (core bridge server)
- **Whitelisted recipients**: Can receive mints (market makers, authorized addresses)
- **Critical constraint**: Address with mint permission CANNOT be on recipient whitelist

### Attack Vector Mitigation
**Current risk**: Compromised mint key → mint to self → transfer anywhere
**New model**: Compromised mint key → can only mint to whitelisted recipients → attacker must ALSO compromise a market maker

## Technical Implementation

### Authorizer Enhancement
```solidity
// New permission types
bytes32 constant MINT_RECIPIENT = keccak256("MINT_RECIPIENT");
bytes32 constant UPDATE_MINT_RECIPIENTS = keccak256("UPDATE_MINT_RECIPIENTS");

// Constraint enforcement
function checkMintRecipient(address minter, address recipient) external view {
    require(hasRole(MINT_RECIPIENT, recipient), "Recipient not whitelisted");
    require(!hasRole(MINT, minter) || !hasRole(MINT_RECIPIENT, minter), "Minter cannot be recipient");
}
```

### Governance Controls
- **Whitelist changes**: Require timelock + multisig approval
- **Mint operations**: No timelock required (hot wallet operations)
- **Role separation**: Enforce mutual exclusion between MINT and MINT_RECIPIENT roles

## Implementation Approach

### Integration Points
- **Vault minting**: Check recipient whitelist before mint execution
- **Authorizer validation**: Enforce role separation constraints
- **Timelock coordination**: Whitelist updates via governance process

### Operational Flow
1. **Setup**: Configure initial whitelist of market makers
2. **Runtime**: Hot wallet mints to whitelisted addresses only
3. **Updates**: Governance can add/remove recipients via timelock
4. **Security**: Compromise of single key insufficient for full control

## Benefits

- **Defense in depth**: Two-key security model
- **Operational efficiency**: Hot wallet for normal operations
- **Controlled expansion**: Governance controls recipient list
- **Clear separation**: Mint permission and recipient permission mutually exclusive

## Future Considerations

- **Rate limiting**: Daily mint throttles (separate spec)
- **Multi-recipient batch mints**: Efficiency for multiple market makers
- **Emergency procedures**: Incident response for compromised keys
- **Monitoring**: Alerts for unusual mint patterns