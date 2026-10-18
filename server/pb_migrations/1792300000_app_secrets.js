/// <reference path="../pb_data/types.d.ts" />

// Server-side secrets, editable only by superusers in the dashboard.
// Holds the Firebase service account under key "fcm_service_account".
migrate((app) => {
  const secrets = new Collection({
    type: "base",
    name: "app_secrets",
    listRule: null,
    viewRule: null,
    createRule: null,
    updateRule: null,
    deleteRule: null,
    fields: [
      { name: "key", type: "text", required: true, max: 100 },
      { name: "value", type: "text", max: 20000 },
      { name: "created", type: "autodate", onCreate: true, onUpdate: false },
      { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
    ],
    indexes: ["CREATE UNIQUE INDEX idx_app_secrets_key ON app_secrets (key)"],
  })
  app.save(secrets)

  const record = new Record(secrets)
  record.set("key", "fcm_service_account")
  record.set("value", "")
  app.save(record)
}, (app) => {
  app.delete(app.findCollectionByNameOrId("app_secrets"))
})
