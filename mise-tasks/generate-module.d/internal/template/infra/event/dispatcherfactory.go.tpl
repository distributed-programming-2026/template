package event

import (
	"context"

	"github.com/distributed-programming-2026/go-sdk/pkg/event"

	domainevent "github.com/distributed-programming-2026/lib/event"
)

func NewDispatcherFactory(producer string, dispatcher event.Dispatcher) *DispatcherFactory {
	return &DispatcherFactory{
		producer:   producer,
		dispatcher: dispatcher,
	}
}

type DispatcherFactory struct {
	producer   string
	dispatcher event.Dispatcher
}

func (f *DispatcherFactory) NewDispatcher(ctx context.Context) domainevent.Dispatcher {
	return domainevent.NewDispatcherProxy(ctx, f.producer, f.dispatcher)
}
