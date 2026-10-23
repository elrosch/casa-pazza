/// <reference path="../pb_data/types.d.ts" />

// When a list becomes shared again, the other members fetch it by its new
// `updated` timestamp, but its tasks are older than their sync cursor.
// Touching the tasks bumps their timestamps so they are pulled as well.
onRecordUpdateRequest((e) => {
  const wasPrivate = e.record.original().getBool("private")
  e.next()

  if (wasPrivate === e.record.getBool("private")) return
  const tasks = e.app.findAllRecords("tasks", $dbx.hashExp({ list: e.record.id }))
  for (const task of tasks) {
    e.app.save(task)
  }
}, "task_lists")
