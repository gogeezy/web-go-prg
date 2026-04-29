package history

import (
	"context"
	"database/sql"
	"time"
)

// Entry is one recorded calculator operation.
type Entry struct {
	ID        int64
	CreatedAt time.Time
	OperandA  float64
	OperandB  float64
	Result    float64
	Operation string
}

// Repository persists operation history in PostgreSQL.
type Repository struct {
	db *sql.DB
}

// NewRepository returns a repository backed by db.
func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// EnsureSchema creates the operation_history table if it does not exist.
func (r *Repository) EnsureSchema(ctx context.Context) error {
	const createTable = `
CREATE TABLE IF NOT EXISTS operation_history (
	id BIGSERIAL PRIMARY KEY,
	created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
	operand_a DOUBLE PRECISION NOT NULL,
	operand_b DOUBLE PRECISION NOT NULL,
	result DOUBLE PRECISION NOT NULL,
	operation VARCHAR(32) NOT NULL DEFAULT 'sum'
)`
	if _, err := r.db.ExecContext(ctx, createTable); err != nil {
		return err
	}
	const createIndex = `CREATE INDEX IF NOT EXISTS operation_history_created_at_idx ON operation_history (created_at DESC)`
	_, err := r.db.ExecContext(ctx, createIndex)
	return err
}

// InsertSum records a successful sum operation.
func (r *Repository) InsertSum(ctx context.Context, a, b, result float64) error {
	const q = `
INSERT INTO operation_history (operand_a, operand_b, result, operation)
VALUES ($1, $2, $3, 'sum')
`
	_, err := r.db.ExecContext(ctx, q, a, b, result)
	return err
}

// ListRecent returns the latest operations, newest first.
func (r *Repository) ListRecent(ctx context.Context, limit int) ([]Entry, error) {
	if limit <= 0 {
		limit = 50
	}
	if limit > 500 {
		limit = 500
	}
	const q = `
SELECT id, created_at, operand_a, operand_b, result, operation
FROM operation_history
ORDER BY created_at DESC
LIMIT $1
`
	rows, err := r.db.QueryContext(ctx, q, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []Entry
	for rows.Next() {
		var e Entry
		if err := rows.Scan(&e.ID, &e.CreatedAt, &e.OperandA, &e.OperandB, &e.Result, &e.Operation); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}
