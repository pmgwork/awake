import { Plugin } from "@opencode-ai/plugin"

const bridge = "__AWAKE_BRIDGE_PATH__"

export default Plugin.define({
  id: "pmgwork.awake",
  setup(ctx) {
    const controller = new AbortController()
    const active = new Set<string>()

    const send = async (sessionID: string, state: "active" | "idle", reason: string) => {
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
          const value = event as any
          const properties = value.properties ?? {}
          const sessionID = properties.sessionID ?? properties.session_id
            ?? properties.session?.id ?? properties.info?.id ?? ""
          if (value.type === "session.error") {
            await send(sessionID, "idle", "session.error")
            continue
          }
          if (value.type !== "session.status") continue
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
})
