/// <reference path="../pb_data/types.d.ts" />

// Task priority A (highest) to D. Empty means D, so existing tasks and
// older app versions keep working.
migrate((app) => {
  const tasks = app.findCollectionByNameOrId("tasks")
  tasks.fields.add(new SelectField({
    name: "priority",
    maxSelect: 1,
    values: ["A", "B", "C", "D"],
  }))
  app.save(tasks)
}, (app) => {
  const tasks = app.findCollectionByNameOrId("tasks")
  tasks.fields.removeByName("priority")
  app.save(tasks)
})
