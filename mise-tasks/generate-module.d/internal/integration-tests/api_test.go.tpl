package integration_tests

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/distributed-programming-2026/go-sdk/pkg/amqp"
	eventamqp "github.com/distributed-programming-2026/go-sdk/pkg/event/amqp"
	"github.com/stretchr/testify/require"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"

	domainevent "github.com/distributed-programming-2026/lib/event"

	internalapi "template/api/server/internalapi"
	publicapi "template/api/server/publicapi"
)

func TestHTTPAndGRPCDelivery(t *testing.T) {
	client, err := publicapi.NewClientWithResponses("http://" + testEnv.conf.HTTP.Address)
	require.NoError(t, err)

	response, err := client.EchoWithResponse(t.Context(), publicapi.EchoJSONRequestBody{
		Body: "HTTP привет",
	})
	require.NoError(t, err)
	require.Equal(t, http.StatusOK, response.StatusCode())
	require.NotNil(t, response.JSON200)
	envelope := checkEcho(t, response.JSON200.OperationID, "HTTP привет")
	waitHandled(t, envelope, 1)

	connection, err := grpc.NewClient(testEnv.conf.GRPC.Address, grpc.WithTransportCredentials(insecure.NewCredentials()))
	require.NoError(t, err)
	defer connection.Close()

	ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
	defer cancel()

	grpcResponse, err := internalapi.NewTemplateServiceClient(connection).Echo(ctx, &internalapi.EchoRequest{
		Body: "gRPC echo",
	}, grpc.WaitForReady(true))
	require.NoError(t, err)
	waitHandled(t, checkEcho(t, grpcResponse.OperationID, "gRPC echo"), 1)

	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	duplicateConnection := amqp.NewConnection(moduleID, amqp.ConnectionConfig{
		URL:            testEnv.conf.AMQP.URL,
		ConnectTimeout: time.Second,
	}, logger)
	defer func() {
		require.NoError(t, duplicateConnection.Stop())
	}()

	dispatcher, err := eventamqp.NewDispatcher(duplicateConnection.Producer(domainevent.DomainExchange(), nil, nil))
	require.NoError(t, err)
	require.NoError(t, duplicateConnection.Start())
	require.NoError(t, dispatcher.Dispatch(t.Context(), envelope))
	waitHandled(t, envelope, 2)
	require.Equal(t, 1, testEnv.logs.count("echo received", "echo_id", response.JSON200.OperationID))
}

func TestInvalidHTTPRequests(t *testing.T) {
	client := &http.Client{
		Timeout: time.Second,
	}
	for _, body := range []string{`{}`, `{"body":42}`, `null`, `{"body":`} {
		request, err := http.NewRequestWithContext(t.Context(), http.MethodPost,
			"http://"+testEnv.conf.HTTP.Address+"/api/public/v1/echo", strings.NewReader(body),
		)
		require.NoError(t, err)
		request.Header.Set("Content-Type", "application/json")

		response, err := client.Do(request)
		require.NoError(t, err)
		require.NoError(t, response.Body.Close())
		require.Equal(t, http.StatusBadRequest, response.StatusCode)
	}
}
