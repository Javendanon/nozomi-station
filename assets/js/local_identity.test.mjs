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

function saved(localStorage) {
  const value = JSON.parse(localStorage.getItem(key))
  assert.equal(typeof value.updatedAt, "number")
  return {id: value.id, alias: value.alias}
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
  // A fresh module represents a full page reload or another tab; remounts reuse the same module.
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

  first.receive({...identity, restored: true})
  assert.deepEqual(saved(localStorage), identity)
  assert.equal(JSON.parse(localStorage.getItem(key)).restored, undefined)
  assert.deepEqual(first.sent.at(-1), ["identity_storage", {available: true}])

  const reload = await freshPage()
  const second = reload()
  second.mounted()
  assert.deepEqual(second.sent, [["restore_identity", JSON.parse(localStorage.getItem(key))]])
})

test("stores a regenerated alias without replacing the ID or unrelated vote data", async t => {
  const localStorage = storage(JSON.stringify(identity))
  localStorage.setItem("nozomi:votes", "existing-vote")
  const mount = await browser(t, () => localStorage)
  const hook = mount()
  hook.mounted()
  const regenerated = {...identity, alias: "Hikari-7-Kyoto-E5-Akane"}
  hook.receive(regenerated)

  assert.deepEqual(saved(localStorage), regenerated)
  assert.equal(localStorage.getItem("nozomi:votes"), "existing-vote")
  hook.reconnected()
  const [, restored] = hook.sent.at(-1)
  assert.deepEqual({id: restored.id, alias: restored.alias}, regenerated)
})

test("keeps the stored alias when another tab rewrote it while this tab was open", async t => {
  const localStorage = storage()
  const mount = await browser(t, () => localStorage)
  const tabA = mount()
  tabA.mounted()
  tabA.receive(identity)

  // Tab B mounts while tab A's alias is the stored one, so tab B remembers it.
  const otherTab = await freshPage()
  const tabB = otherTab()
  tabB.mounted()
  assert.equal(tabB.sent.at(-1)[1].alias, identity.alias)

  const regenerated = {...identity, alias: "Kodama-9-Nagoya-E7-Midori"}
  tabA.receive(regenerated)

  tabB.reconnected()
  assert.equal(tabB.sent.at(-1)[1].alias, regenerated.alias)
  assert.deepEqual(saved(localStorage), regenerated)
})

test("a delayed restoration cannot overwrite another tab's regenerated alias", async t => {
  const localStorage = storage()
  const mount = await browser(t, () => localStorage)
  const tabA = mount()
  tabA.mounted()
  tabA.receive(identity)

  const otherTab = await freshPage()
  const tabB = otherTab()
  tabB.mounted()
  assert.equal(tabB.sent.at(-1)[1].alias, identity.alias)

  const regenerated = {...identity, alias: "Kodama-9-Nagoya-E7-Midori"}
  tabA.receive(regenerated)
  const revision = localStorage.getItem(key)

  // Deliver B's old confirmation only after A has saved its new alias.
  tabB.receive({...identity, restored: true})
  assert.equal(localStorage.getItem(key), revision)
  assert.deepEqual(saved(localStorage), regenerated)

  const reload = await freshPage()
  const returning = reload()
  returning.mounted()
  assert.equal(returning.sent.at(-1)[1].alias, regenerated.alias)
  tabB.reconnected()
  assert.equal(tabB.sent.at(-1)[1].alias, regenerated.alias)
})

test("retains identity across hook remounts when access to localStorage is blocked", async t => {
  const mount = await browser(t, () => { throw new Error("Storage is disabled") })
  const first = mount()
  first.mounted()
  first.receive({...identity, restored: true})
  assert.deepEqual(first.sent.at(-1), ["identity_storage", {available: false}])

  const second = mount()
  second.mounted()
  const [, restored] = second.sent.at(-1)
  assert.deepEqual({id: restored.id, alias: restored.alias}, identity)
  second.reconnected()
  const [, reconnected] = second.sent.at(-1)
  assert.deepEqual({id: reconnected.id, alias: reconnected.alias}, identity)
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
  const [, restored] = remount.sent.at(-1)
  assert.deepEqual({id: restored.id, alias: restored.alias}, regenerated)
})

test("recovers from unreadable or malformed stored data without throwing", async t => {
  for (const value of ["{broken", "null", "[]", "42", '"text"']) {
    await t.test(value, async t => {
      const localStorage = storage(value)
      const mount = await browser(t, () => localStorage)
      const hook = mount()
      hook.mounted()
      assert.deepEqual(hook.sent, [["restore_identity", {}]])
      hook.receive({...identity, restored: true})
      assert.deepEqual(saved(localStorage), identity)
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
