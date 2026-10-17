/// <reference path="../pb_data/types.d.ts" />

// Initial Casa Pazza schema.
//
// Every user belongs to at most one household (users.household). All shared
// data carries a `household` relation so the API rules stay simple, plus a
// `deleted` flag (soft delete) and `updated` timestamp for offline sync.

const IN_HOUSEHOLD = '@request.auth.id != "" && @request.auth.household != "" && household = @request.auth.household'
const KEEP_HOUSEHOLD = '(@request.body.household:isset = false || @request.body.household = @request.auth.household)'

function timestamps() {
  return [
    { name: "created", type: "autodate", onCreate: true, onUpdate: false },
    { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
  ]
}

function householdRules(extraCreate) {
  const create = extraCreate ? `${IN_HOUSEHOLD} && ${extraCreate}` : IN_HOUSEHOLD
  return {
    listRule: IN_HOUSEHOLD,
    viewRule: IN_HOUSEHOLD,
    createRule: create,
    updateRule: `${IN_HOUSEHOLD} && ${KEEP_HOUSEHOLD}`,
    deleteRule: IN_HOUSEHOLD,
  }
}

migrate((app) => {
  const users = app.findCollectionByNameOrId("users")

  const households = new Collection({
    type: "base",
    name: "households",
    listRule: 'id = @request.auth.household',
    viewRule: 'id = @request.auth.household',
    // Only users without a household may create one (hook assigns them to it).
    createRule: '@request.auth.id != "" && @request.auth.household = ""',
    updateRule: 'id = @request.auth.household',
    deleteRule: null,
    fields: [
      { name: "name", type: "text", required: true, max: 100 },
      { name: "invite_code", type: "text", max: 16 },
      ...timestamps(),
    ],
    indexes: [
      "CREATE UNIQUE INDEX idx_households_invite_code ON households (invite_code) WHERE invite_code != ''",
    ],
  })
  app.save(households)

  users.fields.add(new RelationField({
    name: "household",
    collectionId: households.id,
    maxSelect: 1,
    cascadeDelete: false,
  }))
  // Members of the same household can see each other (names for assignment).
  users.listRule = 'id = @request.auth.id || (household != "" && household = @request.auth.household)'
  users.viewRule = users.listRule
  app.save(users)

  const relHousehold = { name: "household", type: "relation", required: true, collectionId: households.id, maxSelect: 1, cascadeDelete: true }
  const relUser = (name) => ({ name, type: "relation", collectionId: users.id, maxSelect: 1, cascadeDelete: false })

  const taskLists = new Collection({
    type: "base",
    name: "task_lists",
    ...householdRules(),
    fields: [
      relHousehold,
      { name: "name", type: "text", required: true, max: 100 },
      { name: "color", type: "text", max: 16 },
      { name: "sort", type: "number" },
      { name: "deleted", type: "bool" },
      ...timestamps(),
    ],
    indexes: ["CREATE INDEX idx_task_lists_sync ON task_lists (household, updated)"],
  })
  app.save(taskLists)

  const tasks = new Collection({
    type: "base",
    name: "tasks",
    ...householdRules(
      'list.household = @request.auth.household && (@request.body.assignee:isset = false || @request.body.assignee = "" || @request.body.assignee.household = @request.auth.household)'
    ),
    fields: [
      relHousehold,
      { name: "list", type: "relation", required: true, collectionId: taskLists.id, maxSelect: 1, cascadeDelete: true },
      { name: "title", type: "text", required: true, max: 200 },
      { name: "notes", type: "text", max: 2000 },
      relUser("assignee"),
      { name: "due", type: "date" },
      // Recurrence: empty unit = one-off task; otherwise repeats every N units.
      { name: "repeat_unit", type: "select", maxSelect: 1, values: ["day", "week", "month", "year"] },
      { name: "repeat_every", type: "number", min: 0, onlyInt: true },
      { name: "done", type: "bool" },
      { name: "done_at", type: "date" },
      relUser("done_by"),
      relUser("created_by"),
      { name: "deleted", type: "bool" },
      ...timestamps(),
    ],
    indexes: [
      "CREATE INDEX idx_tasks_sync ON tasks (household, updated)",
      "CREATE INDEX idx_tasks_assignee ON tasks (assignee, done)",
    ],
  })
  app.save(tasks)

  const shoppingLists = new Collection({
    type: "base",
    name: "shopping_lists",
    ...householdRules(),
    fields: [
      relHousehold,
      { name: "name", type: "text", required: true, max: 100 },
      { name: "sort", type: "number" },
      { name: "deleted", type: "bool" },
      ...timestamps(),
    ],
    indexes: ["CREATE INDEX idx_shopping_lists_sync ON shopping_lists (household, updated)"],
  })
  app.save(shoppingLists)

  const shoppingItems = new Collection({
    type: "base",
    name: "shopping_items",
    ...householdRules('list.household = @request.auth.household'),
    fields: [
      relHousehold,
      { name: "list", type: "relation", required: true, collectionId: shoppingLists.id, maxSelect: 1, cascadeDelete: true },
      { name: "name", type: "text", required: true, max: 200 },
      { name: "quantity", type: "text", max: 50 },
      { name: "checked", type: "bool" },
      relUser("checked_by"),
      { name: "sort", type: "number" },
      { name: "deleted", type: "bool" },
      ...timestamps(),
    ],
    indexes: ["CREATE INDEX idx_shopping_items_sync ON shopping_items (household, updated)"],
  })
  app.save(shoppingItems)

  // Push tokens (FCM) per device, private to their owner.
  const devices = new Collection({
    type: "base",
    name: "devices",
    listRule: 'user = @request.auth.id',
    viewRule: 'user = @request.auth.id',
    createRule: '@request.auth.id != "" && user = @request.auth.id',
    updateRule: 'user = @request.auth.id && (@request.body.user:isset = false || @request.body.user = @request.auth.id)',
    deleteRule: 'user = @request.auth.id',
    fields: [
      { name: "user", type: "relation", required: true, collectionId: users.id, maxSelect: 1, cascadeDelete: true },
      { name: "token", type: "text", required: true, max: 4096 },
      { name: "platform", type: "select", maxSelect: 1, values: ["android", "ios"] },
      ...timestamps(),
    ],
    indexes: ["CREATE UNIQUE INDEX idx_devices_token ON devices (token)"],
  })
  app.save(devices)
}, (app) => {
  for (const name of ["devices", "shopping_items", "shopping_lists", "tasks", "task_lists"]) {
    app.delete(app.findCollectionByNameOrId(name))
  }
  const users = app.findCollectionByNameOrId("users")
  users.fields.removeByName("household")
  users.listRule = "id = @request.auth.id"
  users.viewRule = "id = @request.auth.id"
  app.save(users)
  app.delete(app.findCollectionByNameOrId("households"))
})
