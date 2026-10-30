/// <reference path="../pb_data/types.d.ts" />

// Completion log: one entry per checked-off task (recurring tasks get one
// per completion), for the „Verlauf" screen. Visible like the task itself,
// so entries from private lists stay private.

const IN_HOUSEHOLD = '@request.auth.id != "" && @request.auth.household != "" && household = @request.auth.household'
const VISIBLE = '(list.private = false || list.owner = @request.auth.id)'

migrate((app) => {
  const households = app.findCollectionByNameOrId("households")
  const users = app.findCollectionByNameOrId("users")
  const taskLists = app.findCollectionByNameOrId("task_lists")
  const tasks = app.findCollectionByNameOrId("tasks")

  const completions = new Collection({
    type: "base",
    name: "completions",
    listRule: `${IN_HOUSEHOLD} && ${VISIBLE}`,
    viewRule: `${IN_HOUSEHOLD} && ${VISIBLE}`,
    // Everyone logs their own completions, in lists they can see.
    createRule: `${IN_HOUSEHOLD} && ${VISIBLE} && user = @request.auth.id && list.household = @request.auth.household`,
    // Only undo (soft delete) of one's own entries.
    updateRule: `${IN_HOUSEHOLD} && user = @request.auth.id && (@request.body.user:isset = false || @request.body.user = @request.auth.id) && (@request.body.household:isset = false || @request.body.household = @request.auth.household)`,
    deleteRule: `${IN_HOUSEHOLD} && user = @request.auth.id`,
    fields: [
      { name: "household", type: "relation", required: true, collectionId: households.id, maxSelect: 1, cascadeDelete: true },
      { name: "task", type: "relation", collectionId: tasks.id, maxSelect: 1, cascadeDelete: false },
      { name: "list", type: "relation", required: true, collectionId: taskLists.id, maxSelect: 1, cascadeDelete: true },
      { name: "title", type: "text", required: true, max: 200 },
      { name: "user", type: "relation", required: true, collectionId: users.id, maxSelect: 1, cascadeDelete: false },
      { name: "done_at", type: "date", required: true },
      { name: "deleted", type: "bool" },
      { name: "created", type: "autodate", onCreate: true, onUpdate: false },
      { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
    ],
    indexes: [
      "CREATE INDEX idx_completions_sync ON completions (household, updated)",
    ],
  })
  app.save(completions)
}, (app) => {
  app.delete(app.findCollectionByNameOrId("completions"))
})
