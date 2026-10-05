package grpc

import (
	"context"
	"errors"
	"fmt"
	"net"
	"time"

	"google.golang.org/grpc"
)

type Config struct {
	Address      string
	GraceTimeout time.Duration
}

type RegisterFunc func(*grpc.Server) error

func NewServer(c Config, registers ...RegisterFunc) (*Server, error) {
	if c.GraceTimeout <= 0 {
		return nil, errors.New("gRPC grace timeout must be positive")
	}

	server := grpc.NewServer()
	for _, register := range registers {
		if register == nil {
			return nil, errors.New("gRPC register function must not be nil")
		}

		err := register(server)
		if err != nil {
			return nil, err
		}
	}

	return &Server{
		address:      c.Address,
		graceTimeout: c.GraceTimeout,
		srv:          server,
	}, nil
}

type Server struct {
	address      string
	graceTimeout time.Duration
	srv          *grpc.Server
}

func (s *Server) Serve(ctx context.Context) error {
	listener, err := net.Listen("tcp", s.address)
	if err != nil {
		return err
	}

	done := make(chan error, 1)
	go func() {
		done <- s.srv.Serve(listener)
	}()

	var shutdownErr error
	select {
	case err = <-done:
		s.srv.Stop()
	case <-ctx.Done():
		shutdownErr = s.shutdown()
		if shutdownErr != nil {
			return shutdownErr
		}
		err = <-done
	}
	if errors.Is(err, grpc.ErrServerStopped) {
		err = nil
	}
	return errors.Join(shutdownErr, err)
}

func (s *Server) shutdown() error {
	stopped := make(chan struct{})
	go func() {
		s.srv.GracefulStop()
		close(stopped)
	}()

	timer := time.NewTimer(s.graceTimeout)
	defer timer.Stop()

	select {
	case <-stopped:
		return nil
	case <-timer.C:
		go s.srv.Stop()
		return fmt.Errorf("gRPC graceful shutdown: %w", context.DeadlineExceeded)
	}
}
