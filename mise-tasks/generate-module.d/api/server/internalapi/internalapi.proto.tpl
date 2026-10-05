syntax = "proto3";
package templateInternalAPI;

option go_package = "/.;templateinternalapi";

service TemplateService {
  rpc Echo(EchoRequest) returns (EchoResponse);
}

message EchoRequest {
  string Body = 1;
}

message EchoResponse {
  string OperationID = 1;
}