import { afterEach, assert, clearStore, describe, test } from "matchstick-as";
import { Address, Bytes, ethereum } from "@graphprotocol/graph-ts";
import {
  ConfigBinding,
  ConfigRegister,
  RegistryMeta,
} from "../generated/schema";
import { Register } from "../generated/ConfigRegistry/ConfigRegistry";
import {
  Approved,
  ApprovedUnscoped,
  MetaV1_2,
  Register as RegisterV5,
  Revoked,
  RevokedUnscoped,
} from "../generated/ConfigRegistryV5/ConfigRegistryV5";
import {
  handleConfigRegistryRegister,
  handleConfigRegistryV5Approved,
  handleConfigRegistryV5ApprovedUnscoped,
  handleConfigRegistryV5MetaV1_2,
  handleConfigRegistryV5Register,
  handleConfigRegistryV5Revoked,
  handleConfigRegistryV5RevokedUnscoped,
} from "../src/configregistry";
import {
  delegateChangeLog,
  inTx,
  metaV1_2Log,
  mockRowId,
  registerLog,
  registerV5Log,
  TX_FROM,
  TX_HASH,
  unscopedDelegateChangeLog,
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
/*
 * Rain meta documents from `RainMetaDocumentV1Item::cbor_encode_seq` (rain.metadata),
 * items: config name, value type, unless named otherwise.
 */
const P = "0xff0a89c674ee7874";
const NAME_US = "a2004f737430782e726261632e75732e7631011bffcdcfae6227d5e9";
const NAME_EU = "a2004f737430782e726261632e65752e7631011bffcdcfae6227d5e9";
const TYPE_ADDRESS = "a2004761646472657373011bffcdb2cc1b1d53be";
const TYPE_UINT256 = "a2004775696e74323536011bffcdb2cc1b1d53be";
const META_OK = P.concat(NAME_US).concat(TYPE_ADDRESS);
/** A rainlang source item, the type, then the name with `identity` encoding. */
const META_FOREIGN = P.concat("a200455f3a20313b011bff13109e41336ff2")
  .concat(TYPE_ADDRESS)
  .concat(
    "a3004f737430782e726261632e75732e7631011bffcdcfae6227d5e903686964656e74697479",
  );
/** The name deflated. */
const META_DEFLATE = P.concat(
  "a30057789c2b2e31a8d02b4a4a4cd62b2dd62b3304002ba10541011bffcdcfae6227d5e903676465666c617465",
).concat(TYPE_ADDRESS);
/**
 * Hand-built, accepted by `cbor_decode`: an indefinite foreign item map with a
 * tag, an indefinite byte string, a half float and a nested map.
 */
const META_EXOTIC = P.concat(
  "bf004161011bff13109e41336ff2059fc11a000000015f4161426263fff93c00a10180ffff",
)
  .concat(NAME_US)
  .concat(TYPE_ADDRESS);
/** Hand-built, each rejected by `cbor_decode`. */
const FOREIGN_KEY_5 = "a3004161011bff13109e41336ff205";
const META_RESERVED_INFO = P.concat(FOREIGN_KEY_5)
  .concat("1c")
  .concat("00".repeat(16))
  .concat(NAME_US)
  .concat(TYPE_ADDRESS);
const META_TEXT_KEY = P.concat("a261304161011bff13109e41336ff2")
  .concat(NAME_US)
  .concat(TYPE_ADDRESS);
const META_DUPLICATE_KEY = P.concat("a3004161004162011bff13109e41336ff2")
  .concat(NAME_US)
  .concat(TYPE_ADDRESS);
const META_NO_MAGIC = P.concat("a1004161").concat(NAME_US).concat(TYPE_ADDRESS);
const META_NO_PAYLOAD = P.concat("a10100").concat(NAME_US).concat(TYPE_ADDRESS);
const META_TRAILING_BREAK = META_OK.concat("ff");
const META_TOO_DEEP = P.concat("a3004161011bff13109e41336ff205")
  .concat("81".repeat(200))
  .concat("00")
  .concat(NAME_US)
  .concat(TYPE_ADDRESS);
const META_INDEFINITE_INT = P.concat(FOREIGN_KEY_5)
  .concat("1f")
  .concat(NAME_US)
  .concat(TYPE_ADDRESS);
const META_MIXED_CHUNK = P.concat(FOREIGN_KEY_5)
  .concat("5f6141ff")
  .concat(NAME_US)
  .concat(TYPE_ADDRESS);
const META_INDEFINITE_TAG = P.concat(FOREIGN_KEY_5)
  .concat("df")
  .concat(NAME_US)
  .concat(TYPE_ADDRESS);
const META_LONE_BREAK = P.concat(FOREIGN_KEY_5)
  .concat("ff")
  .concat(NAME_US)
  .concat(TYPE_ADDRESS);
const META_EMPTY_TEXT_KEY = P.concat("a2604161011bff13109e41336ff2")
  .concat(NAME_US)
  .concat(TYPE_ADDRESS);
const META_NEGATIVE_MAGIC = P.concat("a20041610120")
  .concat(NAME_US)
  .concat(TYPE_ADDRESS);
const META_TRUNCATED_ITEM = META_OK.concat("a2004161");
/** Accepted by `cbor_decode`: a foreign item holding a definite map. */
const META_NESTED_MAP = P.concat(FOREIGN_KEY_5)
  .concat("a10102")
  .concat(NAME_US)
  .concat(TYPE_ADDRESS);
/** The name raw but declared `deflate`. */
const META_RAW_DECLARED_DEFLATE = P.concat(
  "a3004f737430782e726261632e75732e7631011bffcdcfae6227d5e903676465666c617465",
).concat(TYPE_ADDRESS);
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

function registerEvent(
  sender: string,
  name: string,
  valueType: string,
  value: string,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  return registerV5Log(
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
  handleConfigRegistryV5Register(
    changetype<RegisterV5>(
      registerEvent(sender, name, valueType, value, blockNumber, logIndex),
    ),
  );
}

function metaEvent(
  subject: string,
  metaHex: string,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  return metaV1_2Log(
    Address.fromString(REGISTRY),
    Address.fromString(DELEGATE),
    Bytes.fromHexString(subject),
    Bytes.fromHexString(metaHex),
    blockNumber,
    logIndex,
  );
}

function meta(
  subject: string,
  metaHex: string,
  blockNumber: i32,
  logIndex: i32,
): void {
  handleConfigRegistryV5MetaV1_2(
    changetype<MetaV1_2>(metaEvent(subject, metaHex, blockNumber, logIndex)),
  );
}

describe("ConfigRegistryV5 Register", () => {
  afterEach(clearStore);

  test("a first Register binds the value, its type and its type hash", () => {
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

    assert.fieldEquals("Contract", REGISTRY, "kind", "CONFIG_REGISTRY_V5");
    assert.fieldEquals("Contract", REGISTRY, "firstIndexedBlock", "100");
  });

  test("the type hash is keccak256 of the emitted type", () => {
    register(AUTHORITY, US_NAME, "(address,uint256)", VALUE_B, 100, 3);

    let id = bindingId(REGISTRY, AUTHORITY, US_NAME);
    assert.fieldEquals("ConfigBinding", id, "valueTypeHash", TUPLE_HASH);
    assert.fieldEquals(
      "ConfigRegister",
      mockRowId(3),
      "valueTypeHash",
      TUPLE_HASH,
    );
  });

  test("a rebind as another type moves the type and keeps each row's own", () => {
    register(AUTHORITY, US_NAME, "address", VALUE_A, 100, 3);
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
    register(AUTHORITY, US_NAME, "address", VALUE_A, 100, 3);
    register(AUTHORITY, US_NAME, "(address,uint256)", VALUE_B, 250, 1);
    register(AUTHORITY, US_NAME, "address", VALUE_A, 100, 3);

    let id = bindingId(REGISTRY, AUTHORITY, US_NAME);
    assert.fieldEquals("ConfigBinding", id, "valueType", "(address,uint256)");
    assert.fieldEquals("ConfigBinding", id, "valueTypeHash", TUPLE_HASH);
    assert.fieldEquals("ConfigBinding", id, "registerCount", "2");
    assert.entityCount("ConfigRegister", 2);
  });

  test("a V3 and a V5 binding of one name are separate rows, the V3 one untyped", () => {
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
    register(AUTHORITY, US_NAME, "address", VALUE_A, 100, 3);

    assert.entityCount("ConfigBinding", 2);
    assert.entityCount("Contract", 2);
    assert.fieldEquals("Contract", REGISTRY_V3, "kind", "CONFIG_REGISTRY");
    assert.fieldEquals("Contract", REGISTRY, "kind", "CONFIG_REGISTRY_V5");
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

describe("ConfigRegistryV5 MetaV1_2", () => {
  afterEach(clearStore);

  test("a bind's meta links to its binding and its Register, raw", () => {
    register(DELEGATE, US_NAME, "address", VALUE_A, 100, 3);
    meta(US_SUBJECT, META, 100, 4);

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
    register(AUTHORITY, US_NAME, "address", VALUE_A, 100, 3);
    meta(US_SUBJECT, META, 100, 4);
    handleConfigRegistryV5Register(
      changetype<RegisterV5>(
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
    handleConfigRegistryV5MetaV1_2(
      changetype<MetaV1_2>(
        inTx(
          metaEvent(US_SUBJECT, META, 250, 2),
          Bytes.fromHexString(OTHER_TX),
        ),
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
    register(AUTHORITY, US_NAME, "address", VALUE_A, 100, 3);
    handleConfigRegistryV5MetaV1_2(
      changetype<MetaV1_2>(
        inTx(
          metaEvent(US_SUBJECT, META, 300, 0),
          Bytes.fromHexString(OTHER_TX),
        ),
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
    meta(EU_NAME, META, 100, 4);

    let entity = RegistryMeta.load(Bytes.fromHexString(mockRowId(4)))!;
    assert.assertTrue(entity.configBinding === null);
    assert.assertTrue(entity.configRegister === null);
    assert.assertTrue(entity.migrationRecord === null);
    assert.fieldEquals("RegistryMeta", mockRowId(4), "meta", META);
    assert.fieldEquals("Contract", REGISTRY, "kind", "CONFIG_REGISTRY_V5");
  });

  test("a replayed meta writes one row", () => {
    register(AUTHORITY, US_NAME, "address", VALUE_A, 100, 3);
    meta(US_SUBJECT, META, 100, 4);
    meta(US_SUBJECT, META, 100, 4);

    assert.entityCount("RegistryMeta", 1);
  });
});

const VERIFIED = "true|st0x.rbac.us.v1";
const UNVERIFIED = "false|null";
function verifiedFor(metaHex: string, valueType: string): string {
  register(AUTHORITY, US_NAME, valueType, VALUE_A, 100, 3);
  meta(US_SUBJECT, metaHex, 100, 4);
  let row = RegistryMeta.load(Bytes.fromHexString(mockRowId(4)))!;
  let name = row.nameString;
  return (row.verified ? "true|" : "false|").concat(
    name === null ? "null" : name!,
  );
}

describe("ConfigRegistryV5 MetaV1_2 verification", () => {
  afterEach(clearStore);

  test("name and value type preimages that hash to the binding verify", () => {
    assert.stringEquals(verifiedFor(META_OK, "address"), VERIFIED);
  });

  test("a name preimage that hashes elsewhere does not verify", () => {
    assert.stringEquals(
      verifiedFor(P.concat(NAME_EU).concat(TYPE_ADDRESS), "address"),
      UNVERIFIED,
    );
  });

  test("a value type preimage that hashes elsewhere does not verify", () => {
    assert.stringEquals(
      verifiedFor(P.concat(NAME_US).concat(TYPE_UINT256), "address"),
      UNVERIFIED,
    );
  });

  test("the value type is checked against this Register's type", () => {
    assert.stringEquals(verifiedFor(META_OK, "uint256"), UNVERIFIED);
  });

  test("a missing name or value type item does not verify", () => {
    assert.stringEquals(verifiedFor(P.concat(NAME_US), "address"), UNVERIFIED);
    clearStore();
    assert.stringEquals(
      verifiedFor(P.concat(TYPE_ADDRESS), "address"),
      UNVERIFIED,
    );
  });

  test("a second name item that hashes elsewhere does not verify", () => {
    assert.stringEquals(
      verifiedFor(
        P.concat(NAME_US).concat(NAME_EU).concat(TYPE_ADDRESS),
        "address",
      ),
      UNVERIFIED,
    );
  });

  test("foreign items are skipped and identity encoding is plain", () => {
    assert.stringEquals(verifiedFor(META_FOREIGN, "address"), VERIFIED);
    clearStore();
    assert.stringEquals(verifiedFor(META_EXOTIC, "address"), VERIFIED);
    clearStore();
    assert.stringEquals(verifiedFor(META_NESTED_MAP, "address"), VERIFIED);
  });

  test("a deflated preimage does not verify", () => {
    assert.stringEquals(verifiedFor(META_DEFLATE, "address"), UNVERIFIED);
  });

  test("a raw preimage declared deflated does not verify", () => {
    assert.stringEquals(
      verifiedFor(META_RAW_DECLARED_DEFLATE, "address"),
      UNVERIFIED,
    );
  });

  test("items under another document magic do not verify", () => {
    assert.stringEquals(
      verifiedFor(
        "0xffcdcfae6227d5e9".concat(NAME_US).concat(TYPE_ADDRESS),
        "address",
      ),
      UNVERIFIED,
    );
  });

  test("malformed meta does not verify", () => {
    let cases = [
      META,
      META_OK.slice(0, META_OK.length - 2),
      "0x".concat(META_OK.slice(18)),
      "0xff0a89c674ee78",
      "0x",
      META_RESERVED_INFO,
      META_TEXT_KEY,
      META_DUPLICATE_KEY,
      META_NO_MAGIC,
      META_NO_PAYLOAD,
      META_TRAILING_BREAK,
      META_TOO_DEEP,
      META_INDEFINITE_INT,
      META_MIXED_CHUNK,
      META_INDEFINITE_TAG,
      META_LONE_BREAK,
      META_EMPTY_TEXT_KEY,
      META_NEGATIVE_MAGIC,
      META_TRUNCATED_ITEM,
    ];
    for (let i = 0; i < cases.length; i++) {
      clearStore();
      assert.stringEquals(verifiedFor(cases[i], "address"), UNVERIFIED);
    }
  });

  test("meta with no Register in its transaction does not verify", () => {
    register(AUTHORITY, US_NAME, "address", VALUE_A, 100, 3);
    handleConfigRegistryV5MetaV1_2(
      changetype<MetaV1_2>(
        inTx(
          metaEvent(US_SUBJECT, META_OK, 300, 0),
          Bytes.fromHexString(OTHER_TX),
        ),
      ),
    );
    assert.fieldEquals(
      "RegistryMeta",
      rowIdIn(OTHER_TX, 0),
      "verified",
      "false",
    );
    assert.assertNull<string | null>(
      RegistryMeta.load(Bytes.fromHexString(rowIdIn(OTHER_TX, 0)))!.nameString,
    );
    clearStore();
    meta(EU_NAME, META_OK, 100, 4);
    assert.fieldEquals("RegistryMeta", mockRowId(4), "verified", "false");
    assert.assertNull<string | null>(
      RegistryMeta.load(Bytes.fromHexString(mockRowId(4)))!.nameString,
    );
  });
});

describe("ConfigRegistryV5 delegates", () => {
  afterEach(clearStore);

  test("Approved then Revoked move an approval under the V5 registry", () => {
    handleConfigRegistryV5Approved(
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
    assert.fieldEquals("Contract", REGISTRY, "kind", "CONFIG_REGISTRY_V5");

    handleConfigRegistryV5Revoked(
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

function unscoped(approved: boolean, blockNumber: i32, logIndex: i32): void {
  let log = unscopedDelegateChangeLog(
    Address.fromString(REGISTRY),
    Address.fromString(AUTHORITY),
    Address.fromString(DELEGATE),
    blockNumber,
    logIndex,
  );
  if (approved) {
    handleConfigRegistryV5ApprovedUnscoped(changetype<ApprovedUnscoped>(log));
  } else {
    handleConfigRegistryV5RevokedUnscoped(changetype<RevokedUnscoped>(log));
  }
}

describe("ConfigRegistryV5 unscoped delegates", () => {
  afterEach(clearStore);

  test("ApprovedUnscoped then RevokedUnscoped move an unscoped approval", () => {
    unscoped(true, 300, 4);
    let id = REGISTRY.concat(AUTHORITY.slice(2)).concat(DELEGATE.slice(2));
    assert.fieldEquals("RegistryUnscopedDelegate", id, "approved", "true");
    assert.fieldEquals("RegistryUnscopedDelegate", id, "registry", REGISTRY);
    assert.fieldEquals("RegistryUnscopedDelegate", id, "account", AUTHORITY);
    assert.fieldEquals("RegistryUnscopedDelegate", id, "delegate", DELEGATE);
    assert.fieldEquals("Contract", REGISTRY, "kind", "CONFIG_REGISTRY_V5");

    unscoped(false, 400, 2);
    assert.fieldEquals("RegistryUnscopedDelegate", id, "approved", "false");
    assert.fieldEquals(
      "RegistryUnscopedDelegate",
      id,
      "approvedAtBlock",
      "300",
    );
    assert.fieldEquals("RegistryUnscopedDelegate", id, "revokedAtBlock", "400");
    assert.entityCount("RegistryUnscopedDelegateChange", 2);
    assert.fieldEquals(
      "RegistryUnscopedDelegateChange",
      mockRowId(4),
      "approved",
      "true",
    );
    assert.entityCount("RegistryDelegate", 0);
  });
});
