import { rawCid } from "./cid.mjs";

/** Upload `JSON.stringify(data)` to Pinata (IPFS) and return its CID, which
 * must be the CID of the uploaded bytes. */
export async function uploadToPinata(data) {
  const jwt = process.env.PINATA_JWT;
  if (!jwt) {
    throw new Error("PINATA_JWT environment variable is not set");
  }

  const json = JSON.stringify(data);
  const blob = new Blob([json], { type: "application/json" });
  const formData = new FormData();
  formData.append("file", blob, "metadata.json");

  const response = await fetch("https://uploads.pinata.cloud/v3/files", {
    method: "POST",
    headers: { Authorization: `Bearer ${jwt}` },
    body: formData,
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Pinata upload failed (${response.status}): ${text}`);
  }

  const result = await response.json();
  const cid = result?.data?.cid;
  const expected = rawCid(Buffer.from(json, "utf8"));
  if (cid !== expected) {
    throw new Error(
      `Pinata returned CID ${
        JSON.stringify(cid)
      }, expected ${expected} for the uploaded bytes`,
    );
  }
  return cid;
}
