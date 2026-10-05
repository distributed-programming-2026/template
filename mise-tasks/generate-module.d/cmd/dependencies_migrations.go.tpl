package main

import (
	"context"
	"log/slog"

	"github.com/distributed-programming-2026/go-sdk/pkg/event/inbox"
	"github.com/distributed-programming-2026/go-sdk/pkg/event/outbox"
	"github.com/distributed-programming-2026/go-sdk/pkg/migrator"
	"github.com/distributed-programming-2026/go-sdk/pkg/mysql"

	"template/internal/template/infra/mysql/migrations"
)

func migrateDatabase(ctx context.Context, logger *slog.Logger, client mysql.TransactionalClient) error {
	runner, err := migrator.New(client, logger)
	if err != nil {
		return err
	}

	targets := []struct {
		name       string
		migrations []migrator.Migration
	}{
		{
			name:       appID,
			migrations: migrations.Database(client),
		},
		{
			name:       "event-outbox",
			migrations: outbox.Migrations(client),
		},
		{
			name:       "event-inbox",
			migrations: inbox.Migrations(client),
		},
	}

	for _, target := range targets {
		err = runner.Migrate(ctx, target.name, target.migrations...)
		if err != nil {
			return err
		}
	}
	return nil
}
