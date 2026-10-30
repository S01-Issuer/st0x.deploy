import { Bytes, crypto } from "@graphprotocol/graph-ts";

export const RAIN_META_DOCUMENT_V1: u64 = 0xff0a89c674ee7874;
export const CONFIG_REGISTRY_NAME_V1: u64 = 0xffcdcfae6227d5e9;
export const CONFIG_REGISTRY_VALUE_TYPE_V1: u64 = 0xffcdb2cc1b1d53be;
export const MIGRATION_REGISTRY_NAMESPACE_V1: u64 = 0xff82e354bb91c055;
export const MIGRATION_REGISTRY_MIGRATION_V1: u64 = 0xffae12bf8892cc25;

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

  /** One definite-length byte string or UTF-8 text string, or null. */
  definite(): Bytes | null {
    let length = this.head();
    if (
      !this.ok ||
      (this.major != 2 && this.major != 3) ||
      length == INDEFINITE
    ) {
      this.fail();
      return null;
    }
    let text = this.major == 3;
    let value = this.take(length);
    if (!this.ok || (text && !utf8(value))) {
      this.fail();
      return null;
    }
    return value;
  }

  encoding(): boolean {
    if (!this.ok || this.done()) {
      this.fail();
      return false;
    }
    if (this.data[this.pos] >> 5 == 0) {
      let index = this.head();
      if (!this.ok || index > 2) {
        this.fail();
      }
      return index < 2;
    }
    let name = this.definite();
    if (name === null) {
      return false;
    }
    if (
      name.equals(Bytes.fromUTF8("none")) ||
      name.equals(Bytes.fromUTF8("identity"))
    ) {
      return true;
    }
    if (!name.equals(Bytes.fromUTF8("deflate"))) {
      this.fail();
    }
    return false;
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
        payload = this.definite();
      } else if (key == 1) {
        magic = this.head();
        hasMagic = this.major == 0 && magic != INDEFINITE;
        if (!hasMagic) {
          this.fail();
        }
      } else if (key == 3) {
        plain = this.encoding();
      } else {
        this.skip(1);
      }
    }
    if (!this.ok || payload === null || !hasMagic) {
      this.fail();
      return null;
    }
    return new Item(magic, payload!, plain);
  }
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
    items.push(item);
  }
  return items;
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
