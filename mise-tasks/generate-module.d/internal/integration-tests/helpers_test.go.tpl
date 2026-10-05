package integration_tests

import (
	"bytes"
	"encoding/json"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/distributed-programming-2026/go-sdk/pkg/event"
	"github.com/stretchr/testify/require"
	"github.com/testcontainers/testcontainers-go"

	templateevents "template/api/events"
)

type logBuffer struct {
	mu     sync.Mutex
	buffer bytes.Buffer
}

func (b *logBuffer) Accept(log testcontainers.Log) {
	_, _ = b.Write(log.Content)
}

func (b *logBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buffer.Write(p)
}

func (b *logBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buffer.String()
}

func (b *logBuffer) count(message, key, value string) int {
	var count int
	for _, line := range strings.Split(b.String(), "\n") {
		var record map[string]any
		err := json.Unmarshal([]byte(line), &record)
		if err == nil && record["msg"] == message && (key == "" || record[key] == value) {
			count++
		}
	}
	return count
}

func checkEcho(t *testing.T, id, body string) event.Envelope {
	t.Helper()
	client := testEnv.connector.TransactionalClient()
	var stored string
	err := client.GetContext(t.Context(), "test.echo", &stored, "SELECT body FROM echo WHERE id = ?", id)
	require.NoError(t, err)
	require.Equal(t, body, stored)

	var rows []struct {
		Payload []byte `db:"payload"`
	}
	err = client.SelectContext(t.Context(), "test.outbox", &rows, "SELECT payload FROM event_outbox")
	require.NoError(t, err)
	for _, row := range rows {
		envelope, err := event.Unmarshal(row.Payload)
		require.NoError(t, err)
		var echo templateevents.Echo
		err = envelope.UnmarshalPayload(&echo)
		require.NoError(t, err)
		if echo.ID == id {
			require.Equal(t, body, echo.Body)
			require.Equal(t, moduleID, envelope.Producer())
			require.Equal(t, "Echo", envelope.Type())
			require.NotEmpty(t, envelope.ID())
			require.NotEmpty(t, envelope.CorrelationID())
			return envelope
		}
	}
	t.Fatal("echo was committed without an outbox event")
	return event.Envelope{}
}

func waitHandled(t *testing.T, envelope event.Envelope, count int) {
	t.Helper()
	require.Eventually(t, func() bool {
		return testEnv.logs.count("event handling completed", "event_id", envelope.ID()) >= count
	}, 30*time.Second, 20*time.Millisecond)

	var markers int
	err := testEnv.connector.TransactionalClient().GetContext(t.Context(), "test.inbox", &markers,
		"SELECT COUNT(*) FROM event_inbox WHERE consumer = ? AND event_id = ?",
		testEnv.conf.AMQP.Queue, envelope.ID(),
	)
	require.NoError(t, err)
	require.Equal(t, 1, markers)
}
