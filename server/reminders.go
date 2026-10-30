package main

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// digestTask is the part of a task the daily digest needs.
type digestTask struct {
	Title    string
	Due      time.Time // zero = no due date
	Assignee string
	Priority string
}

// digestTasks picks the tasks for a user's daily digest: open tasks due
// today or earlier (in the user's local time), only the user's own with
// scope "mine". Highest priority first, then oldest due date.
func digestTasks(tasks []digestTask, userID, scope string, localNow time.Time) []digestTask {
	endOfDay := time.Date(localNow.Year(), localNow.Month(), localNow.Day(), 23, 59, 59, 0, localNow.Location())
	var due []digestTask
	for _, t := range tasks {
		if t.Due.IsZero() || t.Due.In(localNow.Location()).After(endOfDay) {
			continue
		}
		if scope == "mine" && t.Assignee != userID {
			continue
		}
		due = append(due, t)
	}
	// Small n: insertion sort keeps this dependency free and stable.
	for i := 1; i < len(due); i++ {
		for j := i; j > 0 && digestLess(due[j], due[j-1]); j-- {
			due[j], due[j-1] = due[j-1], due[j]
		}
	}
	return due
}

func digestLess(a, b digestTask) bool {
	pa, pb := priorityRank(a.Priority), priorityRank(b.Priority)
	if pa != pb {
		return pa < pb
	}
	return a.Due.Before(b.Due)
}

func priorityRank(p string) int {
	switch p {
	case "A":
		return 0
	case "B":
		return 1
	case "C":
		return 2
	default:
		return 3
	}
}

// digestMessage is the notification text, e.g.
// "Heute zu tun" / "3 Aufgaben: Müll rausbringen, Wäsche, Bad putzen".
func digestMessage(tasks []digestTask) (title, body string) {
	names := make([]string, 0, 3)
	for i, t := range tasks {
		if i == 3 {
			break
		}
		names = append(names, t.Title)
	}
	list := strings.Join(names, ", ")
	if len(tasks) > 3 {
		list += " …"
	}
	if len(tasks) == 1 {
		return "Heute zu tun", list
	}
	return "Heute zu tun", fmt.Sprintf("%d Aufgaben: %s", len(tasks), list)
}

// reminderDue reports whether a user's digest should go out now: the
// configured local time has been reached and none was sent today. A missed
// minute (server down) is caught up later the same day.
func reminderDue(reminderTime, lastSent string, localNow time.Time) bool {
	if reminderTime == "" || lastSent == localNow.Format("2006-01-02") {
		return false
	}
	return localNow.Format("15:04") >= reminderTime
}

func registerReminders(app core.App, sender *fcmSender) {
	app.Cron().MustAdd("casa_daily_digest", "* * * * *", func() {
		sendDueDigests(app, sender, time.Now())
	})
}

func sendDueDigests(app core.App, sender *fcmSender, now time.Time) {
	users, err := app.FindRecordsByFilter("users", "reminder_time != '' && household != ''", "", 0, 0)
	if err != nil {
		app.Logger().Warn("reminders: loading users failed", "error", err)
		return
	}
	for _, user := range users {
		offset := time.Duration(user.GetInt("reminder_tz_offset")) * time.Minute
		localNow := now.UTC().Add(offset).In(time.FixedZone("local", int(offset.Seconds())))
		if !reminderDue(user.GetString("reminder_time"), user.GetString("reminder_last"), localNow) {
			continue
		}
		// Marked first, so a failing push is not retried every minute.
		user.Set("reminder_last", localNow.Format("2006-01-02"))
		if err := app.Save(user); err != nil {
			app.Logger().Warn("reminders: saving user failed", "error", err, "user", user.Id)
			continue
		}

		tasks, err := visibleOpenTasks(app, user)
		if err != nil {
			app.Logger().Warn("reminders: loading tasks failed", "error", err, "user", user.Id)
			continue
		}
		due := digestTasks(tasks, user.Id, user.GetString("reminder_scope"), localNow)
		if len(due) == 0 {
			continue
		}
		title, body := digestMessage(due)
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		err = sender.sendToUser(ctx, user.Id, title, body, map[string]string{"type": "digest"})
		cancel()
		if err != nil {
			app.Logger().Warn("reminders: push failed", "error", err, "user", user.Id)
		}
	}
}

// visibleOpenTasks loads the open tasks of the user's household that the user
// may see (private lists only for their owner).
func visibleOpenTasks(app core.App, user *core.Record) ([]digestTask, error) {
	lists, err := app.FindAllRecords("task_lists", dbx.HashExp{
		"household": user.GetString("household"),
		"deleted":   false,
	})
	if err != nil {
		return nil, err
	}
	var listIDs []any
	for _, l := range lists {
		if !l.GetBool("private") || l.GetString("owner") == user.Id {
			listIDs = append(listIDs, l.Id)
		}
	}
	if len(listIDs) == 0 {
		return nil, nil
	}
	records, err := app.FindAllRecords("tasks",
		dbx.In("list", listIDs...),
		dbx.HashExp{"done": false, "deleted": false},
	)
	if err != nil {
		return nil, err
	}
	tasks := make([]digestTask, 0, len(records))
	for _, r := range records {
		tasks = append(tasks, digestTask{
			Title:    r.GetString("title"),
			Due:      r.GetDateTime("due").Time(),
			Assignee: r.GetString("assignee"),
			Priority: r.GetString("priority"),
		})
	}
	return tasks, nil
}
