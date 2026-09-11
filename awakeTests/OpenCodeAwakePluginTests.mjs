import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { test } from "node:test"
import vm from "node:vm"

const source = await readFile(new URL("../awake/Resources/Hooks/OpenCodeAwakePlugin.ts", import.meta.url), "utf8")

async function run(events, { failSpawn = false, version = 2, verifyAbort = false } = {}) {
  const calls = []
  let finish
  const consumed = new Promise(resolve => { finish = resolve })
  const context = vm.createContext({
    AbortController,
    Bun: {
      spawn(args) {
        calls.push(Object.fromEntries(args.slice(1).reduce((pairs, value, index, values) => {
          if (index % 2 === 0) pairs.push([value, values[index + 1]])
          return pairs
        }, [])))
        if (failSpawn) throw new Error("Bridge unavailable")
        return { exited: Promise.resolve(0) }
      },
    },
  })
  const plugin = vm.runInContext(source.replace("export default AwakePlugin", "AwakePlugin"), context)
  if (version === 1) {
    const hooks = await plugin.server()
    for (const event of events) await hooks.event({ event })
    return calls
  }
  let signal
  const cleanup = plugin.setup({
    event: {
      async *subscribe(options) {
        signal = options.signal
        for (const event of events) yield event
        finish()
      },
    },
  })
  await consumed
  await cleanup()
  if (verifyAbort) assert.equal(signal.aborted, true)
  return calls
}

test("V2 data envelopes report busy, retry and idle for the correct session", async () => {
  const calls = await run(["busy", "retry", "idle"].map(type => ({
    type: "session.status",
    data: { sessionID: "ses_v2", status: { type } },
  })))
  assert.deepEqual(calls.map(call => [call["--session-id"], call["--state"]]), [
    ["ses_v2", "active"],
    ["ses_v2", "active"],
    ["ses_v2", "idle"],
  ])
})

test("current V2 execution events track concurrent sessions across model steps", async () => {
  // Envelope/field names captured from the running beta-19425 service.
  const event = (type, sessionID) => ({ type, durable: true, data: { sessionID } })
  const calls = await run([
    event("session.execution.started", "ses_a"),
    event("session.step.started", "ses_a"),
    event("session.execution.started", "ses_b"),
    event("session.step.ended", "ses_a"),
    event("session.execution.succeeded", "ses_b"),
    event("session.step.started", "ses_a"),
    event("session.execution.succeeded", "ses_a"),
  ])
  assert.deepEqual(calls.map(call => [call["--session-id"], call["--state"]]), [
    ["ses_a", "active"],
    ["ses_b", "active"],
    ["ses_b", "idle"],
    ["ses_a", "idle"],
  ])
})

test("V2 failed and interrupted executions release their active state", async () => {
  for (const outcome of ["failed", "interrupted"]) {
    const calls = await run([
      { type: "session.execution.started", data: { sessionID: "ses_v2" } },
      { type: `session.execution.${outcome}`, data: { sessionID: "ses_v2" } },
    ])
    assert.deepEqual(calls.map(call => call["--state"]), ["active", "idle"])
  }
})

test("V1 envelopes handle status, terminal and ignored events despite bridge failures", async () => {
  const calls = await run([
    { type: "session.status", properties: { sessionID: "ses_old", status: "busy" } },
    { type: "session.idle", properties: { sessionID: "ses_old" } },
    { type: "session.status", properties: { sessionID: "ses_old", status: { type: "retry" } } },
    { type: "session.error", properties: { sessionID: "ses_old" } },
    { type: "message.updated", data: { sessionID: "ses_other" } },
    { type: "session.status", data: { status: { type: "busy" } } },
  ], { failSpawn: true, version: 1 })
  assert.deepEqual(calls.map(call => call["--state"]), ["active", "idle", "active", "idle"])
})

test("cleanup releases active sessions and bridge failures do not stop subscription", async () => {
  const calls = await run([
    { type: "session.status", data: { sessionID: "ses_a", status: { type: "busy" } } },
    { type: "session.status", data: { sessionID: "ses_b", status: { type: "busy" } } },
  ], { failSpawn: true, verifyAbort: true })
  assert.deepEqual(calls.map(call => [call["--session-id"], call["--reason"]]), [
    ["ses_a", "session.status:busy"], ["ses_b", "session.status:busy"],
    ["ses_a", "plugin.unload"], ["ses_b", "plugin.unload"],
  ])
})
