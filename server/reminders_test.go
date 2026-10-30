package main

import (
	"testing"
	"time"
)

func TestReminderDue(t *testing.T) {
	at := func(hm string) time.Time {
		parsed, _ := time.Parse("2006-01-02 15:04", "2026-10-30 "+hm)
		return parsed
	}
	cases := []struct {
		name, time, last, now string
		want                  bool
	}{
		{"off", "", "", "08:00", false},
		{"before", "08:00", "", "07:59", false},
		{"exactly", "08:00", "", "08:00", true},
		{"caught up later", "08:00", "2026-10-29", "11:30", true},
		{"already sent today", "08:00", "2026-10-30", "08:01", false},
	}
	for _, c := range cases {
		if got := reminderDue(c.time, c.last, at(c.now)); got != c.want {
			t.Errorf("%s: got %v, want %v", c.name, got, c.want)
		}
	}
}

func TestDigestTasks(t *testing.T) {
	loc := time.FixedZone("CET", 3600)
	now := time.Date(2026, 10, 30, 8, 0, 0, 0, loc)
	tasks := []digestTask{
		{Title: "Later", Due: now.AddDate(0, 0, 1), Assignee: "me"},
		{Title: "No date", Assignee: "me"},
		{Title: "Overdue D", Due: now.AddDate(0, 0, -2), Assignee: "me", Priority: "D"},
		{Title: "Today A", Due: time.Date(2026, 10, 30, 22, 30, 0, 0, time.UTC), Assignee: "me", Priority: "A"},
		{Title: "Others", Due: now, Assignee: "ben", Priority: "B"},
	}

	mine := digestTasks(tasks, "me", "mine", now)
	if got := titles(mine); got != "Today A,Overdue D" {
		t.Fatalf("mine = %s", got)
	}
	all := digestTasks(tasks, "me", "household", now)
	if got := titles(all); got != "Today A,Others,Overdue D" {
		t.Fatalf("household = %s", got)
	}
}

func TestDigestMessage(t *testing.T) {
	title, body := digestMessage([]digestTask{{Title: "Müll"}})
	if title != "Heute zu tun" || body != "Müll" {
		t.Fatalf("single: %q / %q", title, body)
	}
	_, body = digestMessage([]digestTask{{Title: "A"}, {Title: "B"}, {Title: "C"}, {Title: "D"}})
	if body != "4 Aufgaben: A, B, C …" {
		t.Fatalf("many: %q", body)
	}
}

func titles(tasks []digestTask) string {
	s := ""
	for i, t := range tasks {
		if i > 0 {
			s += ","
		}
		s += t.Title
	}
	return s
}
