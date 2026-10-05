package main

import (
	"context"
	"log/slog"
	"os"

	"github.com/distributed-programming-2026/go-sdk/pkg/logging"
	"github.com/kelseyhightower/envconfig"
	"github.com/urfave/cli/v3"

	"template/internal/template/config"

	"github.com/distributed-programming-2026/lib/runtime"
)

const appID = "template"

type application struct {
	logger *slog.Logger
	conf   config.Env
}

func main() {
	if err := runMain(); err != nil {
		os.Exit(1)
	}
}

func runMain() error {
	ctx, stop := runtime.ListenOSKillSignalsContext(context.Background())
	defer stop()
	a := &application{
		logger: logging.New(logging.Config{
			AppID: appID,
		}),
	}
	if err := a.command().Run(ctx, os.Args); err != nil {
		a.logger.Error("stopped with error", logging.Error(err))
		return err
	}
	a.logger.Info("stopped successfully")
	return nil
}

func (a *application) command() *cli.Command {
	return &cli.Command{
		Name:           appID,
		DefaultCommand: "service",
		Flags: []cli.Flag{
			&cli.BoolFlag{
				Name: "debug",
			},
		},
		Before: func(ctx context.Context, c *cli.Command) (context.Context, error) {
			err := envconfig.Process(appID, &a.conf)
			if err != nil {
				return ctx, err
			}
			err = a.conf.Validate()
			if err != nil {
				return ctx, err
			}
			a.logger = logging.New(logging.Config{
				AppID: appID,
				Debug: c.Bool("debug") || a.conf.App.Debug,
			})
			return ctx, nil
		},
		Commands: []*cli.Command{
			a.serviceCmd(),
			a.messageHandlerCmd(),
		},
	}
}
