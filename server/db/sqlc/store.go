package db

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Store is the generated Querier plus transaction support. Hand-written; sqlc
// does not touch this file.
type Store interface {
	Querier
	// ExecTx runs fn inside a single transaction, committing when fn returns
	// nil and rolling back otherwise.
	ExecTx(ctx context.Context, fn func(Querier) error) error
}

type SQLStore struct {
	pool *pgxpool.Pool
	*Queries
}

func NewStore(pool *pgxpool.Pool) Store {
	return &SQLStore{pool: pool, Queries: New(pool)}
}

func (s *SQLStore) ExecTx(ctx context.Context, fn func(Querier) error) error {
	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return err
	}
	if err := fn(s.Queries.WithTx(tx)); err != nil {
		if rbErr := tx.Rollback(ctx); rbErr != nil {
			return fmt.Errorf("tx err: %w, rollback err: %v", err, rbErr)
		}
		return err
	}
	return tx.Commit(ctx)
}
