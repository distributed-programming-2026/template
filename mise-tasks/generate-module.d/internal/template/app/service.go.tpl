package app

import (
	"context"
	"uuid"

	"github.com/distributed-programming-2026/go-sdk/pkg/event"
	"github.com/distributed-programming-2026/go-sdk/pkg/uow"

	domainevent "github.com/distributed-programming-2026/lib/event"

	"template/internal/template/domain"
	"template/internal/template/infra/mysql"
)

type Service struct {
	unit       uow.UnitOfWorkWithRepositoryProvider[*mysql.RepositoryProvider]
	dispatcher event.Dispatcher
	producer   string // todo вынести конструирование dispatcher proxy в фабрику, что бы producer задавался из main. Фабрику сделать на infra
}

func NewService(
	unit uow.UnitOfWorkWithRepositoryProvider[*mysql.RepositoryProvider],
	dispatcher event.Dispatcher,
	producer string,
) *Service {
	return &Service{
		unit:       unit,
		dispatcher: dispatcher,
		producer:   producer,
	}
}

func (s *Service) Echo(ctx context.Context, body string) (uuid.UUID, error) {
	var id uuid.UUID
	err := s.unit.ExecuteWithRepositoryProvider(ctx, func(provider *mysql.RepositoryProvider) error {
		svc := domain.NewEchoService(
			provider.Echo(ctx),
			domainevent.NewDispatcherProxy(ctx, s.producer, s.dispatcher),
		)

		var err error
		id, err = svc.Echo(body)
		return err
	})
	if err != nil {
		return uuid.Nil(), err
	}
	return id, nil
}
