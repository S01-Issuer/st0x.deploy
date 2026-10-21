import { createHash } from "node:crypto";

const BASE32 = "abcdefghijklmnopqrstuvwxyz234567";

/** The CIDv1 Pinata gives a single-block file: raw codec, sha2-256, base32. */
export function rawCid(bytes) {
  const digest = createHash("sha256").update(bytes).digest();
  const cid = Buffer.concat([Buffer.from([0x01, 0x55, 0x12, 0x20]), digest]);
  let text = "b";
  let value = 0;
  let bits = 0;
  for (const byte of cid) {
    value = ((value << 8) | byte) & 0xfff;
    bits += 8;
    while (bits >= 5) {
      text += BASE32[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) text += BASE32[(value << (5 - bits)) & 31];
  return text;
}
