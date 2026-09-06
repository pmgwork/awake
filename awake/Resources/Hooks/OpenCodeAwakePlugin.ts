// Awake session-lifecycle reporter (pmgwork.awake).
//
// Dependency-free on purpose: "@opencode-ai/plugin" cannot be resolved from
// outside the OpenCode config directory, and a failing import makes OpenCode
// refuse to load the whole plugin. The default export below already satisfies
// the loader contract (an id plus a setup function); Plugin.define is only a
// typing helper, so a plain object is used instead.

const bridge = "__AWAKE_BRIDGE_PATH__"

const AwakePlugin = {
  id: "pmgwork.awake",
  setup(ctx) {
    const controller = new AbortController()
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

    void (async () => {
      try {
        for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
          const properties = event.properties ?? {}
          const sessionID = properties.sessionID ?? properties.session_id
            ?? properties.session?.id ?? properties.info?.id ?? ""
          if (event.type === "session.error") {
            await send(sessionID, "idle", "session.error")
            continue
          }
          if (event.type === "session.idle") {
            await send(sessionID, "idle", "session.idle")
            continue
          }
          if (event.type !== "session.status") continue
          const statusValue = properties.status
          const status = typeof statusValue === "string"
            ? statusValue
            : statusValue?.type ?? statusValue?.status ?? ""
          if (status === "busy" || status === "retry") await send(sessionID, "active", `session.status:${status}`)
          if (status === "idle") await send(sessionID, "idle", "session.status:idle")
        }
      } catch (_) {
        // Abort and server shutdown are expected lifecycle events.
      }
    })()

    return () => {
      controller.abort()
      for (const sessionID of active) void send(sessionID, "idle", "plugin.unload")
    }
  },
}

export default AwakePlugin
