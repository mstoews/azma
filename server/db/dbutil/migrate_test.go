package dbutil

import "testing"

func TestDirectDSN(t *testing.T) {
	cases := map[string]string{
		"postgresql://u:p@ep-cool-1-pooler.ap-southeast-1.aws.neon.tech/neondb?sslmode=require": "postgresql://u:p@ep-cool-1.ap-southeast-1.aws.neon.tech/neondb?sslmode=require",
		"postgresql://u:p@ep-cool-1.ap-southeast-1.aws.neon.tech/neondb?sslmode=require":        "postgresql://u:p@ep-cool-1.ap-southeast-1.aws.neon.tech/neondb?sslmode=require",
		"postgresql://cms:cms@localhost:55440/cms?sslmode=disable":                              "postgresql://cms:cms@localhost:55440/cms?sslmode=disable",
	}
	for in, want := range cases {
		if got := DirectDSN(in); got != want {
			t.Errorf("DirectDSN(%q) = %q, want %q", in, got, want)
		}
	}
}
