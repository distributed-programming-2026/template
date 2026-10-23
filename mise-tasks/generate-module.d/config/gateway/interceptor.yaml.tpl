kind: gateway/service/v1
name: template-interceptor
interceptor:
  address: template-service:8081
  transport: grpc
  timeout: 5s
