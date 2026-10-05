package event

import (
	"context"
	"fmt"

	"github.com/distributed-programming-2026/go-sdk/pkg/event"
	"google.golang.org/protobuf/proto"
)

type Dispatcher interface {
	Dispatch(message proto.Message) error
}

func NewDispatcherProxy(ctx context.Context, producer string, d event.Dispatcher) Dispatcher {
	return &dispatcherProxy{
		ctx:      ctx,
		producer: producer,
		d:        d,
	}
}

type dispatcherProxy struct {
	ctx      context.Context
	producer string
	d        event.Dispatcher
}

func (d dispatcherProxy) Dispatch(message proto.Message) error {
	envelope, err := event.New(d.ctx, d.producer, string(message.ProtoReflect().Type().Descriptor().Name()), message)
	if err != nil {
		return fmt.Errorf("create envelope: %w", err)
	}
	return d.d.Dispatch(d.ctx, envelope)
}
