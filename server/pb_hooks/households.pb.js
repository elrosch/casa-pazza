/// <reference path="../pb_data/types.d.ts" />

// Household membership is only changed server-side: by creating a household
// or by joining one with its invite code.

// Note: handlers run in isolated contexts, so shared constants are inlined.

onRecordCreateRequest((e) => {
  e.record.set("invite_code", $security.randomStringWithAlphabet(8, "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"))
  e.next()

  const user = e.app.findRecordById("users", e.auth.id)
  user.set("household", e.record.id)
  e.app.save(user)
}, "households")

// Clients may leave their household (set it to ""), but never pick one directly.
onRecordCreateRequest((e) => {
  if (e.record.get("household")) {
    throw new BadRequestError("Use the join endpoint to enter a household.")
  }
  e.next()
}, "users")

onRecordUpdateRequest((e) => {
  const before = e.record.original().get("household")
  const after = e.record.get("household")
  if (after && after !== before && !e.hasSuperuserAuth()) {
    throw new BadRequestError("Use the join endpoint to enter a household.")
  }
  e.next()
}, "users")

routerAdd("POST", "/api/casa/join", (e) => {
  const body = e.requestInfo().body
  const code = String(body.code || "").trim().toUpperCase()
  if (!code) {
    throw new BadRequestError("Missing invite code.")
  }

  let household
  try {
    household = e.app.findFirstRecordByData("households", "invite_code", code)
  } catch (_) {
    throw new NotFoundError("Unknown invite code.")
  }

  const user = e.app.findRecordById("users", e.auth.id)
  user.set("household", household.id)
  e.app.save(user)

  return e.json(200, { household: household.id, name: household.get("name") })
}, $apis.requireAuth("users"))

// Regenerates the invite code, e.g. after it was shared too widely.
routerAdd("POST", "/api/casa/invite-code", (e) => {
  const householdId = e.auth.get("household")
  if (!householdId) {
    throw new BadRequestError("Not in a household.")
  }
  const household = e.app.findRecordById("households", householdId)
  household.set("invite_code", $security.randomStringWithAlphabet(8, "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"))
  e.app.save(household)
  return e.json(200, { invite_code: household.get("invite_code") })
}, $apis.requireAuth("users"))
