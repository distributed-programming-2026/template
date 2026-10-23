package integration_tests

import (
	"context"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"

	api "github.com/distributed-programming-2026/lib/gateway/interceptor"
	"github.com/stretchr/testify/require"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/wait"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"

	publicapi "template/api/server/publicapi"
)

func TestGatewayInterceptor(t *testing.T) {
	connection, err := grpc.NewClient(testEnv.conf.GRPC.Address, grpc.WithTransportCredentials(insecure.NewCredentials()))
	require.NoError(t, err)
	defer connection.Close()

	ctx, cancel := context.WithTimeout(t.Context(), time.Minute)
	defer cancel()

	// The request phase replaces a client-supplied value with the gateway request ID.
	decision, err := api.NewInterceptorClient(connection).Intercept(ctx, &api.InterceptRequest{
		Context: &api.ProcessingContext{RequestId: "demo-request", Request: &api.HttpRequest{Method: http.MethodPost}},
		Event: &api.InterceptRequest_RequestHeaders{RequestHeaders: &api.HttpHeaders{
			Headers: []*api.Header{{Key: "X-Demo-Request-ID", Value: "untrusted"}},
		}},
	}, grpc.WaitForReady(true))
	require.NoError(t, err)
	require.NotNil(t, decision.GetContinueResponse())
	require.Equal(t, "X-Demo-Request-ID", decision.GetContinueResponse().GetHeaderMutation().GetSet()[0].GetKey())
	require.Equal(t, []string{"demo-request"}, decision.GetContinueResponse().GetHeaderMutation().GetSet()[0].GetValues())

	// Run the same generated route and interceptor configuration as local-up.
	configuration := "kind: gateway/v1\nport: 8000\nhealthzPort: 15000\ngatewayHealthHost: 0\n"
	for _, name := range []string{"routes.yaml", "interceptor.yaml"} {
		data, err := os.ReadFile("../../config/gateway/" + name)
		require.NoError(t, err)
		configuration += "---\n" + string(data)
	}
	proxy, err := testEnv.startContainer(ctx, testcontainers.ContainerRequest{
		Image:        "ghcr.io/distributed-programming-2026/gateway:v0.0.1",
		ExposedPorts: []string{"8000/tcp", "15000/tcp"},
		Networks:     []string{testEnv.network.Name},
		Files: []testcontainers.ContainerFile{{
			Reader: strings.NewReader(configuration), ContainerFilePath: "/config/gateway.yaml", FileMode: 0o644,
		}},
		WaitingFor: wait.ForHTTP("/readyz").WithPort("15000/tcp").WithStatusCodeMatcher(func(code int) bool {
			return code == http.StatusNoContent
		}),
	})
	require.NoError(t, err)
	address, err := containerAddress(ctx, proxy, "8000/tcp")
	require.NoError(t, err)
	client, err := publicapi.NewClientWithResponses("http://" + address + "/" + moduleID)
	require.NoError(t, err)

	response, err := client.EchoWithResponse(ctx, publicapi.EchoJSONRequestBody{Body: "through gateway"})
	require.NoError(t, err)
	require.Equal(t, http.StatusOK, response.StatusCode())
	require.Equal(t, moduleID, response.HTTPResponse.Header.Get("X-Demo-Interceptor"))
	require.NotNil(t, response.JSON200)
	waitHandled(t, checkEcho(t, response.JSON200.OperationID, "through gateway"), 1)

	denied, err := client.EchoWithResponse(ctx, publicapi.EchoJSONRequestBody{Body: "denied by gateway"},
		func(_ context.Context, request *http.Request) error {
			request.Header.Set("X-Demo-Deny", "true")
			return nil
		},
	)
	require.NoError(t, err)
	require.Equal(t, http.StatusForbidden, denied.StatusCode())
	require.JSONEq(t, `{"error":"denied by demo interceptor"}`, string(denied.Body))
	// Immediate responses stop processing before the backend and response phase.
	require.Empty(t, denied.HTTPResponse.Header.Get("X-Demo-Interceptor"))
	var count int
	err = testEnv.connector.TransactionalClient().GetContext(ctx, "test.gateway.denied", &count,
		"SELECT COUNT(*) FROM echo WHERE body = ?", "denied by gateway")
	require.NoError(t, err)
	require.Zero(t, count)
}
