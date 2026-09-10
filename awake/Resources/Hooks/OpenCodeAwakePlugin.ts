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
    cleanup: () => Promise.all([...active].map(sessionID => send(sessionID, "idle", "plugin.unload"))),
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
      try {
        for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
          await reporter.handle(event)
        }
      } catch (_) {
        // Abort and server shutdown are expected lifecycle events.
      }
    })()

    return () => {
      controller.abort()
      return reporter.cleanup()
    }
  },
}

export default AwakePlugin
