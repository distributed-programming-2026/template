package http

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
)

type Config struct {
	Address           string
	GraceTimeout      time.Duration
	ReadHeaderTimeout time.Duration
}

type RegisterFunc func(chi.Router) error

func NewServer(c Config, registers ...RegisterFunc) (*Server, error) {
	if c.GraceTimeout <= 0 {
		return nil, errors.New("HTTP grace timeout must be positive")
	}
	if c.ReadHeaderTimeout == 0 {
		c.ReadHeaderTimeout = 5 * time.Second
	}

	router := chi.NewRouter()
	router.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	})

	for _, register := range registers {
		if register == nil {
			return nil, errors.New("HTTP register function must not be nil")
		}

		err := register(router)
		if err != nil {
			return nil, err
		}
	}

	return &Server{
		graceTimeout: c.GraceTimeout,
		srv: &http.Server{
			Addr:              c.Address,
			Handler:           router,
			ReadHeaderTimeout: c.ReadHeaderTimeout,
		},
	}, nil
}

type Server struct {
	graceTimeout time.Duration
	srv          *http.Server
}

func (s *Server) Serve(ctx context.Context) error {
	listener, err := net.Listen("tcp", s.srv.Addr)
	if err != nil {
		return err
	}

	done := make(chan error, 1)
	go func() {
		done <- s.srv.Serve(listener)
	}()

	select {
	case err = <-done:
		return serveError(err)
	case <-ctx.Done():
		shutdownCtx, cancel := context.WithTimeout(context.Background(), s.graceTimeout)
		defer cancel()

		err = s.srv.Shutdown(shutdownCtx)
		if err != nil {
			err = errors.Join(fmt.Errorf("HTTP graceful shutdown: %w", err), s.srv.Close())
		}
		return errors.Join(err, serveError(<-done))
	}
}

func serveError(err error) error {
	if errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	return err
}
