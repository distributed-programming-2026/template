package main

import (
	"context"
	"log/slog"
	"time"

	"github.com/distributed-programming-2026/go-sdk/pkg/event/outbox"
	"github.com/distributed-programming-2026/go-sdk/pkg/logging"

	"template/internal/template/config"
)

func runRelay(ctx context.Context, logger *slog.Logger, relay *outbox.Relay, conf config.Relay) error {
	ticker := time.NewTicker(conf.Interval)
	defer ticker.Stop()

	for {
		if ctx.Err() != nil {
			return nil
		}

		batchCtx, cancel := context.WithTimeout(ctx, conf.PublishTimeout)
		_, err := relay.ProcessBatch(batchCtx)
		cancel()
		if err != nil && ctx.Err() == nil {
			logger.Error("outbox publication failed; will retry", logging.Error(err))
		}

		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
		}
	}
}
