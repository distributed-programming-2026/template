package main

import (
	"context"
	"errors"
	"log/slog"

	"github.com/distributed-programming-2026/go-sdk/pkg/mysql"
	"github.com/distributed-programming-2026/go-sdk/pkg/uow"
	mysqldriver "github.com/go-sql-driver/mysql"

	"template/internal/template/config"
	echomysql "template/internal/template/infra/mysql"
)

type database struct {
	connector mysql.Connector
	unit      uow.UnitOfWorkWithRepositoryProvider[*echomysql.RepositoryProvider]
}

func openDatabase(ctx context.Context, logger *slog.Logger, conf config.Env) (_ *database, err error) {
	dsn := mysqldriver.NewConfig()
	dsn.Net = "tcp"
	dsn.Addr = conf.MySQL.Address
	dsn.DBName = conf.MySQL.Database
	dsn.User = conf.MySQL.User
	dsn.Passwd = conf.MySQL.Password
	dsn.ParseTime = true
	dsn.Timeout = conf.MySQL.ConnectTimeout
	dsn.ReadTimeout = conf.MySQL.ReadTimeout
	dsn.WriteTimeout = conf.MySQL.WriteTimeout
	dsn.Params = map[string]string{
		"charset": "utf8mb4",
	}

	connector := mysql.NewConnector()
	err = connector.Open(dsn.FormatDSN(), mysql.Config{
		MaxConnections:        conf.MySQL.MaxConnections,
		ConnectionMaxLifeTime: conf.MySQL.ConnectionMaxLifeTime,
		ConnectionMaxIdleTime: conf.MySQL.ConnectionMaxIdleTime,
	})
	if err != nil {
		return nil, err
	}
	defer func() {
		if err != nil {
			err = errors.Join(err, connector.Close())
		}
	}()

	client := connector.TransactionalClient()
	err = migrateDatabase(ctx, logger, client)
	if err != nil {
		return nil, err
	}

	unit := uow.NewUnitOfWork(mysql.NewConnectionPool(client), echomysql.NewRepositoryProvider)
	return &database{
		connector: connector,
		unit:      unit,
	}, nil
}
