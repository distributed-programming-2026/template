[tasks.all]
run = [
    { task = "generate" },
    { task = "modules" },
    { task = "build" },
    { task = "test" },
    { task = "integration-tests" },
    { task = "lint" },
]

[tasks.generate]
run = [
    { task = "grpc-generate" },
    { task = "oapi-generate" },
    { task = "go-generate" },
]

[tasks.go-generate]
run = "go generate ./..."

[tasks.grpc-generate]
run = """
#!/usr/bin/env sh
set -eu

find . -name '*.proto' | while read -r proto_file; do
    proto_dir=$(dirname "$proto_file")
    protoc \
        --proto_path="$proto_dir" \
        --go_out="$proto_dir" \
        --go_opt=paths=source_relative \
        --go-grpc_out="$proto_dir" \
        --go-grpc_opt=paths=source_relative \
        "$proto_file"
done
"""
[tasks.oapi-generate]
run = """
#!/usr/bin/env sh
set -eu

find . -name '*.oapi.yaml' | while read -r oapi_file; do
    base_filename="${oapi_file%.*}"
    oapi-codegen \
        -generate types,chi-server,strict-server,client,spec \
        -o "$base_filename.gen.go" "$oapi_file"
done
"""

[tasks."modules"]
run = "go mod tidy"

[tasks.build]
depends = ["generate"]
env = { GOOS = "linux", CGO_ENABLED = "0" }
run = "go build -v -trimpath -o dist/template ./cmd"

[tasks."test"]
run = '''
#!/usr/bin/env sh
set -eu

packages=$(go list ./...)
printf '%s\n' "$packages" | awk '!/\/internal\/integration-tests($|\/)/' | xargs go test
'''

[tasks."lint"]
run = "golangci-lint run"

[tasks.integration-tests]
depends = ["build"]
run = [
    "docker build --tag distributed-programming-template:integration .",
    "go test -v -count=1 ./internal/integration-tests",
]
