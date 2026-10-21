import { afterEach, describe, it } from "node:test";
import assert from "node:assert/strict";
import { rawCid } from "../cid.mjs";
import { uploadToPinata } from "../pinata.mjs";

const realFetch = globalThis.fetch;

function pinataReturns(cid) {
  globalThis.fetch = async () =>
    new Response(JSON.stringify({ data: { cid } }), { status: 200 });
}

describe("uploadToPinata", () => {
  afterEach(() => {
    globalThis.fetch = realFetch;
    delete process.env.PINATA_JWT;
  });

  it("computes the raw CIDv1 of the empty file", () => {
    assert.equal(
      rawCid(Buffer.alloc(0)),
      "bafkreihdwdcefgh4dqkjv67uzcmw7ojee6xedzdetojuzjevtenxquvyku",
    );
  });

  it("returns the CID of the uploaded bytes", async () => {
    process.env.PINATA_JWT = "test";
    const cid = rawCid(Buffer.from(JSON.stringify({ a: 1 })));
    pinataReturns(cid);
    assert.equal(await uploadToPinata({ a: 1 }), cid);
  });

  it("refuses an empty CID", async () => {
    process.env.PINATA_JWT = "test";
    pinataReturns("");
    await assert.rejects(uploadToPinata({ a: 1 }), /Pinata returned CID ""/);
  });

  it("refuses the CID of other bytes", async () => {
    process.env.PINATA_JWT = "test";
    pinataReturns(rawCid(Buffer.from(JSON.stringify({ a: 2 }))));
    await assert.rejects(uploadToPinata({ a: 1 }), /expected/);
  });
});
