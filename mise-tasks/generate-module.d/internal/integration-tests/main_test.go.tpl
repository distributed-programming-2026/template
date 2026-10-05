package integration_tests

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/distributed-programming-2026/go-sdk/pkg/mysql"
	mysqldriver "github.com/go-sql-driver/mysql"
	"github.com/kelseyhightower/envconfig"
	"github.com/testcontainers/testcontainers-go"
	tcmysql "github.com/testcontainers/testcontainers-go/modules/mysql"
	"github.com/testcontainers/testcontainers-go/network"
	"github.com/testcontainers/testcontainers-go/wait"

	"template/internal/template/config"
)

const moduleID = "template"

var testEnv *environment

type environment struct {
	conf      config.Env
	connector mysql.Connector
	network   *testcontainers.DockerNetwork
	logs      logBuffer
	closers   []func() error
}

func TestMain(m *testing.M) {
	os.Exit(runTests(m))
}

func runTests(m *testing.M) (exitCode int) {
	testEnv = &environment{}
	defer func() {
		err := testEnv.close()
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			exitCode = 1
		}
		if exitCode != 0 {
			fmt.Fprintln(os.Stderr, testEnv.logs.String())
		}
	}()

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	err := testEnv.prepare(ctx)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	return m.Run()
}

func (e *environment) prepare(ctx context.Context) error {
	err := envconfig.Process("integration_defaults", &e.conf)
	if err != nil {
		return err
	}

	e.network, err = network.New(ctx)
	if err != nil {
		return err
	}
	e.closers = append(e.closers, func() error {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		return e.network.Remove(ctx)
	})

	mysqlContainer, err := tcmysql.Run(ctx, "mysql:8.4",
		tcmysql.WithDatabase(moduleID+"_test"),
		tcmysql.WithUsername(moduleID),
		tcmysql.WithPassword("integration:password@local"),
		network.WithNetwork([]string{"mysql"}, e.network),
	)
	if mysqlContainer != nil {
		e.closers = append(e.closers, func() error {
			return testcontainers.TerminateContainer(mysqlContainer)
		})
	}
	if err != nil {
		return err
	}

	dsn, err := mysqlContainer.ConnectionString(ctx, "parseTime=true")
	if err != nil {
		return err
	}
	databaseConfig, err := mysqldriver.ParseDSN(dsn)
	if err != nil {
		return err
	}
	e.conf.MySQL.Address = databaseConfig.Addr
	e.conf.MySQL.Database = databaseConfig.DBName
	e.conf.MySQL.User = databaseConfig.User
	e.conf.MySQL.Password = databaseConfig.Passwd

	err = e.startBroker(ctx)
	if err != nil {
		return err
	}

	e.connector = mysql.NewConnector()
	err = e.connector.Open(dsn, mysql.Config{
		MaxConnections: 10,
	})
	if err != nil {
		return err
	}
	e.closers = append(e.closers, e.connector.Close)

	e.conf.App.GraceTimeout = time.Second
	e.conf.Relay.Interval = 50 * time.Millisecond
	e.conf.Relay.PublishTimeout = time.Second

	_, err = e.startApplication(ctx, "message-handler")
	if err != nil {
		return err
	}
	service, err := e.startApplication(ctx, "service")
	if err != nil {
		return err
	}
	e.conf.HTTP.Address, err = containerAddress(ctx, service, "8082/tcp")
	if err != nil {
		return err
	}
	e.conf.GRPC.Address, err = containerAddress(ctx, service, "8081/tcp")
	return err
}

func (e *environment) startBroker(ctx context.Context) error {
	broker, err := e.startContainer(ctx, testcontainers.ContainerRequest{
		Image:        "rabbitmq:4.1-alpine",
		ExposedPorts: []string{"5672/tcp"},
		Networks:     []string{e.network.Name},
		NetworkAliases: map[string][]string{
			e.network.Name: {"rabbitmq"},
		},
		Env: map[string]string{
			"RABBITMQ_DEFAULT_USER": "integration",
			"RABBITMQ_DEFAULT_PASS": "integration-password",
		},
		WaitingFor: wait.ForLog("Server startup complete").WithStartupTimeout(time.Minute),
	})
	if err != nil {
		return err
	}
	address, err := containerAddress(ctx, broker, "5672/tcp")
	if err != nil {
		return err
	}
	brokerURL := &url.URL{
		Scheme: "amqp",
		User:   url.UserPassword("integration", "integration-password"),
		Host:   address,
		Path:   "/",
	}
	e.conf.AMQP.URL = brokerURL.String()
	return nil
}

func (e *environment) startApplication(ctx context.Context, command string) (testcontainers.Container, error) {
	prefix := strings.ToUpper(moduleID) + "_"
	return e.startContainer(ctx, testcontainers.ContainerRequest{
		Image:        "distributed-programming-template:integration",
		Cmd:          []string{command},
		ExposedPorts: []string{"8081/tcp", "8082/tcp"},
		Networks:     []string{e.network.Name},
		Env: map[string]string{
			prefix + "MYSQL_ADDRESS":         "mysql:3306",
			prefix + "MYSQL_DATABASE":        e.conf.MySQL.Database,
			prefix + "MYSQL_USER":            e.conf.MySQL.User,
			prefix + "MYSQL_PASSWORD":        e.conf.MySQL.Password,
			prefix + "AMQP_URL":              "amqp://integration:integration-password@rabbitmq:5672/",
			prefix + "AMQP_QUEUE":            e.conf.AMQP.Queue,
			prefix + "HTTP_ADDRESS":          ":8082",
			prefix + "GRPC_ADDRESS":          ":8081",
			prefix + "APP_GRACE_TIMEOUT":     e.conf.App.GraceTimeout.String(),
			prefix + "RELAY_INTERVAL":        e.conf.Relay.Interval.String(),
			prefix + "RELAY_PUBLISH_TIMEOUT": e.conf.Relay.PublishTimeout.String(),
		},
		LogConsumerCfg: &testcontainers.LogConsumerConfig{
			Consumers: []testcontainers.LogConsumer{&e.logs},
		},
		WaitingFor: wait.ForHTTP("/healthz").WithPort("8082/tcp").WithStatusCodeMatcher(func(status int) bool {
			return status == http.StatusNoContent
		}).WithStartupTimeout(time.Minute),
	})
}

func (e *environment) startContainer(ctx context.Context, request testcontainers.ContainerRequest) (testcontainers.Container, error) {
	container, err := testcontainers.GenericContainer(ctx, testcontainers.GenericContainerRequest{
		ContainerRequest: request,
		Started:          true,
	})
	if container != nil {
		e.closers = append(e.closers, func() error {
			return testcontainers.TerminateContainer(container)
		})
	}
	return container, err
}

func (e *environment) close() error {
	var errs []error
	for i := len(e.closers) - 1; i >= 0; i-- {
		errs = append(errs, e.closers[i]())
	}
	return errors.Join(errs...)
}

func containerAddress(ctx context.Context, container testcontainers.Container, port string) (string, error) {
	host, err := container.Host(ctx)
	if err != nil {
		return "", err
	}
	mappedPort, err := container.MappedPort(ctx, port)
	if err != nil {
		return "", err
	}
	return net.JoinHostPort(host, mappedPort.Port()), nil
}
