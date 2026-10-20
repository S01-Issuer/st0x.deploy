import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import http from "node:http";
import { fileURLToPath } from "node:url";

const [command, argument] = process.argv.slice(2);
const failure = {
  code: -32000,
  message: "role-history fixture refused window",
};

if (command === "start") {
  assert.ok(["limited", "floor"].includes(argument));
  const child = spawn(
    process.execPath,
    [fileURLToPath(import.meta.url), "serve", argument],
    {
      detached: true,
      stdio: ["ignore", "ignore", "ignore", "ipc"],
    },
  );
  let timeout;
  try {
    const { url } = await new Promise((resolve, reject) => {
      timeout = setTimeout(
        () => reject(new Error("fixture startup timed out")),
        10000,
      );
      child.once("error", reject);
      child.once("exit", () => {
        reject(new Error("fixture exited before listening"));
      });
      child.once("message", resolve);
    });
    process.stdout.write(url);
  } catch (error) {
    child.kill("SIGTERM");
    throw error;
  } finally {
    clearTimeout(timeout);
    if (child.connected) child.disconnect();
    child.unref();
  }
} else if (command === "stop" || command === "stats") {
  const url = new URL(argument);
  assert.equal(url.hostname, "127.0.0.1");
  const response = await fetch(new URL(`/${command}`, url));
  assert.ok(response.ok);
  process.stdout.write(await response.text());
} else if (command === "serve") {
  const anvil = spawn("anvil", ["--host", "127.0.0.1", "--port", "0"], {
    stdio: ["ignore", "pipe", "ignore"],
  });
  const anvilExit = new Promise((resolve) => {
    anvil.once("exit", resolve);
    anvil.once("error", resolve);
  });
  let server;
  let idle;
  let stopping = false;
  async function stop() {
    if (stopping) return;
    stopping = true;
    clearTimeout(idle);
    anvil.kill("SIGTERM");
    await anvilExit;
    server?.close();
  }
  process.once("SIGTERM", () => void stop());
  process.once("SIGINT", () => void stop());
  try {
    const upstream = await new Promise((resolve, reject) => {
      let output = "";
      anvil.once("error", reject);
      anvil.once("exit", () => {
        reject(new Error("anvil exited before listening"));
      });
      anvil.stdout.on("data", (data) => {
        output += data;
        const match = output.match(/Listening on (127\.0\.0\.1:\d+)/);
        if (match) resolve(`http://${match[1]}`);
      });
    });
    const ranges = [];
    const blocks = [100, 599, 600, 1099, 1100, 1299];
    const word = (value) => `0x${BigInt(value).toString(16).padStart(64, "0")}`;
    async function rpc(request) {
      if (request.method !== "eth_getLogs") {
        const response = await fetch(upstream, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(request),
        });
        return response.json();
      }
      const filter = request.params[0];
      const from = Number(BigInt(filter.fromBlock));
      const to = Number(BigInt(filter.toBlock));
      ranges.push([from, to]);
      if (argument === "floor" || to - from + 1 > 500) {
        return { jsonrpc: "2.0", id: request.id, error: failure };
      }
      const result = blocks
        .filter((block) => from <= block && block <= to)
        .map((block) => ({
          address: "0x00000000000000000000000000000000000a11ce",
          topics: [word(0xbeef)],
          data: word(block),
          blockNumber: `0x${block.toString(16)}`,
          blockHash: word(block),
          transactionHash: word(block),
          transactionIndex: "0x0",
          logIndex: "0x0",
          removed: false,
        }));
      return { jsonrpc: "2.0", id: request.id, result };
    }
    server = http.createServer(async (request, response) => {
      if (request.url === "/stats") {
        response.end(
          JSON.stringify({ ranges, pid: process.pid, anvilPid: anvil.pid }),
        );
      } else if (request.url === "/stop") {
        await stop();
        response.end("stopped");
      } else {
        try {
          let body = "";
          for await (const chunk of request) body += chunk;
          const query = JSON.parse(body);
          const result = Array.isArray(query)
            ? await Promise.all(query.map(rpc))
            : await rpc(query);
          response.setHeader("Content-Type", "application/json");
          response.end(JSON.stringify(result));
        } catch (error) {
          response.statusCode = 500;
          response.end(String(error));
        }
      }
    });
    await new Promise((resolve, reject) => {
      server.once("error", reject);
      server.listen(0, "127.0.0.1", resolve);
    });
    const port = server.address().port;
    // Forge reads the fork after the test call returns. Idle timeout reaps
    // the process once that read is finished.
    idle = setTimeout(() => void stop(), 20000);
    server.on("request", () => {
      idle.refresh();
    });
    process.send({ url: `http://127.0.0.1:${port}` });
  } catch (error) {
    await stop();
    throw error;
  }
} else {
  throw new Error("expected start, serve, stats, or stop");
}
