import assert from "node:assert/strict";

let uploads = 0;
globalThis.fetch = async (url, request) => {
  assert.equal(url, "https://uploads.pinata.cloud/v3/files");
  assert.equal(request.method, "POST");
  assert.equal(request.headers.Authorization, "Bearer launch-test");
  const json = JSON.parse(await request.body.get("file").text());
  const isSchema = uploads++ === 0;
  assert.equal(json.schema?.type === "object", isSchema);
  const cid = isSchema
    ? process.env.LAUNCH_TEST_SCHEMA_CID
    : process.env.LAUNCH_TEST_METADATA_CID;
  assert.ok(cid);
  return new Response(JSON.stringify({ data: { cid } }), { status: 200 });
};
