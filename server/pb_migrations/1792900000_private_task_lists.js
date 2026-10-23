/// <reference path="../pb_data/types.d.ts" />

// Private task lists: visible only to their owner, together with their tasks.
//
// - Lists get an `owner` (set on creation) and a `private` flag.
// - Only the owner may make a list private or shared again. An ownerless
//   (older) list can be claimed by setting `owner` to oneself.
// - Tasks of a private list are only visible to the owner and can only be
//   assigned to the owner.

const VISIBLE_LIST = '(private = false || owner = @request.auth.id)'
const VISIBLE_TASK = '(list.private = false || list.owner = @request.auth.id)'

const LIST_CREATE =
  '(owner = "" || owner = @request.auth.id) && (private = false || owner = @request.auth.id)'

const LIST_UPDATE = [
  VISIBLE_LIST,
  // Ownership only moves from nobody to the caller.
  '(@request.body.owner:isset = false || @request.body.owner = owner || (@request.body.owner = @request.auth.id && owner = ""))',
  // Visibility only changes by the (current or claiming) owner …
  '(@request.body.private:isset = false || @request.body.private = private || owner = @request.auth.id || (owner = "" && @request.body.owner = @request.auth.id))',
  // … and a private list always ends up owned by the caller.
  '(@request.body.private != true || @request.body.owner = @request.auth.id || (@request.body.owner:isset = false && owner = @request.auth.id))',
].join(' && ')

const TASK_CREATE = [
  VISIBLE_TASK,
  '(list.private = false || @request.body.assignee:isset = false || @request.body.assignee = "" || @request.body.assignee = @request.auth.id)',
].join(' && ')

const TASK_UPDATE = [
  VISIBLE_TASK,
  // Tasks stay in their list, so they cannot be moved into a foreign private list.
  '(@request.body.list:isset = false || @request.body.list = list)',
  '(list.private = false || @request.body.assignee:isset = false || @request.body.assignee = "" || @request.body.assignee = @request.auth.id)',
].join(' && ')

migrate((app) => {
  const users = app.findCollectionByNameOrId("users")
  const lists = app.findCollectionByNameOrId("task_lists")
  lists.fields.add(new BoolField({ name: "private" }))
  lists.fields.add(new RelationField({
    name: "owner",
    collectionId: users.id,
    maxSelect: 1,
    cascadeDelete: false,
  }))
  lists.listRule = `${lists.listRule} && ${VISIBLE_LIST}`
  lists.viewRule = `${lists.viewRule} && ${VISIBLE_LIST}`
  lists.createRule = `${lists.createRule} && ${LIST_CREATE}`
  lists.updateRule = `${lists.updateRule} && ${LIST_UPDATE}`
  lists.deleteRule = `${lists.deleteRule} && ${VISIBLE_LIST}`
  app.save(lists)

  const tasks = app.findCollectionByNameOrId("tasks")
  tasks.listRule = `${tasks.listRule} && ${VISIBLE_TASK}`
  tasks.viewRule = `${tasks.viewRule} && ${VISIBLE_TASK}`
  tasks.createRule = `${tasks.createRule} && ${TASK_CREATE}`
  tasks.updateRule = `${tasks.updateRule} && ${TASK_UPDATE}`
  tasks.deleteRule = `${tasks.deleteRule} && ${VISIBLE_TASK}`
  app.save(tasks)
}, (app) => {
  const strip = (rule, ...parts) => parts.reduce((r, p) => r.replace(` && ${p}`, ""), rule)

  const tasks = app.findCollectionByNameOrId("tasks")
  tasks.listRule = strip(tasks.listRule, VISIBLE_TASK)
  tasks.viewRule = strip(tasks.viewRule, VISIBLE_TASK)
  tasks.createRule = strip(tasks.createRule, TASK_CREATE)
  tasks.updateRule = strip(tasks.updateRule, TASK_UPDATE)
  tasks.deleteRule = strip(tasks.deleteRule, VISIBLE_TASK)
  app.save(tasks)

  const lists = app.findCollectionByNameOrId("task_lists")
  lists.listRule = strip(lists.listRule, VISIBLE_LIST)
  lists.viewRule = strip(lists.viewRule, VISIBLE_LIST)
  lists.createRule = strip(lists.createRule, LIST_CREATE)
  lists.updateRule = strip(lists.updateRule, LIST_UPDATE)
  lists.deleteRule = strip(lists.deleteRule, VISIBLE_LIST)
  lists.fields.removeByName("private")
  lists.fields.removeByName("owner")
  app.save(lists)
})
