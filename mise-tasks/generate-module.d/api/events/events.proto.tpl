syntax = "proto3";
package templateEvents;

option go_package = "/.;templateevents";

message Echo {
  string ID = 1;
  string Body = 2;
}