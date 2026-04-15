# Glossary

Domain terms used throughout the st0x.deploy codebase.

| Term | Definition |
|------|-----------|
| **Action Index** | 1-based position of a corporate action node in the storage array. Stable once assigned (never reused). 0 means "none" (sentinel). |
| **Action Type** | Bitmap identifying what kind of corporate action a node represents. Each type occupies a single bit (`1 << n`). Currently only `ACTION_TYPE_STOCK_SPLIT = 1 << 0`. |
| **Authorizer** | External contract (`IAuthorizeV1`) that gates who can schedule or cancel corporate actions. Resolved from the vault's storage under delegatecall. |
| **Beacon Proxy** | `StoxWrappedTokenVault` instances are beacon proxies — they delegate to an implementation held by `StoxWrappedTokenVaultBeacon`. Upgrading the beacon replaces logic for all proxies simultaneously. |
| **Completion Filter** | Enum (`ALL`, `COMPLETED`, `PENDING`) used by traversal getters to select nodes based on whether their `effectiveTime` has passed. |
| **Corporate Action** | An event that affects all token holders simultaneously (e.g., stock split). Represented as a node in the linked list. |
| **Cursor** | A 1-based node index tracking how far through the linked list an account (or `(holder, id)` pair) has been migrated. 0 = never migrated. |
| **Diamond Facet** | `StoxCorporateActionsFacet` — a contract whose functions are delegatecalled by the vault, sharing the vault's storage and address while keeping logic modular. |
| **effectiveTime** | The `uint64` timestamp at which a corporate action takes effect. No stored status — completion is derived from `effectiveTime <= block.timestamp`. |
| **ERC-7201** | Namespaced storage standard. Each library uses a fixed slot derived from a human-readable namespace string (e.g., `rain.storage.corporate-action.1`), preventing storage collisions in upgradeable proxy contracts. |
| **Fold** | `LibTotalSupply.fold()` — bootstraps the per-cursor pot model from OZ's `_totalSupply` and advances the `totalSupplyLatestSplit` pointer. Called at the start of `_update`. |
| **Lazy Migration** | Account balances are not rewritten when a split takes effect. Instead, they are rasterized (migrated) on first interaction (transfer, mint, burn) via the `_update` hook. |
| **Linked List** | Doubly linked list of `CorporateActionNode`s ordered by `effectiveTime`. Index 0 is a sentinel. Head points to the earliest node, tail to the latest. |
| **Migration** | The process of rewriting a stored balance from its pre-rebase value to the post-rebase value and advancing the account's cursor. Covers balance rasterization + cursor advancement. |
| **Multiplier** | A Rain Float value representing the split ratio (e.g., 2.0 for a 2-for-1 split, 0.333... for a 1-for-3 reverse split). Stored as ABI-encoded `Float` in the node's `parameters` field. |
| **Per-cursor Pot** | `unmigrated[k]` — the sum of stored balances for all accounts whose migration cursor is at position `k`. Used by `LibTotalSupply` to compute `effectiveTotalSupply` without iterating all accounts. |
| **Pointer Files** | `src/generated/*.pointers.sol` — contain Zoltu deterministic deployment addresses and creation bytecodes. Regenerated when contract bytecode changes. |
| **Rain Float** | Floating-point type from `rain.math.float` used for multiplier representation. Finite precision — see the sequential precision discussion in `LibRebase.sol`. |
| **Rasterization** | Converting a stored balance to its effective (post-rebase) value by applying each pending multiplier sequentially with integer truncation between steps. Synonymous with "migration" at the per-account level. |
| **Receipt Vault** | `StoxReceiptVault` (`OffchainAssetReceiptVault` subclass) — the ERC-20 vault that issues fungible shares. Holds corporate action storage via ERC-7201. |
| **Receipt** | `StoxReceipt` — the ERC-1155 token representing proof of deposit. Each receipt id corresponds to a specific deposit. Rebases in lockstep with shares. |
| **Sentinel** | Node at index 0 in the linked list array. Never used for real data — exists so that `prev = 0` and `next = 0` unambiguously mean "no neighbor." |
| **Sequential Precision** | The design choice to truncate after each multiplier application rather than collapsing multipliers into a cumulative product. Ensures dormant and active accounts converge to identical balances. |
| **Type Hash** | External human-readable identifier for an action type (e.g., `keccak256("StockSplit")`). Mapped to the internal bitmap by `resolveActionType`. |
| **Wrapped Vault** | `StoxWrappedTokenVault` (ERC-4626) — wraps receipt vault shares, capturing rebase value changes in price rather than supply. |
| **Zoltu** | Deterministic deployment factory. Contracts with parameterless constructors get identical addresses across all EVM networks. |
