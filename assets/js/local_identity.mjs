const storageKey = "nozomi:identity"
// ponytail: memory fallback lasts for this page; durable identity requires working browser storage.
let identity = null

function readStored() {
  try {
    const saved = JSON.parse(localStorage.getItem(storageKey))
    if (saved && typeof saved === "object" && !Array.isArray(saved)) return saved
  } catch (_error) {
    // Missing, corrupt, or blocked storage is repaired after server restoration.
  }
  return null
}

// Another tab may have written a newer alias; on a tie the stored copy wins, so a
// stale reconnect cannot revert it while a failed write still keeps the memory value.
function newest(memory, stored) {
  if (!stored) return memory
  if (!memory) return stored
  return (stored.updatedAt || 0) >= (memory.updatedAt || 0) ? stored : memory
}

export const LocalIdentity = {
  mounted() {
    identity = newest(identity, readStored())

    this.handleEvent("identity", value => {
      identity = {...value, updatedAt: Date.now()}
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
    // Re-read storage so a newer alias from another tab survives the reconnect.
    identity = newest(identity, readStored())
    this.restoreIdentity()
  },

  restoreIdentity() {
    this.pushEvent("restore_identity", identity || {})
  },
}
