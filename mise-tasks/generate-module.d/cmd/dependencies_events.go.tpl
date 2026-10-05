package main

import (
	"log/slog"

	"github.com/distributed-programming-2026/go-sdk/pkg/amqp"
	"github.com/distributed-programming-2026/go-sdk/pkg/event"
	eventamqp "github.com/distributed-programming-2026/go-sdk/pkg/event/amqp"
	"github.com/distributed-programming-2026/go-sdk/pkg/event/inbox"
	"github.com/distributed-programming-2026/go-sdk/pkg/event/outbox"
	"github.com/distributed-programming-2026/go-sdk/pkg/uow"

	domainevent "github.com/distributed-programming-2026/lib/event"

	"template/internal/template/config"
	eventhandler "template/internal/template/infra/handlers/events"
)

func newDispatcher(logger *slog.Logger, conf config.Env, db *database, connection amqp.Connection) (event.Dispatcher, *outbox.Relay, error) {
	// Declare the durable queue before publishing, even if the consumer is offline.
	producer := connection.Producer(domainevent.DomainExchange(), eventQueue(conf), eventBinding(conf))
	transport, err := eventamqp.NewDispatcher(producer)
	if err != nil {
		return nil, nil, err
	}

	return outbox.Decorate(
		event.ChainDispatcher(transport, event.DispatcherLogging(logger)),
		uow.NewLockableUnitOfWork(db.unit),
		outbox.Config{
			Transport:   "rabbitmq",
			BatchSize:   conf.Relay.BatchSize,
			LockTimeout: conf.Relay.LockTimeout,
		},
	)
}

func newMessageHandler(logger *slog.Logger, conf config.Env, db *database) (amqp.Handler, error) {
	handler, _, err := inbox.Decorate(eventhandler.NewHandler(logger), db.unit, inbox.Config{
		Consumer: conf.AMQP.Queue,
	})
	if err != nil {
		return nil, err
	}

	return eventamqp.NewHandler(event.ChainHandler(handler, event.HandlerLogging(logger)))
}
