package runtime

import (
	"context"
	"os/signal"
	"syscall"
)

func ListenOSKillSignalsContext(ctx context.Context) (context.Context, context.CancelFunc) {
	return signal.NotifyContext(ctx, syscall.SIGTERM, syscall.SIGINT)
}
