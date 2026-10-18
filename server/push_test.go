package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestShouldNotify(t *testing.T) {
	cases := []struct {
		name                 string
		before, after, actor string
		done, deleted        bool
		want                 bool
	}{
		{"new assignment by someone else", "", "ben", "anna", false, false, true},
		{"reassigned", "anna", "ben", "anna", false, false, true},
		{"unchanged on sync", "ben", "ben", "anna", false, false, false},
		{"assigned to oneself", "", "anna", "anna", false, false, false},
		{"unassigned", "ben", "", "anna", false, false, false},
		{"already done", "", "ben", "anna", true, false, false},
		{"deleted", "", "ben", "anna", false, true, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := shouldNotify(c.before, c.after, c.actor, c.done, c.deleted); got != c.want {
				t.Fatalf("shouldNotify = %v, want %v", got, c.want)
			}
		})
	}
}

func TestAssignmentMessage(t *testing.T) {
	title, body := assignmentMessage("Anna", "Müll rausbringen")
	if title != "Neue Aufgabe für dich" || body != "Anna: Müll rausbringen" {
		t.Fatalf("got %q / %q", title, body)
	}
}

func TestSendFCM(t *testing.T) {
	var got fcmMessage
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/projects/demo/messages:send" {
			t.Errorf("unexpected path %s", r.URL.Path)
		}
		_ = json.NewDecoder(r.Body).Decode(&got)
		switch got.Message.Token {
		case "gone":
			w.WriteHeader(http.StatusNotFound)
			_, _ = w.Write([]byte(`{"error":{"status":"NOT_FOUND","details":[{"errorCode":"UNREGISTERED"}]}}`))
		case "broken":
			w.WriteHeader(http.StatusInternalServerError)
		default:
			_, _ = w.Write([]byte(`{"name":"projects/demo/messages/1"}`))
		}
	}))
	defer server.Close()
	fcmBaseURL = server.URL

	ctx := context.Background()
	data := map[string]string{"type": "task_assigned", "task_id": "t1"}
	if err := sendFCM(ctx, server.Client(), "demo", "ok", "T", "B", data); err != nil {
		t.Fatal(err)
	}
	if got.Message.Notification.Body != "B" || got.Message.Data["task_id"] != "t1" ||
		got.Message.Android.Priority != "HIGH" || got.Message.Android.Notification.Tag != "t1" {
		t.Fatalf("unexpected message %+v", got)
	}
	if err := sendFCM(ctx, server.Client(), "demo", "gone", "T", "B", data); !errors.Is(err, errTokenGone) {
		t.Fatalf("want errTokenGone, got %v", err)
	}
	if err := sendFCM(ctx, server.Client(), "demo", "broken", "T", "B", data); err == nil || errors.Is(err, errTokenGone) {
		t.Fatalf("want generic error, got %v", err)
	}
}
