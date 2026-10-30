import { Bytes, crypto } from "@graphprotocol/graph-ts";

export const RAIN_META_DOCUMENT_V1: u64 = 0xff0a89c674ee7874;
export const CONFIG_REGISTRY_NAME_V1: u64 = 0xffcdcfae6227d5e9;
export const CONFIG_REGISTRY_VALUE_TYPE_V1: u64 = 0xffcdb2cc1b1d53be;
export const MIGRATION_REGISTRY_NAMESPACE_V1: u64 = 0xff82e354bb91c055;
export const MIGRATION_REGISTRY_MIGRATION_V1: u64 = 0xffae12bf8892cc25;

const OA_SCHEMA: u64 = 0xffa8e8a9b9cf4a31;
const KNOWN_MAGICS: u64[] = [
  0xffe5282f43e495b4,
  0xffdac2f2f37be894,
  0xff1c198cec3b48a7,
  0xffe5ffb4a3ff2cde,
  0xffe9e3a02ca8e235,
  0xff52fe42f1a05093,
  0xffc21bbf86cc199b,
  0xffdb988a8cd04d32,
  0xff13109e41336ff2,
  0xffb2637608c09e38,
  0xffa15ef0fc437099,
  0xffda7b2fb167c286,
  0xff7a1507ba4419ca,
  0xff5dcce9b571ba42,
  OA_SCHEMA,
  0xff9fae3cc645f463,
  0xffc47a6299e8a911,
  0xff8cd2927c8c86cb,
  0xffbc38eb14ad2209,
  CONFIG_REGISTRY_NAME_V1,
  CONFIG_REGISTRY_VALUE_TYPE_V1,
  MIGRATION_REGISTRY_NAMESPACE_V1,
  MIGRATION_REGISTRY_MIGRATION_V1,
];
const CONTENT_TYPES: string[] = [
  "None",
  "application/json",
  "application/cbor",
  "application/octet-stream",
];
const CONTENT_ENCODINGS: string[] = ["none", "identity", "deflate"];
const CONTENT_LANGUAGES: string[] = ["none", "en"];
const MAX_DEPTH: i32 = 127;
const INDEFINITE: u64 = u64.MAX_VALUE;

/** One rain meta item magic and the `bytes32` key its payload must hash to. */
export class PreimageCheck {
  constructor(
    public magic: u64,
    public key: Bytes,
  ) {}
}

class Item {
  constructor(
    public magic: u64,
    public payload: Bytes,
    public plain: boolean,
  ) {}
}

class CborReader {
  pos: i32 = 0;
  ok: boolean = true;
  major: u8 = 0;
  info: u8 = 0;

  constructor(public data: Bytes) {}

  done(): boolean {
    return this.pos >= this.data.length;
  }

  fail(): u64 {
    this.ok = false;
    return 0;
  }

  /** The head's argument; `INDEFINITE` for additional info 31. */
  head(): u64 {
    if (!this.ok || this.done()) {
      return this.fail();
    }
    let initial = this.data[this.pos];
    this.pos += 1;
    this.major = initial >> 5;
    this.info = initial & 0x1f;
    if (this.info < 24) {
      return this.info as u64;
    }
    if (this.info == 31) {
      return INDEFINITE;
    }
    if (this.info > 27) {
      return this.fail();
    }
    let size = 1 << (this.info - 24);
    if (this.pos + size > this.data.length) {
      return this.fail();
    }
    let value: u64 = 0;
    for (let i = 0; i < size; i++) {
      value = (value << 8) | (this.data[this.pos + i] as u64);
    }
    this.pos += size;
    return value;
  }

  take(length: u64): Bytes {
    if (!this.ok || length > ((this.data.length - this.pos) as u64)) {
      this.fail();
      return Bytes.empty();
    }
    let start = this.pos;
    this.pos += length as i32;
    return Bytes.fromUint8Array(this.data.subarray(start, this.pos));
  }

  isBreak(): boolean {
    return this.ok && !this.done() && this.data[this.pos] == 0xff;
  }

  skip(depth: i32): void {
    let argument = this.head();
    if (!this.ok) {
      return;
    }
    let major = this.major;
    if (major >= 4 && major <= 6 && depth >= MAX_DEPTH) {
      this.fail();
      return;
    }
    if (major == 0 || major == 1) {
      if (argument == INDEFINITE) {
        this.fail();
      }
    } else if (major == 2 || major == 3) {
      if (argument == INDEFINITE) {
        while (this.ok && !this.isBreak()) {
          let chunk = this.head();
          if (this.major != major || chunk == INDEFINITE) {
            this.fail();
            return;
          }
          this.take(chunk);
        }
        this.pos += 1;
      } else {
        this.take(argument);
      }
    } else if (major == 4 || major == 5) {
      let per: u64 = major == 4 ? 1 : 2;
      if (argument == INDEFINITE) {
        while (this.ok && !this.isBreak()) {
          for (let i: u64 = 0; i < per; i++) {
            this.skip(depth + 1);
          }
        }
        this.pos += 1;
      } else {
        if (argument > ((this.data.length - this.pos) as u64)) {
          this.fail();
          return;
        }
        for (let i: u64 = 0; i < argument * per && this.ok; i++) {
          this.skip(depth + 1);
        }
      }
    } else if (major == 6) {
      if (argument == INDEFINITE) {
        this.fail();
        return;
      }
      this.skip(depth + 1);
    } else if (argument == INDEFINITE) {
      this.fail();
    }
  }

  string(): Bytes | null {
    let length = this.head();
    let major = this.major;
    if (!this.ok || (major != 2 && major != 3)) {
      this.fail();
      return null;
    }
    let value = Bytes.empty();
    if (length == INDEFINITE) {
      let parts = new Array<u8>();
      while (this.ok && !this.isBreak()) {
        let chunk = this.head();
        if (!this.ok || this.major != major || chunk == INDEFINITE) {
          this.fail();
          return null;
        }
        let part = this.take(chunk);
        for (let i = 0; i < part.length; i++) {
          parts.push(part[i]);
        }
      }
      if (!this.ok || this.done()) {
        this.fail();
        return null;
      }
      this.pos += 1;
      value = bytesOf(parts);
    } else {
      value = this.take(length);
    }
    if (!this.ok || (major == 3 && !utf8(value))) {
      this.fail();
      return null;
    }
    return value;
  }

  payload(): Bytes | null {
    if (!this.ok || this.done()) {
      this.fail();
      return null;
    }
    if (this.data[this.pos] >> 5 != 4) {
      return this.string();
    }
    let length = this.head();
    if (
      length != INDEFINITE &&
      length > ((this.data.length - this.pos) as u64)
    ) {
      this.fail();
      return null;
    }
    let parts = new Array<u8>();
    let read: u64 = 0;
    while (this.ok) {
      if (length == INDEFINITE) {
        if (this.isBreak()) {
          this.pos += 1;
          break;
        }
      } else if (read == length) {
        break;
      }
      read += 1;
      let byte = this.head();
      if (!this.ok || this.major != 0 || byte > 255) {
        this.fail();
        return null;
      }
      parts.push(byte as u8);
    }
    if (!this.ok) {
      return null;
    }
    return bytesOf(parts);
  }

  variant(names: string[]): i32 {
    if (!this.ok || this.done()) {
      this.fail();
      return -1;
    }
    if (this.data[this.pos] >> 5 == 0) {
      let index = this.head();
      if (!this.ok || index >= (names.length as u64)) {
        this.fail();
        return -1;
      }
      return index as i32;
    }
    let name = this.string();
    if (name === null) {
      return -1;
    }
    for (let i = 0; i < names.length; i++) {
      if (name.equals(Bytes.fromUTF8(names[i]))) {
        return i;
      }
    }
    this.fail();
    return -1;
  }

  /** One rain meta item map: mandatory payload (0) and magic (1), each once. */
  item(): Item | null {
    let entries = this.head();
    if (!this.ok || this.major != 5) {
      this.fail();
      return null;
    }
    let payload: Bytes | null = null;
    let magic: u64 = 0;
    let hasMagic = false;
    let plain = true;
    let seen = new Array<u64>();
    let read: u64 = 0;
    while (this.ok) {
      if (entries == INDEFINITE) {
        if (this.isBreak()) {
          this.pos += 1;
          break;
        }
      } else if (read == entries) {
        break;
      }
      read += 1;
      let key = this.head();
      if (
        !this.ok ||
        this.major != 0 ||
        key == INDEFINITE ||
        seen.includes(key)
      ) {
        this.fail();
        return null;
      }
      seen.push(key);
      if (key == 0) {
        payload = this.payload();
      } else if (key == 1) {
        magic = this.head();
        hasMagic = this.major == 0 && magic != INDEFINITE;
        if (!hasMagic) {
          this.fail();
        }
      } else if (key == 2) {
        this.variant(CONTENT_TYPES);
      } else if (key == 3) {
        plain = this.variant(CONTENT_ENCODINGS) < 2;
      } else if (key == 4) {
        this.variant(CONTENT_LANGUAGES);
      } else if (key == OA_SCHEMA) {
        let schema = this.string();
        if (schema !== null && !utf8(schema)) {
          this.fail();
        }
      } else {
        this.skip(1);
      }
    }
    if (
      !this.ok ||
      payload === null ||
      !hasMagic ||
      magic == RAIN_META_DOCUMENT_V1
    ) {
      this.fail();
      return null;
    }
    return new Item(magic, payload!, plain);
  }
}

function bytesOf(parts: Array<u8>): Bytes {
  let value = new Uint8Array(parts.length);
  for (let i = 0; i < parts.length; i++) {
    value[i] = parts[i];
  }
  return Bytes.fromUint8Array(value);
}

function utf8(bytes: Bytes): boolean {
  let i = 0;
  while (i < bytes.length) {
    let b = bytes[i] as i32;
    if (b < 0x80) {
      i += 1;
      continue;
    }
    let n = 0;
    let lo = 0x80;
    let hi = 0xbf;
    if (b >= 0xc2 && b <= 0xdf) {
      n = 1;
    } else if (b >= 0xe0 && b <= 0xef) {
      n = 2;
      if (b == 0xe0) {
        lo = 0xa0;
      } else if (b == 0xed) {
        hi = 0x9f;
      }
    } else if (b >= 0xf0 && b <= 0xf4) {
      n = 3;
      if (b == 0xf0) {
        lo = 0x90;
      } else if (b == 0xf4) {
        hi = 0x8f;
      }
    } else {
      return false;
    }
    if (i + n >= bytes.length) {
      return false;
    }
    for (let k = 1; k <= n; k++) {
      let c = bytes[i + k] as i32;
      if (c < (k == 1 ? lo : 0x80) || c > (k == 1 ? hi : 0xbf)) {
        return false;
      }
    }
    i += n + 1;
  }
  return true;
}

/** Every item of a rain meta document, or null when it is not one. */
function documentItems(meta: Bytes): Item[] | null {
  if (meta.length < 8) {
    return null;
  }
  let prefix: u64 = 0;
  for (let i = 0; i < 8; i++) {
    prefix = (prefix << 8) | (meta[i] as u64);
  }
  if (prefix != RAIN_META_DOCUMENT_V1) {
    return null;
  }
  let reader = new CborReader(Bytes.fromUint8Array(meta.subarray(8)));
  let items = new Array<Item>();
  while (!reader.done()) {
    let item = reader.item();
    if (item === null) {
      return null;
    }
    if (KNOWN_MAGICS.includes(item.magic)) {
      items.push(item);
    }
  }
  return items.length == 0 ? null : items;
}

/**
 * Each check's preimage, in order, when `meta` is a well formed rain meta
 * document holding at least one item of each check's magic and every such item
 * is unencoded with a payload whose `keccak256` is the check's key; else null.
 */
export function verifyPreimages(
  meta: Bytes,
  checks: PreimageCheck[],
): Bytes[] | null {
  let items = documentItems(meta);
  if (items === null) {
    return null;
  }
  let preimages = new Array<Bytes>();
  for (let c = 0; c < checks.length; c++) {
    let check = checks[c];
    let found: Bytes | null = null;
    for (let i = 0; i < items.length; i++) {
      let item = items[i];
      if (item.magic != check.magic) {
        continue;
      }
      if (
        !item.plain ||
        !Bytes.fromByteArray(crypto.keccak256(item.payload)).equals(check.key)
      ) {
        return null;
      }
      found = item.payload;
    }
    if (found === null) {
      return null;
    }
    preimages.push(found!);
  }
  return preimages;
}
