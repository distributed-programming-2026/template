package migrations

import (
	"github.com/distributed-programming-2026/go-sdk/pkg/migrator"
	"github.com/distributed-programming-2026/go-sdk/pkg/mysql"
)

func Database(client mysql.ClientContext) []migrator.Migration {
	m := make([]migrator.Migration, 0, len(migrations))
	for _, buildFunc := range migrations {
		m = append(m, buildFunc(client))
	}
	return m
}

type mysqlMigration func(client mysql.ClientContext) migrator.Migration

var migrations = []mysqlMigration{
	Version1791225168,
}
