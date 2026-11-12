package util

import (
	"errors"
	"strings"
	"time"

	"github.com/spf13/viper"
)

// Config is read by viper from app.env (if present) and overridden by
// environment variables of the same name.
type Config struct {
	Environment       string        `mapstructure:"ENVIRONMENT"`
	DBSource          string        `mapstructure:"DB_SOURCE"`
	HTTPServerAddress string        `mapstructure:"HTTP_SERVER_ADDRESS"`
	AllowedOrigins    []string      `mapstructure:"ALLOWED_ORIGINS"`
	AutoMigrate       bool          `mapstructure:"AUTO_MIGRATE"`
	SessionDuration   time.Duration `mapstructure:"SESSION_DURATION"`

	LoginLockoutThreshold int           `mapstructure:"LOGIN_LOCKOUT_THRESHOLD"`
	LoginLockoutWindow    time.Duration `mapstructure:"LOGIN_LOCKOUT_WINDOW"`

	// MediaDir is where uploads are written; MediaURLPrefix is the public path
	// they are served under.
	MediaDir string `mapstructure:"MEDIA_DIR"`
	// MediaBucket, when set, stores uploads in this Google Cloud Storage
	// bucket (under MediaBucketPrefix) instead of MediaDir.
	MediaBucket       string `mapstructure:"MEDIA_BUCKET"`
	MediaBucketPrefix string `mapstructure:"MEDIA_BUCKET_PREFIX"`
	MediaURLPrefix    string `mapstructure:"MEDIA_URL_PREFIX"`
	MediaMaxBytes     int64  `mapstructure:"MEDIA_MAX_BYTES"`

	// StaticDir, when set, is the built Angular site (dist/.../browser). The
	// server then serves it with an index.html fallback, so the site and the
	// API deploy as one process.
	StaticDir string `mapstructure:"STATIC_DIR"`
}

var defaults = map[string]any{
	"ENVIRONMENT":             "development",
	"DB_SOURCE":               "",
	"HTTP_SERVER_ADDRESS":     "0.0.0.0:8080",
	"ALLOWED_ORIGINS":         "",
	"AUTO_MIGRATE":            true,
	"SESSION_DURATION":        "12h",
	"LOGIN_LOCKOUT_THRESHOLD": 5,
	"LOGIN_LOCKOUT_WINDOW":    "15m",
	"MEDIA_DIR":               "./media",
	"MEDIA_BUCKET":            "",
	"MEDIA_BUCKET_PREFIX":     "media/",
	"MEDIA_URL_PREFIX":        "/media",
	"MEDIA_MAX_BYTES":         10 << 20,
	"STATIC_DIR":              "",
}

// LoadConfig reads <path>/app.env when it exists. A missing file is fine:
// every key has a default and can be supplied through the environment.
func LoadConfig(path string) (Config, error) {
	v := viper.New()
	v.AddConfigPath(path)
	v.SetConfigName("app")
	v.SetConfigType("env")
	v.AutomaticEnv()
	for k, val := range defaults {
		v.SetDefault(k, val)
	}

	var config Config
	if err := v.ReadInConfig(); err != nil {
		var notFound viper.ConfigFileNotFoundError
		if !errors.As(err, &notFound) {
			return config, err
		}
	}
	if err := v.Unmarshal(&config); err != nil {
		return config, err
	}
	// ALLOWED_ORIGINS arrives as one comma-separated string from env files.
	var origins []string
	for _, o := range config.AllowedOrigins {
		for _, part := range strings.Split(o, ",") {
			if part = strings.TrimSpace(part); part != "" {
				origins = append(origins, part)
			}
		}
	}
	config.AllowedOrigins = origins
	config.MediaURLPrefix = "/" + strings.Trim(config.MediaURLPrefix, "/")
	if config.DBSource == "" {
		return config, errors.New("DB_SOURCE is required")
	}
	return config, nil
}

func (c Config) IsProduction() bool { return strings.EqualFold(c.Environment, "production") }
