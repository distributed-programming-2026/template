package repository

import (
	"context"
	"uuid"

	"github.com/distributed-programming-2026/go-sdk/pkg/mysql"

	"template/internal/template/domain"
)

func NewEchoRepository(ctx context.Context, client mysql.ClientContext) domain.EchoRepository {
	return &echoRepository{
		ctx:    ctx,
		client: client,
	}
}

type echoRepository struct {
	ctx    context.Context
	client mysql.ClientContext
}

func (r *echoRepository) NextID() (uuid.UUID, error) {
	return uuid.New(), nil
}

func (r *echoRepository) Store(e domain.Echo) error {
	_, err := r.client.ExecContext(r.ctx, "echo.store", `
INSERT INTO echo (id, body) VALUES (?, ?)
`, e.ID.String(), e.Body)
	return err
}
