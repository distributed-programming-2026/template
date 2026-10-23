// Package gateway demonstrates request/response header processing and a local denial.
package gateway

import (
	"context"
	"net/http"
	"strings"

	api "github.com/distributed-programming-2026/lib/gateway/interceptor"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

func NewHandler() api.InterceptorServer {
	return &handler{}
}

type handler struct {
	api.UnimplementedInterceptorServer
}

func (h *handler) Intercept(_ context.Context, req *api.InterceptRequest) (*api.InterceptResponse, error) {
	if req.GetContext().GetRequest() == nil {
		return nil, status.Error(codes.InvalidArgument, "request context required")
	}

	var mutation *api.HeaderMutation
	switch {
	case req.GetRequestHeaders() != nil:
		// Demo only: replace this opt-in denial with application policy.
		for _, header := range req.GetRequestHeaders().GetHeaders() {
			if strings.EqualFold(header.GetKey(), "X-Demo-Deny") && header.GetValue() == "true" {
				return &api.InterceptResponse{Result: &api.InterceptResponse_ImmediateResponse{
					ImmediateResponse: &api.ImmediateResponse{
						StatusCode: http.StatusForbidden,
						Headers:    []*api.Header{{Key: "Content-Type", Value: "application/json"}},
						Body:       []byte(`{"error":"denied by demo interceptor"}`),
					},
				}}, nil
			}
		}
		mutation = &api.HeaderMutation{
			Set: []*api.HeaderValues{{Key: "X-Demo-Request-ID", Values: []string{req.GetContext().GetRequestId()}}},
		}
	case req.GetResponseHeaders() != nil:
		mutation = &api.HeaderMutation{
			Set: []*api.HeaderValues{{Key: "X-Demo-Interceptor", Values: []string{"template"}}},
		}
	default:
		return nil, status.Error(codes.InvalidArgument, "request or response headers phase required")
	}

	return &api.InterceptResponse{Result: &api.InterceptResponse_ContinueResponse{
		ContinueResponse: &api.ContinueResponse{HeaderMutation: mutation},
	}}, nil
}
