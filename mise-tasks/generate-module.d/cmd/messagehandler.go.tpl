package main

import (
	"context"
	"errors"
	"log/slog"

	"github.com/distributed-programming-2026/go-sdk/pkg/amqp"
	"github.com/urfave/cli/v3"

	domainevent "github.com/distributed-programming-2026/lib/event"
	"github.com/distributed-programming-2026/lib/runtime/http"

	"template/internal/template/config"
)

func (a *application) messageHandlerCmd() *cli.Command {
	return &cli.Command{
		Name: "message-handler",
		Action: func(ctx context.Context, _ *cli.Command) error {
			return messageHandler(ctx, a.logger, a.conf)
		},
	}
}

func messageHandler(ctx context.Context, logger *slog.Logger, conf config.Env) (err error) {
	db, err := openDatabase(ctx, logger, conf)
	if err != nil {
		return err
	}
	defer func() {
		err = errors.Join(err, db.connector.Close())
	}()

	handler, err := newMessageHandler(logger, conf, db)
	if err != nil {
		return err
	}

	consumerCtx, cancel := context.WithCancel(ctx)
	defer cancel()

	connection := newConnection(logger, conf)
	defer func() {
		err = errors.Join(err, connection.Stop())
	}()

	consumer := connection.Consumer(
		consumerCtx,
		handler,
		domainevent.DomainExchange(),
		eventQueue(conf),
		eventBinding(conf),
		&amqp.QoSConfig{
			PrefetchCount: conf.AMQP.PrefetchCount,
		},
	)
	defer func() {
		cancel()
		closeCtx, closeCancel := context.WithTimeout(context.Background(), conf.App.GraceTimeout)
		defer closeCancel()

		err = errors.Join(err, consumer.Close(closeCtx))
	}()

	err = connection.Start()
	if err != nil {
		return err
	}

	server, err := http.NewServer(http.Config{
		Address:      conf.HTTP.Address,
		GraceTimeout: conf.App.GraceTimeout,
	})
	if err != nil {
		return err
	}
	return server.Serve(ctx)
}
