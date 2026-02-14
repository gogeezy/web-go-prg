package calculator

import (
	"math"
	"testing"
)

func TestSum(t *testing.T) {
	tests := []struct {
		name string
		a, b float64
		want float64
	}{
		{"zeros", 0, 0, 0},
		{"positive", 1, 1, 2},
		{"negative", -1, -1, -2},
		{"mixed", -1, 1, 0},
		{"decimals", 1.5, 2.5, 4},
		{"large", 1e10, 1e10, 2e10},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := Sum(tt.a, tt.b)
			if math.Abs(got-tt.want) > 1e-9 {
				t.Errorf("Sum(%v, %v) = %v, want %v", tt.a, tt.b, got, tt.want)
			}
		})
	}
}
