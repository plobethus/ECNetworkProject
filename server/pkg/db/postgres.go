package db

import (
	"database/sql"

	_ "github.com/lib/pq"
)

func Connect() (*sql.DB, error) {
	connStr := "postgres://admin:admin@db:5432/metrics?sslmode=disable"
	return sql.Open("postgres", connStr)
}