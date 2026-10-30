/// <reference path="../pb_data/types.d.ts" />

// Daily task digest per user (see reminders.go):
// - reminder_time: "HH:MM" in the user's local time, empty = off
// - reminder_scope: "mine" (assigned to me) or "household" (all visible)
// - reminder_tz_offset: minutes east of UTC, reported by the app
// - reminder_last: local date of the last digest, so it is sent once a day
migrate((app) => {
  const users = app.findCollectionByNameOrId("users")
  users.fields.add(new TextField({ name: "reminder_time", max: 5, pattern: "^([01][0-9]|2[0-3]):[0-5][0-9]$|^$" }))
  users.fields.add(new SelectField({ name: "reminder_scope", maxSelect: 1, values: ["mine", "household"] }))
  users.fields.add(new NumberField({ name: "reminder_tz_offset", onlyInt: true, min: -840, max: 840 }))
  users.fields.add(new TextField({ name: "reminder_last", max: 10 }))
  app.save(users)
}, (app) => {
  const users = app.findCollectionByNameOrId("users")
  for (const name of ["reminder_time", "reminder_scope", "reminder_tz_offset", "reminder_last"]) {
    users.fields.removeByName(name)
  }
  app.save(users)
})
