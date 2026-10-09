import { afterEach, assert, clearStore, describe, test } from "matchstick-as";
import { Address, Bytes } from "@graphprotocol/graph-ts";
import {
  RoleAdminChanged,
  RoleGranted,
  RoleRevoked,
} from "../generated/Authorizer/AccessControl";
// The timelock's `RoleGranted` is a different AssemblyScript class from the
// authoriser's even though the ABI is the same one — `graph codegen` emits a
// class per (data source, ABI) pair, and `changetype` between them is rejected.
import {
  RoleAdminChanged as TimelockRoleAdminChanged,
  RoleGranted as TimelockRoleGranted,
  RoleRevoked as TimelockRoleRevoked,
} from "../generated/GovernanceTimelock/AccessControl";
import {
  RoleAdminChanged as OrchestratorRoleAdminChanged,
  RoleGranted as OrchestratorRoleGranted,
  RoleRevoked as OrchestratorRoleRevoked,
} from "../generated/templates/Orchestrator/AccessControl";
import {
  RoleAdminChanged as EuRoleAdminChanged,
  RoleGranted as EuRoleGranted,
  RoleRevoked as EuRoleRevoked,
} from "../generated/EuAuthorizer/AccessControl";
import {
  handleAuthorizerRoleAdminChanged,
  handleAuthorizerRoleGranted,
  handleAuthorizerRoleRevoked,
} from "../src/authorizer";
import {
  handleEuAuthorizerRoleAdminChanged,
  handleEuAuthorizerRoleGranted,
  handleEuAuthorizerRoleRevoked,
} from "../src/euauthorizer";
import {
  handleTimelockRoleAdminChanged,
  handleTimelockRoleGranted,
  handleTimelockRoleRevoked,
} from "../src/timelock";
import {
  handleOrchestratorRoleAdminChanged,
  handleOrchestratorRoleGranted,
  handleOrchestratorRoleRevoked,
} from "../src/orchestrator";
import { roleHolderId, roleId } from "../src/lib/accesscontrol";
import {
  TX_FROM,
  TX_HASH,
  roleAdminChangedLog,
  roleChangeLog,
} from "./event-mocks.test";

const AUTHORIZER = "0x315b16faa6ee413fabca877d3851b3818369f0cd";
const TIMELOCK = "0x48ba1371a78e6cc54157c63721756ab444510db3";
const EU_AUTHORIZER = "0x8fc06579571a105c5a699fa11d95b9c73747f8eb";
const ORCHESTRATOR = "0x00000000000000000000000000000000000000c0";
const ALICE = "0x00000000000000000000000000000000000000a1";
const BOB = "0x00000000000000000000000000000000000000b0";
const CALLER = "0x00000000000000000000000000000000000000ca";
const DEFAULT_ADMIN_ROLE =
  "0x0000000000000000000000000000000000000000000000000000000000000000";
const MINT_ROLE =
  "0x1111111111111111111111111111111111111111111111111111111111111111";
const BURN_ROLE =
  "0x2222222222222222222222222222222222222222222222222222222222222222";

function grant(
  contract: string,
  role: string,
  account: string,
  blockNumber: i32,
  logIndex: i32,
): void {
  handleAuthorizerRoleGranted(
    changetype<RoleGranted>(
      roleChangeLog(
        Address.fromString(contract),
        Bytes.fromHexString(role),
        Address.fromString(account),
        Address.fromString(CALLER),
        blockNumber,
        logIndex,
      ),
    ),
  );
}

function revoke(
  contract: string,
  role: string,
  account: string,
  blockNumber: i32,
  logIndex: i32,
): void {
  handleAuthorizerRoleRevoked(
    changetype<RoleRevoked>(
      roleChangeLog(
        Address.fromString(contract),
        Bytes.fromHexString(role),
        Address.fromString(account),
        Address.fromString(CALLER),
        blockNumber,
        logIndex,
      ),
    ),
  );
}

function roleKey(contract: string, role: string): string {
  return roleId(
    Bytes.fromHexString(contract),
    Bytes.fromHexString(role),
  ).toHexString();
}

function holderKey(contract: string, role: string, account: string): string {
  return roleHolderId(
    Bytes.fromHexString(contract),
    Bytes.fromHexString(role),
    Bytes.fromHexString(account),
  ).toHexString();
}

function grantKey(logIndex: i32): string {
  return TX_HASH.concatI32(logIndex).toHexString();
}

describe("Role grants and revokes", () => {
  afterEach(clearStore);

  test("a grant creates the contract, role, holder and history rows", () => {
    grant(AUTHORIZER, MINT_ROLE, ALICE, 100, 3);

    assert.entityCount("Contract", 1);
    assert.entityCount("Role", 1);
    assert.entityCount("RoleHolder", 1);
    assert.entityCount("RoleGrant", 1);

    assert.fieldEquals("Contract", AUTHORIZER, "kind", "AUTHORIZER");
    assert.fieldEquals("Contract", AUTHORIZER, "firstIndexedBlock", "100");
    assert.fieldEquals("Contract", AUTHORIZER, "ownerFromLog", "false");
    assert.fieldEquals(
      "Contract",
      AUTHORIZER,
      "implementationFromLog",
      "false",
    );

    let role = roleKey(AUTHORIZER, MINT_ROLE);
    assert.fieldEquals("Role", role, "contract", AUTHORIZER);
    assert.fieldEquals("Role", role, "role", MINT_ROLE);
    assert.fieldEquals("Role", role, "holderCount", "1");
    // `_setRoleAdmin` emits nothing for the implicit initial admin, so a fresh
    // role has to read back as administered by `DEFAULT_ADMIN_ROLE`.
    assert.fieldEquals("Role", role, "admin", DEFAULT_ADMIN_ROLE);

    let holder = holderKey(AUTHORIZER, MINT_ROLE, ALICE);
    assert.fieldEquals("RoleHolder", holder, "role", role);
    assert.fieldEquals("RoleHolder", holder, "account", ALICE);
    assert.fieldEquals("RoleHolder", holder, "held", "true");
    assert.fieldEquals("RoleHolder", holder, "grantedAtBlock", "100");
    assert.fieldEquals("RoleHolder", holder, "grantedAtTimestamp", "1200");

    let row = grantKey(3);
    assert.fieldEquals("RoleGrant", row, "role", role);
    assert.fieldEquals("RoleGrant", row, "account", ALICE);
    assert.fieldEquals("RoleGrant", row, "granted", "true");
    // The event's own `sender` param, not the transaction submitter: a grant
    // routed through the timelock or a Safe has two different answers here.
    assert.fieldEquals("RoleGrant", row, "sender", CALLER);
    assert.fieldEquals(
      "RoleGrant",
      row,
      "transactionFrom",
      TX_FROM.toHexString(),
    );
    assert.fieldEquals(
      "RoleGrant",
      row,
      "transactionHash",
      TX_HASH.toHexString(),
    );
    assert.fieldEquals("RoleGrant", row, "blockNumber", "100");
    assert.fieldEquals("RoleGrant", row, "blockTimestamp", "1200");
    assert.fieldEquals("RoleGrant", row, "logIndex", "3");
  });

  test("replaying the same grant log leaves holderCount at one", () => {
    grant(AUTHORIZER, MINT_ROLE, ALICE, 100, 3);
    grant(AUTHORIZER, MINT_ROLE, ALICE, 100, 3);

    assert.entityCount("RoleHolder", 1);
    assert.entityCount("RoleGrant", 1);
    assert.fieldEquals(
      "Role",
      roleKey(AUTHORIZER, MINT_ROLE),
      "holderCount",
      "1",
    );
  });

  test("a second account raises holderCount to two", () => {
    grant(AUTHORIZER, MINT_ROLE, ALICE, 100, 3);
    grant(AUTHORIZER, MINT_ROLE, BOB, 100, 4);

    assert.entityCount("RoleHolder", 2);
    assert.entityCount("RoleGrant", 2);
    assert.fieldEquals(
      "Role",
      roleKey(AUTHORIZER, MINT_ROLE),
      "holderCount",
      "2",
    );
  });

  test("a revoke flips held, lowers holderCount and keeps the row", () => {
    grant(AUTHORIZER, MINT_ROLE, ALICE, 100, 3);
    revoke(AUTHORIZER, MINT_ROLE, ALICE, 200, 1);

    assert.entityCount("RoleHolder", 1);
    assert.entityCount("RoleGrant", 2);
    assert.fieldEquals(
      "Role",
      roleKey(AUTHORIZER, MINT_ROLE),
      "holderCount",
      "0",
    );

    let holder = holderKey(AUTHORIZER, MINT_ROLE, ALICE);
    assert.fieldEquals("RoleHolder", holder, "held", "false");
    assert.fieldEquals("RoleHolder", holder, "revokedAtBlock", "200");
    assert.fieldEquals("RoleHolder", holder, "revokedAtTimestamp", "2400");
    // The grant stamps survive the revoke: the pair's history is reachable
    // from the holder row as well as from `grantEvents`.
    assert.fieldEquals("RoleHolder", holder, "grantedAtBlock", "100");

    assert.fieldEquals("RoleGrant", grantKey(1), "granted", "false");
  });

  test("replaying a revoke log does not take holderCount below zero", () => {
    grant(AUTHORIZER, MINT_ROLE, ALICE, 100, 3);
    revoke(AUTHORIZER, MINT_ROLE, ALICE, 200, 1);
    revoke(AUTHORIZER, MINT_ROLE, ALICE, 200, 1);

    assert.fieldEquals(
      "Role",
      roleKey(AUTHORIZER, MINT_ROLE),
      "holderCount",
      "0",
    );
  });

  test("a re-grant after a revoke restores held and the count", () => {
    grant(AUTHORIZER, MINT_ROLE, ALICE, 100, 3);
    revoke(AUTHORIZER, MINT_ROLE, ALICE, 200, 1);
    grant(AUTHORIZER, MINT_ROLE, ALICE, 300, 2);

    let holder = holderKey(AUTHORIZER, MINT_ROLE, ALICE);
    assert.entityCount("RoleHolder", 1);
    assert.entityCount("RoleGrant", 3);
    assert.fieldEquals(
      "Role",
      roleKey(AUTHORIZER, MINT_ROLE),
      "holderCount",
      "1",
    );
    assert.fieldEquals("RoleHolder", holder, "held", "true");
    assert.fieldEquals("RoleHolder", holder, "grantedAtBlock", "300");
    assert.fieldEquals("RoleHolder", holder, "revokedAtBlock", "200");
  });

  test("two roles on one contract are counted separately", () => {
    grant(AUTHORIZER, MINT_ROLE, ALICE, 100, 3);
    grant(AUTHORIZER, BURN_ROLE, ALICE, 100, 4);

    assert.entityCount("Contract", 1);
    assert.entityCount("Role", 2);
    assert.entityCount("RoleHolder", 2);
    assert.fieldEquals(
      "Role",
      roleKey(AUTHORIZER, MINT_ROLE),
      "holderCount",
      "1",
    );
    assert.fieldEquals(
      "Role",
      roleKey(AUTHORIZER, BURN_ROLE),
      "holderCount",
      "1",
    );
  });

  test("the same role on two contracts is two rows", () => {
    grant(AUTHORIZER, MINT_ROLE, ALICE, 100, 3);
    handleTimelockRoleGranted(
      changetype<TimelockRoleGranted>(
        roleChangeLog(
          Address.fromString(TIMELOCK),
          Bytes.fromHexString(MINT_ROLE),
          Address.fromString(ALICE),
          Address.fromString(CALLER),
          100,
          4,
        ),
      ),
    );

    assert.entityCount("Contract", 2);
    assert.entityCount("Role", 2);
    assert.entityCount("RoleHolder", 2);
    assert.fieldEquals("Contract", AUTHORIZER, "kind", "AUTHORIZER");
    assert.fieldEquals("Contract", TIMELOCK, "kind", "GOVERNANCE_TIMELOCK");
    assert.fieldEquals(
      "Role",
      roleKey(TIMELOCK, MINT_ROLE),
      "contract",
      TIMELOCK,
    );
  });
});

describe("Role admin changes", () => {
  afterEach(clearStore);

  test("an admin change moves Role.admin and records the history row", () => {
    handleAuthorizerRoleAdminChanged(
      changetype<RoleAdminChanged>(
        roleAdminChangedLog(
          Address.fromString(AUTHORIZER),
          Bytes.fromHexString(MINT_ROLE),
          Bytes.fromHexString(DEFAULT_ADMIN_ROLE),
          Bytes.fromHexString(BURN_ROLE),
          100,
          2,
        ),
      ),
    );

    let role = roleKey(AUTHORIZER, MINT_ROLE);
    assert.entityCount("Role", 1);
    assert.entityCount("RoleAdminChange", 1);
    assert.fieldEquals("Role", role, "admin", BURN_ROLE);
    // The role exists because an event named it, with nobody holding it.
    assert.fieldEquals("Role", role, "holderCount", "0");

    let row = grantKey(2);
    assert.fieldEquals("RoleAdminChange", row, "role", role);
    assert.fieldEquals(
      "RoleAdminChange",
      row,
      "previousAdminRole",
      DEFAULT_ADMIN_ROLE,
    );
    assert.fieldEquals("RoleAdminChange", row, "newAdminRole", BURN_ROLE);
    assert.fieldEquals("RoleAdminChange", row, "blockNumber", "100");
    assert.fieldEquals("RoleAdminChange", row, "blockTimestamp", "1200");
    assert.fieldEquals(
      "RoleAdminChange",
      row,
      "transactionFrom",
      TX_FROM.toHexString(),
    );
    assert.fieldEquals("RoleAdminChange", row, "logIndex", "2");
  });

  test("an admin change leaves the role's holders alone", () => {
    grant(AUTHORIZER, MINT_ROLE, ALICE, 100, 3);
    handleAuthorizerRoleAdminChanged(
      changetype<RoleAdminChanged>(
        roleAdminChangedLog(
          Address.fromString(AUTHORIZER),
          Bytes.fromHexString(MINT_ROLE),
          Bytes.fromHexString(DEFAULT_ADMIN_ROLE),
          Bytes.fromHexString(BURN_ROLE),
          200,
          1,
        ),
      ),
    );

    let role = roleKey(AUTHORIZER, MINT_ROLE);
    assert.fieldEquals("Role", role, "admin", BURN_ROLE);
    assert.fieldEquals("Role", role, "holderCount", "1");
    assert.fieldEquals(
      "RoleHolder",
      holderKey(AUTHORIZER, MINT_ROLE, ALICE),
      "held",
      "true",
    );
  });
});

describe("EU authoriser", () => {
  afterEach(clearStore);

  test("a grant then a revoke flips held and holderCount", () => {
    handleEuAuthorizerRoleGranted(
      changetype<EuRoleGranted>(
        roleChangeLog(
          Address.fromString(EU_AUTHORIZER),
          Bytes.fromHexString(MINT_ROLE),
          Address.fromString(ALICE),
          Address.fromString(CALLER),
          100,
          1,
        ),
      ),
    );

    let role = roleKey(EU_AUTHORIZER, MINT_ROLE);
    let holder = holderKey(EU_AUTHORIZER, MINT_ROLE, ALICE);
    assert.fieldEquals("Contract", EU_AUTHORIZER, "kind", "AUTHORIZER");
    assert.fieldEquals("Role", role, "holderCount", "1");
    assert.fieldEquals("RoleHolder", holder, "held", "true");
    assert.fieldEquals("RoleGrant", grantKey(1), "granted", "true");

    handleEuAuthorizerRoleRevoked(
      changetype<EuRoleRevoked>(
        roleChangeLog(
          Address.fromString(EU_AUTHORIZER),
          Bytes.fromHexString(MINT_ROLE),
          Address.fromString(ALICE),
          Address.fromString(CALLER),
          200,
          2,
        ),
      ),
    );

    assert.fieldEquals("Role", role, "holderCount", "0");
    assert.fieldEquals("RoleHolder", holder, "held", "false");
    assert.fieldEquals("RoleGrant", grantKey(1), "granted", "true");
    assert.fieldEquals("RoleGrant", grantKey(2), "granted", "false");
  });

  test("the EU authoriser is a row of its own alongside the USA one", () => {
    grant(AUTHORIZER, MINT_ROLE, ALICE, 100, 1);
    handleEuAuthorizerRoleGranted(
      changetype<EuRoleGranted>(
        roleChangeLog(
          Address.fromString(EU_AUTHORIZER),
          Bytes.fromHexString(MINT_ROLE),
          Address.fromString(ALICE),
          Address.fromString(CALLER),
          100,
          2,
        ),
      ),
    );

    assert.entityCount("Contract", 2);
    assert.entityCount("Role", 2);
    assert.entityCount("RoleHolder", 2);
    assert.fieldEquals("Contract", AUTHORIZER, "kind", "AUTHORIZER");
    assert.fieldEquals("Contract", EU_AUTHORIZER, "kind", "AUTHORIZER");
    assert.fieldEquals(
      "Role",
      roleKey(EU_AUTHORIZER, MINT_ROLE),
      "contract",
      EU_AUTHORIZER,
    );
  });

  test("an admin change moves Role.admin on the EU authoriser", () => {
    handleEuAuthorizerRoleAdminChanged(
      changetype<EuRoleAdminChanged>(
        roleAdminChangedLog(
          Address.fromString(EU_AUTHORIZER),
          Bytes.fromHexString(MINT_ROLE),
          Bytes.fromHexString(DEFAULT_ADMIN_ROLE),
          Bytes.fromHexString(BURN_ROLE),
          100,
          2,
        ),
      ),
    );

    let role = roleKey(EU_AUTHORIZER, MINT_ROLE);
    assert.fieldEquals("Contract", EU_AUTHORIZER, "kind", "AUTHORIZER");
    assert.fieldEquals("Role", role, "admin", BURN_ROLE);
    assert.fieldEquals("RoleAdminChange", grantKey(2), "role", role);
  });
});

describe("Orchestrator role events", () => {
  afterEach(clearStore);

  test("a grant then a revoke flips held and holderCount", () => {
    handleOrchestratorRoleGranted(
      changetype<OrchestratorRoleGranted>(
        roleChangeLog(
          Address.fromString(ORCHESTRATOR),
          Bytes.fromHexString(MINT_ROLE),
          Address.fromString(ALICE),
          Address.fromString(CALLER),
          100,
          1,
        ),
      ),
    );

    let role = roleKey(ORCHESTRATOR, MINT_ROLE);
    let holder = holderKey(ORCHESTRATOR, MINT_ROLE, ALICE);
    assert.fieldEquals("Contract", ORCHESTRATOR, "kind", "ORCHESTRATOR");
    assert.fieldEquals("Role", role, "holderCount", "1");
    assert.fieldEquals("RoleHolder", holder, "held", "true");
    assert.fieldEquals("RoleGrant", grantKey(1), "granted", "true");

    handleOrchestratorRoleRevoked(
      changetype<OrchestratorRoleRevoked>(
        roleChangeLog(
          Address.fromString(ORCHESTRATOR),
          Bytes.fromHexString(MINT_ROLE),
          Address.fromString(ALICE),
          Address.fromString(CALLER),
          200,
          2,
        ),
      ),
    );

    assert.fieldEquals("Role", role, "holderCount", "0");
    assert.fieldEquals("RoleHolder", holder, "held", "false");
    assert.fieldEquals("RoleGrant", grantKey(1), "granted", "true");
    assert.fieldEquals("RoleGrant", grantKey(2), "granted", "false");
  });

  test("an admin change moves Role.admin without adding a holder", () => {
    handleOrchestratorRoleAdminChanged(
      changetype<OrchestratorRoleAdminChanged>(
        roleAdminChangedLog(
          Address.fromString(ORCHESTRATOR),
          Bytes.fromHexString(MINT_ROLE),
          Bytes.fromHexString(DEFAULT_ADMIN_ROLE),
          Bytes.fromHexString(BURN_ROLE),
          100,
          2,
        ),
      ),
    );

    let role = roleKey(ORCHESTRATOR, MINT_ROLE);
    assert.fieldEquals("Contract", ORCHESTRATOR, "kind", "ORCHESTRATOR");
    assert.fieldEquals("Role", role, "admin", BURN_ROLE);
    assert.fieldEquals("Role", role, "holderCount", "0");
    assert.fieldEquals("RoleAdminChange", grantKey(2), "role", role);
  });
});

describe("Timelock role events", () => {
  afterEach(clearStore);

  test("a revoke flips held and holderCount on the timelock", () => {
    handleTimelockRoleGranted(
      changetype<TimelockRoleGranted>(
        roleChangeLog(
          Address.fromString(TIMELOCK),
          Bytes.fromHexString(MINT_ROLE),
          Address.fromString(ALICE),
          Address.fromString(CALLER),
          100,
          1,
        ),
      ),
    );

    let role = roleKey(TIMELOCK, MINT_ROLE);
    let holder = holderKey(TIMELOCK, MINT_ROLE, ALICE);
    assert.fieldEquals("Contract", TIMELOCK, "kind", "GOVERNANCE_TIMELOCK");
    assert.fieldEquals("Role", role, "holderCount", "1");
    assert.fieldEquals("RoleGrant", grantKey(1), "granted", "true");

    handleTimelockRoleRevoked(
      changetype<TimelockRoleRevoked>(
        roleChangeLog(
          Address.fromString(TIMELOCK),
          Bytes.fromHexString(MINT_ROLE),
          Address.fromString(ALICE),
          Address.fromString(CALLER),
          200,
          2,
        ),
      ),
    );

    assert.fieldEquals("Role", role, "holderCount", "0");
    assert.fieldEquals("RoleHolder", holder, "held", "false");
    assert.fieldEquals("RoleGrant", grantKey(2), "granted", "false");
  });

  test("an admin change moves Role.admin on the timelock", () => {
    handleTimelockRoleAdminChanged(
      changetype<TimelockRoleAdminChanged>(
        roleAdminChangedLog(
          Address.fromString(TIMELOCK),
          Bytes.fromHexString(MINT_ROLE),
          Bytes.fromHexString(DEFAULT_ADMIN_ROLE),
          Bytes.fromHexString(BURN_ROLE),
          100,
          2,
        ),
      ),
    );

    let role = roleKey(TIMELOCK, MINT_ROLE);
    assert.fieldEquals("Contract", TIMELOCK, "kind", "GOVERNANCE_TIMELOCK");
    assert.fieldEquals("Role", role, "admin", BURN_ROLE);
    assert.fieldEquals("RoleAdminChange", grantKey(2), "role", role);
  });
});
