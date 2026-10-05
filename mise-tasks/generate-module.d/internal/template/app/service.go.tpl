package app

import (
	"context"
	"uuid"

	"github.com/distributed-programming-2026/go-sdk/pkg/uow"

	domainevent "github.com/distributed-programming-2026/lib/event"

	"template/internal/template/domain"
	"template/internal/template/infra/mysql"
)

type DispatcherFactory interface {
	NewDispatcher(ctx context.Context) domainevent.Dispatcher
}

type Service struct {
	unit              uow.UnitOfWorkWithRepositoryProvider[*mysql.RepositoryProvider]
	dispatcherFactory DispatcherFactory
}

func NewService(
	unit uow.UnitOfWorkWithRepositoryProvider[*mysql.RepositoryProvider],
	dispatcherFactory DispatcherFactory,
) *Service {
	return &Service{
		unit:              unit,
		dispatcherFactory: dispatcherFactory,
	}
}

func (s *Service) Echo(ctx context.Context, body string) (uuid.UUID, error) {
	var id uuid.UUID
	err := s.unit.ExecuteWithRepositoryProvider(ctx, func(provider *mysql.RepositoryProvider) error {
		svc := domain.NewEchoService(
			provider.Echo(ctx),
			s.dispatcherFactory.NewDispatcher(ctx),
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
