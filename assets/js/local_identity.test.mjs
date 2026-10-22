import assert from "node:assert/strict"
import test from "node:test"

const key = "nozomi:identity"
const identity = {id: "43035f40-e32c-4eff-9db9-2742f7ac1eb9", alias: "Nozomi-14-Tokyo-N700-Aoi"}
let moduleNumber = 0

function storage(value = null) {
  const values = new Map(value === null ? [] : [[key, value]])
  return {
    getItem: key => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, value),
  }
}

async function browser(t, localStorage) {
  const original = Object.getOwnPropertyDescriptor(globalThis, "localStorage")
  Object.defineProperty(globalThis, "localStorage", {configurable: true, get: () => localStorage()})
  t.after(() => {
    if (original) Object.defineProperty(globalThis, "localStorage", original)
    else delete globalThis.localStorage
  })

  return freshPage()
}

async function freshPage() {
  // A fresh module represents a full page reload; remounts reuse the same module.
  const {LocalIdentity} = await import(`./local_identity.mjs?test=${moduleNumber++}`)
  return () => {
    const events = new Map()
    const sent = []
    return {
      ...LocalIdentity,
      sent,
      handleEvent: (event, callback) => events.set(event, callback),
      pushEvent: (event, payload) => sent.push([event, payload]),
      receive: value => events.get("identity")(value),
    }
  }
}

test("persists a new identity and restores it after a full page reload", async t => {
  const localStorage = storage()
  const mount = await browser(t, () => localStorage)
  const first = mount()
  first.mounted()
  assert.deepEqual(first.sent, [["restore_identity", {}]])

  first.receive(identity)
  assert.deepEqual(JSON.parse(localStorage.getItem(key)), identity)
  assert.deepEqual(first.sent.at(-1), ["identity_storage", {available: true}])

  const reload = await freshPage()
  const second = reload()
  second.mounted()
  assert.deepEqual(second.sent, [["restore_identity", identity]])
})

test("stores a regenerated alias without replacing the ID or unrelated vote data", async t => {
  const localStorage = storage(JSON.stringify(identity))
  localStorage.setItem("nozomi:votes", "existing-vote")
  const mount = await browser(t, () => localStorage)
  const hook = mount()
  hook.mounted()
  const regenerated = {...identity, alias: "Hikari-7-Kyoto-E5-Akane"}
  hook.receive(regenerated)

  assert.deepEqual(JSON.parse(localStorage.getItem(key)), regenerated)
  assert.equal(localStorage.getItem("nozomi:votes"), "existing-vote")
  hook.reconnected()
  assert.deepEqual(hook.sent.at(-1), ["restore_identity", regenerated])
})

test("retains identity across hook remounts when access to localStorage is blocked", async t => {
  const mount = await browser(t, () => { throw new Error("Storage is disabled") })
  const first = mount()
  first.mounted()
  first.receive(identity)
  assert.deepEqual(first.sent.at(-1), ["identity_storage", {available: false}])

  const second = mount()
  second.mounted()
  assert.deepEqual(second.sent, [["restore_identity", identity]])
  second.reconnected()
  assert.deepEqual(second.sent.at(-1), ["restore_identity", identity])
})

test("keeps a regenerated identity in memory when storage writes fail", async t => {
  const localStorage = storage(JSON.stringify(identity))
  localStorage.setItem = () => { throw new Error("Quota exceeded") }
  const mount = await browser(t, () => localStorage)
  const hook = mount()
  hook.mounted()
  const regenerated = {...identity, alias: "Kodama-9-Nagoya-E7-Midori"}
  hook.receive(regenerated)
  assert.deepEqual(hook.sent.at(-1), ["identity_storage", {available: false}])

  const remount = mount()
  remount.mounted()
  assert.deepEqual(remount.sent, [["restore_identity", regenerated]])
})

test("recovers from unreadable or malformed stored data without throwing", async t => {
  for (const value of ["{broken", "null", "[]", "42", '"text"']) {
    await t.test(value, async t => {
      const localStorage = storage(value)
      const mount = await browser(t, () => localStorage)
      const hook = mount()
      hook.mounted()
      assert.deepEqual(hook.sent, [["restore_identity", {}]])
      hook.receive(identity)
      assert.deepEqual(JSON.parse(localStorage.getItem(key)), identity)
    })
  }
})

test("preserves the stored ID for server-side alias repair", async t => {
  const saved = {id: identity.id, alias: "invalid"}
  const mount = await browser(t, () => storage(JSON.stringify(saved)))
  const hook = mount()
  hook.mounted()
  assert.deepEqual(hook.sent, [["restore_identity", saved]])
})
