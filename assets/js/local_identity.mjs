const storageKey = "nozomi:identity"
// ponytail: memory fallback lasts for this page; durable identity requires working browser storage.
let identity = null

export const LocalIdentity = {
  mounted() {
    if (!identity) {
      try {
        const saved = JSON.parse(localStorage.getItem(storageKey))
        if (saved && typeof saved === "object" && !Array.isArray(saved)) identity = saved
      } catch (_error) {
        // Missing, corrupt, or blocked storage is repaired after server restoration.
      }
    }

    this.handleEvent("identity", value => {
      identity = value
      let available = true
      try {
        localStorage.setItem(storageKey, JSON.stringify(identity))
      } catch (_error) {
        available = false
      }
      this.pushEvent("identity_storage", {available})
    })
    this.restoreIdentity()
  },

  reconnected() {
    this.restoreIdentity()
  },

  restoreIdentity() {
    this.pushEvent("restore_identity", identity || {})
  },
}
