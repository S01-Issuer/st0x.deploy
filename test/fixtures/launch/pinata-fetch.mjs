import assert from "node:assert/strict";
import { createHash } from "node:crypto";

const BASE32 = "abcdefghijklmnopqrstuvwxyz234567";

/** The CIDv1 Pinata gives a single-block file: raw codec, sha2-256, base32. */
function rawCid(bytes) {
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

let uploads = 0;
globalThis.fetch = async (url, request) => {
  assert.equal(url, "https://uploads.pinata.cloud/v3/files");
  assert.equal(request.method, "POST");
  assert.equal(request.headers.Authorization, "Bearer launch-test");
  const bytes = Buffer.from(await request.body.get("file").arrayBuffer());
  const json = JSON.parse(bytes.toString("utf8"));
  const isSchema = uploads++ === 0;
  assert.equal(json.schema?.type === "object", isSchema);
  const cid = isSchema
    ? process.env.LAUNCH_TEST_SCHEMA_CID
    : process.env.LAUNCH_TEST_METADATA_CID;
  assert.equal(rawCid(bytes), cid);
  return new Response(JSON.stringify({ data: { cid } }), { status: 200 });
};
