package events

import (
	"context"
	"fmt"
	"log/slog"

	templateevents "template/api/events"

	"github.com/distributed-programming-2026/go-sdk/pkg/event"
)

type handler struct {
	logger *slog.Logger
}

func NewHandler(logger *slog.Logger) event.Handler {
	return &handler{
		logger: logger,
	}
}

func (h *handler) Handle(ctx context.Context, envelope event.Envelope) error {
	if envelope.Type() != "Echo" {
		return fmt.Errorf("unsupported event type %q", envelope.Type())
	}
	var echo templateevents.Echo
	err := envelope.UnmarshalPayload(&echo)
	if err != nil {
		return err
	}
	h.logger.InfoContext(ctx, "echo received", slog.String("echo_id", echo.ID), slog.String("body", echo.Body))
	return nil
}
