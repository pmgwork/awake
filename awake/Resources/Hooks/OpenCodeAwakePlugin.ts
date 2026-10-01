// Awake session-lifecycle reporter (pmgwork.awake).
//
// Dependency-free because this plugin is installed outside the config directory.
// V1 (1.18.29+) calls server(); V2 calls setup(). Both loaders accept this object.

const bridge = "__AWAKE_BRIDGE_PATH__"

function createReporter() {
  const active = new Set()

  const send = async (sessionID, state, reason) => {
    if (!sessionID) return
    if (state === "active") active.add(sessionID)
    else active.delete(sessionID)
    try {
      const child = Bun.spawn(
        [bridge, "--provider", "opencode", "--session-id", sessionID, "--state", state,
          "--reason", reason, "--occurred-at", new Date().toISOString()],
        { stdin: "ignore", stdout: "ignore", stderr: "ignore" },
      )
      await child.exited
    } catch (_) {
      // Awake integration must never affect an OpenCode session.
    }
  }

  const handle = async (event) => {
    // V2 uses data; V1 uses properties.
    const properties = event.data ?? event.properties ?? {}
    const sessionID = properties.sessionID ?? properties.session_id
      ?? properties.session?.id ?? properties.info?.id ?? ""
    // Current V2 publishes execution lifecycle events instead of session.status.
    // A step ending only ends one model call, not the whole execution.
    if (event.type === "session.execution.started") {
      await send(sessionID, "active", event.type)
      return
    }
    if (event.type === "session.execution.succeeded"
      || event.type === "session.execution.failed"
      || event.type === "session.execution.interrupted") {
      await send(sessionID, "idle", event.type)
      return
    }
    if (event.type === "session.error" || event.type === "session.idle") {
      await send(sessionID, "idle", event.type)
      return
    }
    if (event.type !== "session.status") return
    const statusValue = properties.status
    const status = typeof statusValue === "string"
      ? statusValue
      : statusValue?.type ?? statusValue?.status ?? ""
    if (status === "busy" || status === "retry") await send(sessionID, "active", `session.status:${status}`)
    if (status === "idle") await send(sessionID, "idle", "session.status:idle")
  }
  return {
    handle,
    cleanup: (reason = "plugin.unload") => Promise.all([...active].map(sessionID => send(sessionID, "idle", reason))),
  }
}

const AwakePlugin = {
  id: "pmgwork.awake",
  async server() {
    const reporter = createReporter()
    return { event: ({ event }) => reporter.handle(event) }
  },
  setup(ctx) {
    const controller = new AbortController()
    const reporter = createReporter()
    void (async () => {
      let retryDelay = 1000
      while (!controller.signal.aborted) {
        try {
          for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
            if (controller.signal.aborted) break
            await reporter.handle(event)
            retryDelay = 1000
          }
        } catch (_) {
          // A failed stream must release its sessions and retry independently
          // of plugin teardown. Normal stream EOF uses the same recovery path.
        }
        if (controller.signal.aborted) break
        await reporter.cleanup("subscription.disconnected")
        await new Promise(resolve => {
          const finish = () => {
            clearTimeout(timer)
            controller.signal.removeEventListener("abort", finish)
            resolve()
          }
          const timer = setTimeout(finish, retryDelay)
          controller.signal.addEventListener("abort", finish, { once: true })
          if (controller.signal.aborted) finish()
        })
        retryDelay = Math.min(retryDelay * 2, 30000)
      }
    })()

    return () => {
      controller.abort()
      return reporter.cleanup()
    }
  },
}

export default AwakePlugin
