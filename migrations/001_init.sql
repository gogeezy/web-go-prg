-- История операций калькулятора

CREATE TABLE IF NOT EXISTS operation_history (
	id BIGSERIAL PRIMARY KEY,
	created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
	operand_a DOUBLE PRECISION NOT NULL,
	operand_b DOUBLE PRECISION NOT NULL,
	result DOUBLE PRECISION NOT NULL,
	operation VARCHAR(32) NOT NULL DEFAULT 'sum'
);

CREATE INDEX IF NOT EXISTS operation_history_created_at_idx ON operation_history (created_at DESC);
