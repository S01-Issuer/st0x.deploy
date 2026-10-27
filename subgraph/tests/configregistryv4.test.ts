import {
  afterEach,
  assert,
  clearStore,
  createMockedFunction,
  describe,
  test,
} from "matchstick-as";
import { Address, BigInt, Bytes, ethereum } from "@graphprotocol/graph-ts";
import {
  ConfigBinding,
  ConfigRegister,
  RegistryMeta,
} from "../generated/schema";
import { Register } from "../generated/ConfigRegistry/ConfigRegistry";
import {
  Approved,
  MetaV1_2,
  Register as RegisterV4,
  Revoked,
} from "../generated/ConfigRegistryV4/ConfigRegistryV4";
import {
  handleConfigRegistryRegister,
  handleConfigRegistryV4Approved,
  handleConfigRegistryV4MetaV1_2,
  handleConfigRegistryV4Register,
  handleConfigRegistryV4Revoked,
} from "../src/configregistry";
import {
  delegateChangeLog,
  inTx,
  metaV1_2Log,
  mockRowId,
  registerLog,
  registerV4Log,
  TX_FROM,
  TX_HASH,
} from "./event-mocks.test";

const REGISTRY = "0xdc3909127e51dcb3ab7d43eee585dd351f77c285";
const REGISTRY_V3 = "0x2f1f82c65cce305df3950f8af8fa5ad6d9a815e8";
/** st0x `LibStoxMigrations.WRITER`, the root authority. */
const AUTHORITY = "0x0b300013cd54a8f1ac40981f80faaa18b8cc1e4c";
const DELEGATE = "0x00000000000000000000000000000000000000d1";
/** `keccak256("st0x.rbac.us.v1")`, from `cast keccak`. */
const US_NAME =
  "0xb046f6b844b680f0dcfc7a139f126e7e13d58023f8d26c15e3229eb4fff8499f";
/** `keccak256("st0x.rbac.eu.v1")`, from `cast keccak`. */
const EU_NAME =
  "0x560e679773d4bf1a3dee3d913c31185111a3bcc57b6d93366936fc3526985ad5";
/** `keccak256(abi.encode(AUTHORITY, US_NAME))`, from `cast keccak $(cast abi-encode "f(address,bytes32)" …)`. */
const US_SUBJECT =
  "0x912e9df27c27e1655d672dbb02f4a3b59883479b9595a4522ca493312e2cdd89";
/** `keccak256("address")`, from `cast keccak`. */
const ADDRESS_HASH =
  "0x421683f821a0574472445355be6d2b769119e8515f8376a1d7878523dfdecf7b";
/** `keccak256("(address,uint256)")`, from `cast keccak`. */
const TUPLE_HASH =
  "0x4c8216942579564ee54f26005a991364c7f94438571b448bf6d3278d139e0fdf";
const VALUE_A =
  "0x0000000000000000000000000000000000000000000000000000000000000a01";
const VALUE_B =
  "0x0000000000000000000000000000000000000000000000000000000000000b02000000000000000000000000000000000000000000000000000000000000000c";
/** An empty rain meta document: just the `RainMetaDocumentV1` magic. */
const META = "0xff0a89c674ee7874";
const OTHER_TX =
  "0xdeadbeef00000000000000000000000000000000000000000000000000000002";

function bindingId(registry: string, authority: string, name: string): string {
  return registry.concat(authority.slice(2)).concat(name.slice(2));
}

function delegateId(
  registry: string,
  account: string,
  scope: string,
  delegate: string,
): string {
  return registry
    .concat(account.slice(2))
    .concat(scope.slice(2))
    .concat(delegate.slice(2));
}

/** `mockRowId` for a log in `tx` rather than `TX_HASH`. */
function rowIdIn(tx: string, logIndex: i32): string {
  let low = logIndex.toString(16);
  if (low.length < 2) {
    low = "0".concat(low);
  }
  return tx.concat(low).concat("000000");
}

/** What `getV4(authority, name)` answers. */
function mockGetV4(
  authority: string,
  name: string,
  value: string,
  typeHash: string,
): void {
  createMockedFunction(
    Address.fromString(REGISTRY),
    "getV4",
    "getV4(address,bytes32):(bytes,uint256,bytes32)",
  )
    .withArgs([
      ethereum.Value.fromAddress(Address.fromString(authority)),
      ethereum.Value.fromFixedBytes(Bytes.fromHexString(name)),
    ])
    .returns([
      ethereum.Value.fromBytes(Bytes.fromHexString(value)),
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(1200)),
      ethereum.Value.fromFixedBytes(Bytes.fromHexString(typeHash)),
    ]);
}

function mockGetV4Reverts(authority: string, name: string): void {
  createMockedFunction(
    Address.fromString(REGISTRY),
    "getV4",
    "getV4(address,bytes32):(bytes,uint256,bytes32)",
  )
    .withArgs([
      ethereum.Value.fromAddress(Address.fromString(authority)),
      ethereum.Value.fromFixedBytes(Bytes.fromHexString(name)),
    ])
    .reverts();
}

function registerEvent(
  sender: string,
  name: string,
  valueType: string,
  value: string,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  return registerV4Log(
    Address.fromString(REGISTRY),
    Address.fromString(sender),
    Address.fromString(AUTHORITY),
    Bytes.fromHexString(name),
    valueType,
    Bytes.fromHexString(value),
    blockNumber,
    logIndex,
  );
}

function register(
  sender: string,
  name: string,
  valueType: string,
  value: string,
  blockNumber: i32,
  logIndex: i32,
): void {
  handleConfigRegistryV4Register(
    changetype<RegisterV4>(
      registerEvent(sender, name, valueType, value, blockNumber, logIndex),
    ),
  );
}

function metaEvent(
  subject: string,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  return metaV1_2Log(
    Address.fromString(REGISTRY),
    Address.fromString(DELEGATE),
    Bytes.fromHexString(subject),
    Bytes.fromHexString(META),
    blockNumber,
    logIndex,
  );
}

function meta(subject: string, blockNumber: i32, logIndex: i32): void {
  handleConfigRegistryV4MetaV1_2(
    changetype<MetaV1_2>(metaEvent(subject, blockNumber, logIndex)),
  );
}

describe("ConfigRegistryV4 Register", () => {
  afterEach(clearStore);

  test("a first Register binds the value, its type and the type hash getV4 answers", () => {
    mockGetV4(AUTHORITY, US_NAME, VALUE_A, ADDRESS_HASH);
    register(DELEGATE, US_NAME, "address", VALUE_A, 100, 3);

    let id = bindingId(REGISTRY, AUTHORITY, US_NAME);
    assert.entityCount("ConfigBinding", 1);
    assert.fieldEquals("ConfigBinding", id, "registry", REGISTRY);
    assert.fieldEquals("ConfigBinding", id, "authority", AUTHORITY);
    assert.fieldEquals("ConfigBinding", id, "name", US_NAME);
    assert.fieldEquals("ConfigBinding", id, "value", VALUE_A);
    assert.fieldEquals("ConfigBinding", id, "valueType", "address");
    assert.fieldEquals("ConfigBinding", id, "valueTypeHash", ADDRESS_HASH);
    assert.fieldEquals("ConfigBinding", id, "sender", DELEGATE);
    assert.fieldEquals("ConfigBinding", id, "boundAtBlock", "100");
    assert.fieldEquals("ConfigBinding", id, "boundAtTimestamp", "1200");
    assert.fieldEquals("ConfigBinding", id, "registerCount", "1");
    assert.fieldEquals("ConfigBinding", id, "metaSubject", US_SUBJECT);

    let row = mockRowId(3);
    assert.entityCount("ConfigRegister", 1);
    assert.fieldEquals("ConfigRegister", row, "binding", id);
    assert.fieldEquals("ConfigRegister", row, "sender", DELEGATE);
    assert.fieldEquals("ConfigRegister", row, "value", VALUE_A);
    assert.fieldEquals("ConfigRegister", row, "valueType", "address");
    assert.fieldEquals("ConfigRegister", row, "valueTypeHash", ADDRESS_HASH);
    assert.fieldEquals("ConfigRegister", row, "blockNumber", "100");
    assert.fieldEquals(
      "ConfigRegister",
      row,
      "transactionHash",
      TX_HASH.toHexString(),
    );
    assert.fieldEquals(
      "ConfigRegister",
      row,
      "transactionFrom",
      TX_FROM.toHexString(),
    );
    assert.fieldEquals("ConfigRegister", row, "logIndex", "3");

    assert.fieldEquals("Contract", REGISTRY, "kind", "CONFIG_REGISTRY_V4");
    assert.fieldEquals("Contract", REGISTRY, "firstIndexedBlock", "100");
  });

  test("the type hash is the registry's answer, not a hash of the decoded string", () => {
    mockGetV4(AUTHORITY, US_NAME, VALUE_A, TUPLE_HASH);
    register(AUTHORITY, US_NAME, "address", VALUE_A, 100, 3);

    let id = bindingId(REGISTRY, AUTHORITY, US_NAME);
    assert.fieldEquals("ConfigBinding", id, "valueTypeHash", TUPLE_HASH);
    assert.fieldEquals(
      "ConfigRegister",
      mockRowId(3),
      "valueTypeHash",
      TUPLE_HASH,
    );
  });

  test("a getV4 that reverts leaves the type hash unknown and still binds", () => {
    mockGetV4Reverts(AUTHORITY, US_NAME);
    register(AUTHORITY, US_NAME, "address", VALUE_A, 100, 3);

    let id = bindingId(REGISTRY, AUTHORITY, US_NAME);
    let binding = ConfigBinding.load(Bytes.fromHexString(id))!;
    assert.assertTrue(binding.valueTypeHash === null);
    assert.fieldEquals("ConfigBinding", id, "valueType", "address");
    let row = ConfigRegister.load(Bytes.fromHexString(mockRowId(3)))!;
    assert.assertTrue(row.valueTypeHash === null);
  });

  test("a rebind as another type moves the type and keeps each row's own", () => {
    mockGetV4(AUTHORITY, US_NAME, VALUE_A, ADDRESS_HASH);
    register(AUTHORITY, US_NAME, "address", VALUE_A, 100, 3);
    mockGetV4(AUTHORITY, US_NAME, VALUE_B, TUPLE_HASH);
    register(DELEGATE, US_NAME, "(address,uint256)", VALUE_B, 250, 1);

    let id = bindingId(REGISTRY, AUTHORITY, US_NAME);
    assert.entityCount("ConfigBinding", 1);
    assert.fieldEquals("ConfigBinding", id, "value", VALUE_B);
    assert.fieldEquals("ConfigBinding", id, "valueType", "(address,uint256)");
    assert.fieldEquals("ConfigBinding", id, "valueTypeHash", TUPLE_HASH);
    assert.fieldEquals("ConfigBinding", id, "sender", DELEGATE);
    assert.fieldEquals("ConfigBinding", id, "boundAtBlock", "250");
    assert.fieldEquals("ConfigBinding", id, "registerCount", "2");

    assert.entityCount("ConfigRegister", 2);
    assert.fieldEquals("ConfigRegister", mockRowId(3), "valueType", "address");
    assert.fieldEquals(
      "ConfigRegister",
      mockRowId(3),
      "valueTypeHash",
      ADDRESS_HASH,
    );
    assert.fieldEquals(
      "ConfigRegister",
      mockRowId(1),
      "valueType",
      "(address,uint256)",
    );
    assert.fieldEquals(
      "ConfigRegister",
      mockRowId(1),
      "valueTypeHash",
      TUPLE_HASH,
    );
  });

  test("a replayed Register neither counts again nor rolls the type back", () => {
    mockGetV4(AUTHORITY, US_NAME, VALUE_A, ADDRESS_HASH);
    register(AUTHORITY, US_NAME, "address", VALUE_A, 100, 3);
    mockGetV4(AUTHORITY, US_NAME, VALUE_B, TUPLE_HASH);
    register(AUTHORITY, US_NAME, "(address,uint256)", VALUE_B, 250, 1);
    mockGetV4(AUTHORITY, US_NAME, VALUE_A, ADDRESS_HASH);
    register(AUTHORITY, US_NAME, "address", VALUE_A, 100, 3);

    let id = bindingId(REGISTRY, AUTHORITY, US_NAME);
    assert.fieldEquals("ConfigBinding", id, "valueType", "(address,uint256)");
    assert.fieldEquals("ConfigBinding", id, "valueTypeHash", TUPLE_HASH);
    assert.fieldEquals("ConfigBinding", id, "registerCount", "2");
    assert.entityCount("ConfigRegister", 2);
  });

  test("a V3 and a V4 binding of one name are separate rows, the V3 one untyped", () => {
    handleConfigRegistryRegister(
      changetype<Register>(
        registerLog(
          Address.fromString(REGISTRY_V3),
          Address.fromString(AUTHORITY),
          Address.fromString(AUTHORITY),
          Bytes.fromHexString(US_NAME),
          Bytes.fromHexString(VALUE_B),
          90,
          0,
        ),
      ),
    );
    mockGetV4(AUTHORITY, US_NAME, VALUE_A, ADDRESS_HASH);
    register(AUTHORITY, US_NAME, "address", VALUE_A, 100, 3);

    assert.entityCount("ConfigBinding", 2);
    assert.entityCount("Contract", 2);
    assert.fieldEquals("Contract", REGISTRY_V3, "kind", "CONFIG_REGISTRY");
    assert.fieldEquals("Contract", REGISTRY, "kind", "CONFIG_REGISTRY_V4");
    let v3 = ConfigBinding.load(
      Bytes.fromHexString(bindingId(REGISTRY_V3, AUTHORITY, US_NAME)),
    )!;
    assert.bytesEquals(v3.value, Bytes.fromHexString(VALUE_B));
    assert.assertTrue(v3.valueType === null);
    assert.assertTrue(v3.valueTypeHash === null);
    assert.assertTrue(v3.metaSubject === null);
    let v3Row = ConfigRegister.load(Bytes.fromHexString(mockRowId(0)))!;
    assert.assertTrue(v3Row.valueType === null);
    assert.assertTrue(v3Row.valueTypeHash === null);
    assert.fieldEquals(
      "ConfigBinding",
      bindingId(REGISTRY, AUTHORITY, US_NAME),
      "value",
      VALUE_A,
    );
  });
});

describe("ConfigRegistryV4 MetaV1_2", () => {
  afterEach(clearStore);

  test("a bind's meta links to its binding and its Register, raw and unverified", () => {
    mockGetV4(AUTHORITY, US_NAME, VALUE_A, ADDRESS_HASH);
    register(DELEGATE, US_NAME, "address", VALUE_A, 100, 3);
    meta(US_SUBJECT, 100, 4);

    let row = mockRowId(4);
    assert.entityCount("RegistryMeta", 1);
    assert.fieldEquals("RegistryMeta", row, "registry", REGISTRY);
    assert.fieldEquals("RegistryMeta", row, "sender", DELEGATE);
    assert.fieldEquals("RegistryMeta", row, "subject", US_SUBJECT);
    assert.fieldEquals("RegistryMeta", row, "meta", META);
    assert.fieldEquals(
      "RegistryMeta",
      row,
      "configBinding",
      bindingId(REGISTRY, AUTHORITY, US_NAME),
    );
    assert.fieldEquals("RegistryMeta", row, "configRegister", mockRowId(3));
    assert.fieldEquals("RegistryMeta", row, "verified", "false");
    assert.fieldEquals("RegistryMeta", row, "blockNumber", "100");
    assert.fieldEquals("RegistryMeta", row, "blockTimestamp", "1200");
    assert.fieldEquals(
      "RegistryMeta",
      row,
      "transactionHash",
      TX_HASH.toHexString(),
    );
    assert.fieldEquals(
      "RegistryMeta",
      row,
      "transactionFrom",
      TX_FROM.toHexString(),
    );
    assert.fieldEquals("RegistryMeta", row, "logIndex", "4");
    let entity = RegistryMeta.load(Bytes.fromHexString(row))!;
    assert.assertTrue(entity.migrationRecord === null);
  });

  test("a rebind's meta links to the rebind's Register, not the first", () => {
    mockGetV4(AUTHORITY, US_NAME, VALUE_A, ADDRESS_HASH);
    register(AUTHORITY, US_NAME, "address", VALUE_A, 100, 3);
    meta(US_SUBJECT, 100, 4);
    mockGetV4(AUTHORITY, US_NAME, VALUE_B, TUPLE_HASH);
    handleConfigRegistryV4Register(
      changetype<RegisterV4>(
        inTx(
          registerEvent(
            AUTHORITY,
            US_NAME,
            "(address,uint256)",
            VALUE_B,
            250,
            1,
          ),
          Bytes.fromHexString(OTHER_TX),
        ),
      ),
    );
    handleConfigRegistryV4MetaV1_2(
      changetype<MetaV1_2>(
        inTx(metaEvent(US_SUBJECT, 250, 2), Bytes.fromHexString(OTHER_TX)),
      ),
    );

    let second = rowIdIn(OTHER_TX, 2);
    assert.entityCount("RegistryMeta", 2);
    assert.fieldEquals(
      "RegistryMeta",
      second,
      "configRegister",
      rowIdIn(OTHER_TX, 1),
    );
    assert.fieldEquals(
      "RegistryMeta",
      mockRowId(4),
      "configRegister",
      mockRowId(3),
    );
    assert.fieldEquals(
      "RegistryMeta",
      second,
      "configBinding",
      bindingId(REGISTRY, AUTHORITY, US_NAME),
    );
  });

  test("a meta outside its binding's latest Register transaction links the binding only", () => {
    mockGetV4(AUTHORITY, US_NAME, VALUE_A, ADDRESS_HASH);
    register(AUTHORITY, US_NAME, "address", VALUE_A, 100, 3);
    handleConfigRegistryV4MetaV1_2(
      changetype<MetaV1_2>(
        inTx(metaEvent(US_SUBJECT, 300, 0), Bytes.fromHexString(OTHER_TX)),
      ),
    );

    let row = rowIdIn(OTHER_TX, 0);
    assert.fieldEquals(
      "RegistryMeta",
      row,
      "configBinding",
      bindingId(REGISTRY, AUTHORITY, US_NAME),
    );
    let entity = RegistryMeta.load(Bytes.fromHexString(row))!;
    assert.assertTrue(entity.configRegister === null);
  });

  test("a meta whose subject no Register has is kept, unlinked", () => {
    meta(EU_NAME, 100, 4);

    let entity = RegistryMeta.load(Bytes.fromHexString(mockRowId(4)))!;
    assert.assertTrue(entity.configBinding === null);
    assert.assertTrue(entity.configRegister === null);
    assert.assertTrue(entity.migrationRecord === null);
    assert.fieldEquals("RegistryMeta", mockRowId(4), "meta", META);
    assert.fieldEquals("Contract", REGISTRY, "kind", "CONFIG_REGISTRY_V4");
  });

  test("a replayed meta writes one row", () => {
    mockGetV4(AUTHORITY, US_NAME, VALUE_A, ADDRESS_HASH);
    register(AUTHORITY, US_NAME, "address", VALUE_A, 100, 3);
    meta(US_SUBJECT, 100, 4);
    meta(US_SUBJECT, 100, 4);

    assert.entityCount("RegistryMeta", 1);
  });
});

describe("ConfigRegistryV4 delegates", () => {
  afterEach(clearStore);

  test("Approved then Revoked move an approval under the V4 registry", () => {
    handleConfigRegistryV4Approved(
      changetype<Approved>(
        delegateChangeLog(
          Address.fromString(REGISTRY),
          Address.fromString(AUTHORITY),
          Bytes.fromHexString(US_NAME),
          Address.fromString(DELEGATE),
          300,
          4,
        ),
      ),
    );
    let id = delegateId(REGISTRY, AUTHORITY, US_NAME, DELEGATE);
    assert.fieldEquals("RegistryDelegate", id, "approved", "true");
    assert.fieldEquals("RegistryDelegate", id, "registry", REGISTRY);
    assert.fieldEquals("Contract", REGISTRY, "kind", "CONFIG_REGISTRY_V4");

    handleConfigRegistryV4Revoked(
      changetype<Revoked>(
        delegateChangeLog(
          Address.fromString(REGISTRY),
          Address.fromString(AUTHORITY),
          Bytes.fromHexString(US_NAME),
          Address.fromString(DELEGATE),
          400,
          2,
        ),
      ),
    );
    assert.fieldEquals("RegistryDelegate", id, "approved", "false");
    assert.fieldEquals("RegistryDelegate", id, "approvedAtBlock", "300");
    assert.fieldEquals("RegistryDelegate", id, "revokedAtBlock", "400");
    assert.entityCount("RegistryDelegateChange", 2);
  });
});
