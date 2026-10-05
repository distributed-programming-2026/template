package internalapi

import (
	"context"
	"log/slog"

	"github.com/distributed-programming-2026/go-sdk/pkg/logging"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	templateinternalapi "template/api/server/internalapi"
	"template/internal/template/app"
)

func NewHandler(svc *app.Service, logger *slog.Logger) templateinternalapi.TemplateServiceServer {
	return &handler{
		svc:    svc,
		logger: logger,
	}
}

type handler struct {
	svc    *app.Service
	logger *slog.Logger
	templateinternalapi.UnimplementedTemplateServiceServer
}

func (h handler) Echo(ctx context.Context, req *templateinternalapi.EchoRequest) (*templateinternalapi.EchoResponse, error) {
	id, err := h.svc.Echo(ctx, req.Body)
	if err != nil {
		h.logger.ErrorContext(ctx, "echo failed", logging.Error(err))
		return nil, status.Error(codes.Internal, "echo failed")
	}

	return &templateinternalapi.EchoResponse{
		OperationID: id.String(),
	}, nil
}
