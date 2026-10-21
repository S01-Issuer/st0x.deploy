# Base launch audit scope

[RAI-3577](https://linear.app/makeitrain/issue/RAI-3577) ports the existing
sft-ops Base launch at `ee39d0d` without redesign. These compatibility rules
apply only to `LaunchBaseTokens` and its plan inputs. They do not apply to the
other deploy scripts or production fleet invariants.

- **Owner:** `cd-plan.ts::PRODUCTION_OWNER_SAFE` is
  `0xe70d821f3462a074e63b42d0AaC6523faAe1d611`. The issue requires that owner
  and explicitly excludes timelock handover. `planContext` therefore uses the
  Safe. The conflict with `docs/TIMELOCK.md` is a cutover decision for
  [RAI-3577](https://linear.app/makeitrain/issue/RAI-3577); it is not resolved
  by changing this compatibility port's owner.
- **Shipped symbols:** `cd-plan.ts::loadLedgerSymbols` reads the launch ledger,
  not `LibTokenInvariants`. The copied ledger omits live tFGI, so both planners
  plan it. The fixed snapshot test preserves this result. Inputs must be
  reconciled with sft-ops before cutover; adding fleet pins to the planner would
  change the requested skip rule.
- **Retired rows:** cd-plan relaunches a deprecated row unless
  `deprecated.retired === true`. `LibLaunchInputs` keeps the symbol shipped for
  any `retired` value other than `false`, `0` and `null` (for example `"true"`,
  `1` or `"false"`), so a mistyped flag skips the token instead of launching it
  twice. Relaunching such a row needs the flag removed or set to `false`.
- **Dedicated pin matching:** `dedicated-authorisers.ts::findDedicatedPin` uses
  the first case-insensitive match from `Object.keys(pins).find`.
  `LibLaunchPlan.findPin` preserves it. Rejecting ambiguous keys should be
  considered for both launchers together.
- **Signer trust:** the source launch retains the same signer's vault ownership
  and temporary-authoriser administration until handoff. The port preserves that
  trust model. Additional supply or role restrictions would change the source
  launch's acceptance rules and belong in the later design review, not silently
  in this port.

These notes do not waive tests of the compatibility rules. They do not authorize
production cutover, and sft-ops stays live until the team reviews the port.
