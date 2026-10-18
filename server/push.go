package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"sync"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
)

// The Firebase service account JSON is stored by a superuser in the
// app_secrets collection (PocketBase dashboard), so no file or environment
// variable is needed on the NAS.
const serviceAccountKey = "fcm_service_account"

const fcmScope = "https://www.googleapis.com/auth/firebase.messaging"

// fcmBaseURL can be overridden for local end-to-end tests.
var fcmBaseURL = envOr("CASA_FCM_BASE_URL", "https://fcm.googleapis.com")

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// shouldNotify reports whether a task change assigns it to someone new who
// should be told. Re-syncing unchanged tasks, completing them or assigning
// to oneself does not notify.
func shouldNotify(before, after, actorID string, done, deleted bool) bool {
	return after != "" && after != before && after != actorID && !done && !deleted
}

// assignmentMessage is the notification text shown on the assignee's phone.
func assignmentMessage(actorName, taskTitle string) (title, body string) {
	if actorName == "" {
		return "Neue Aufgabe für dich", taskTitle
	}
	return "Neue Aufgabe für dich", fmt.Sprintf("%s: %s", actorName, taskTitle)
}

func registerPush(app core.App) {
	sender := &fcmSender{app: app}

	app.OnRecordCreateRequest("tasks").BindFunc(func(e *core.RecordRequestEvent) error {
		if err := e.Next(); err != nil {
			return err
		}
		sender.notifyAssignment(e.Record, "", e.Auth)
		return nil
	})

	app.OnRecordUpdateRequest("tasks").BindFunc(func(e *core.RecordRequestEvent) error {
		before := e.Record.Original().GetString("assignee")
		if err := e.Next(); err != nil {
			return err
		}
		sender.notifyAssignment(e.Record, before, e.Auth)
		return nil
	})

	// A phone keeps its FCM token across logins: move it to the new user
	// instead of failing on the unique index.
	app.OnRecordCreateRequest("devices").BindFunc(func(e *core.RecordRequestEvent) error {
		existing, _ := e.App.FindAllRecords("devices", dbx.HashExp{"token": e.Record.GetString("token")})
		for _, r := range existing {
			if err := e.App.Delete(r); err != nil {
				return err
			}
		}
		return e.Next()
	})
}

type fcmSender struct {
	app core.App

	mu        sync.Mutex
	rawConfig string
	projectID string
	client    *http.Client
}

func (s *fcmSender) notifyAssignment(task *core.Record, before string, actor *core.Record) {
	actorID, actorName := "", ""
	if actor != nil {
		actorID, actorName = actor.Id, actor.GetString("name")
	}
	assignee := task.GetString("assignee")
	if !shouldNotify(before, assignee, actorID, task.GetBool("done"), task.GetBool("deleted")) {
		return
	}

	title, body := assignmentMessage(actorName, task.GetString("title"))
	data := map[string]string{"type": "task_assigned", "task_id": task.Id}

	// Do not hold up the request; FCM may take a moment.
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		if err := s.sendToUser(ctx, assignee, title, body, data); err != nil {
			s.app.Logger().Warn("push notification failed", "error", err, "task", task.Id)
		}
	}()
}

func (s *fcmSender) sendToUser(ctx context.Context, userID, title, body string, data map[string]string) error {
	devices, err := s.app.FindAllRecords("devices", dbx.HashExp{"user": userID})
	if err != nil || len(devices) == 0 {
		return err
	}
	client, projectID, err := s.httpClient(ctx)
	if err != nil {
		return err
	}

	var errs []error
	for _, device := range devices {
		err := sendFCM(ctx, client, projectID, device.GetString("token"), title, body, data)
		if errors.Is(err, errTokenGone) {
			// Uninstalled app or revoked token: forget the device.
			_ = s.app.Delete(device)
			continue
		}
		if err != nil {
			errs = append(errs, err)
		}
	}
	return errors.Join(errs...)
}

// httpClient returns an OAuth client for the stored service account,
// rebuilding it when the stored JSON changed.
func (s *fcmSender) httpClient(ctx context.Context) (*http.Client, string, error) {
	record, err := s.app.FindFirstRecordByData("app_secrets", "key", serviceAccountKey)
	if err != nil {
		return nil, "", fmt.Errorf("no %q in app_secrets: %w", serviceAccountKey, err)
	}
	raw := record.GetString("value")

	s.mu.Lock()
	defer s.mu.Unlock()
	if s.client != nil && raw == s.rawConfig {
		return s.client, s.projectID, nil
	}
	creds, err := google.CredentialsFromJSONWithType(context.Background(), []byte(raw), google.ServiceAccount, fcmScope)
	if err != nil {
		return nil, "", fmt.Errorf("invalid service account: %w", err)
	}
	if creds.ProjectID == "" {
		return nil, "", errors.New("service account without project_id")
	}
	s.rawConfig = raw
	s.projectID = creds.ProjectID
	s.client = oauth2.NewClient(context.Background(), creds.TokenSource)
	return s.client, s.projectID, nil
}

var errTokenGone = errors.New("fcm token no longer valid")

type fcmMessage struct {
	Message struct {
		Token        string            `json:"token"`
		Notification fcmNotification   `json:"notification"`
		Data         map[string]string `json:"data,omitempty"`
		Android      fcmAndroid        `json:"android"`
	} `json:"message"`
}

type fcmNotification struct {
	Title string `json:"title"`
	Body  string `json:"body"`
}

type fcmAndroid struct {
	Priority     string `json:"priority"`
	Notification struct {
		Tag string `json:"tag,omitempty"`
	} `json:"notification"`
}

func sendFCM(ctx context.Context, client *http.Client, projectID, token, title, body string, data map[string]string) error {
	var msg fcmMessage
	msg.Message.Token = token
	msg.Message.Notification = fcmNotification{Title: title, Body: body}
	msg.Message.Data = data
	msg.Message.Android.Priority = "HIGH"
	// One notification per task, a re-assignment replaces the old one.
	msg.Message.Android.Notification.Tag = data["task_id"]

	payload, err := json.Marshal(msg)
	if err != nil {
		return err
	}
	url := fmt.Sprintf("%s/v1/projects/%s/messages:send", fcmBaseURL, projectID)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusOK {
		return nil
	}
	respBody, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	if resp.StatusCode == http.StatusNotFound || bytes.Contains(respBody, []byte("UNREGISTERED")) {
		return errTokenGone
	}
	return fmt.Errorf("fcm: %s: %s", resp.Status, respBody)
}
