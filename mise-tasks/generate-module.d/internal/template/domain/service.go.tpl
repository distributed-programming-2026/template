package domain

import (
	"uuid"

	"github.com/distributed-programming-2026/lib/event"

	templateevents "template/api/events"
)

type EchoService struct {
	repo       EchoRepository
	dispatcher event.Dispatcher
}

func NewEchoService(repo EchoRepository, dispatcher event.Dispatcher) *EchoService {
	return &EchoService{
		repo:       repo,
		dispatcher: dispatcher,
	}
}

func (s *EchoService) Echo(body string) (uuid.UUID, error) {
	id, err := s.repo.NextID()
	if err != nil {
		return uuid.Nil(), err
	}

	e := Echo{
		ID:   id,
		Body: body,
	}

	err = s.repo.Store(e)
	if err != nil {
		return uuid.Nil(), err
	}

	err = s.dispatcher.Dispatch(&templateevents.Echo{
		ID:   e.ID.String(),
		Body: e.Body,
	})
	if err != nil {
		return uuid.Nil(), err
	}
	return id, nil
}
