// Package api is the HTTP surface of the CMS: a public read endpoint for the
// site, session auth, and the admin-only content management routes.
package api

import (
	"net/http"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	db "github.com/mstoews/azma-associates/server/db/sqlc"
	md "github.com/mstoews/azma-associates/server/middleware"
	"github.com/mstoews/azma-associates/server/storage"
	"github.com/mstoews/azma-associates/server/util"
)

type Server struct {
	config util.Config
	store  db.Store
	media  storage.Store
	router *gin.Engine
	now    func() time.Time
}

func NewServer(config util.Config, store db.Store, media storage.Store) *Server {
	s := &Server{config: config, store: store, media: media, now: time.Now}
	s.setupRouter()
	return s
}

// Handler exposes the router for tests.
func (s *Server) Handler() http.Handler { return s.router }

func (s *Server) Start() error {
	srv := &http.Server{
		Addr:              s.config.HTTPServerAddress,
		Handler:           s.router,
		ReadHeaderTimeout: 10 * time.Second,
	}
	return srv.ListenAndServe()
}

func (s *Server) setupRouter() {
	if s.config.IsProduction() {
		gin.SetMode(gin.ReleaseMode)
	}
	r := gin.New()
	r.Use(gin.Recovery(), requestLogger(), md.SecurityHeaders())
	// Do not trust X-Forwarded-For from arbitrary clients; ClientIP is only
	// recorded on sessions and in the audit log, never used for authorization.
	_ = r.SetTrustedProxies(nil)
	r.MaxMultipartMemory = 8 << 20

	if len(s.config.AllowedOrigins) > 0 {
		r.Use(cors.New(cors.Config{
			AllowOrigins:  s.config.AllowedOrigins,
			AllowMethods:  []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
			AllowHeaders:  []string{"Authorization", "Content-Type"},
			ExposeHeaders: []string{"Content-Length"},
			MaxAge:        12 * time.Hour,
		}))
	}

	// /healthz is kept for local use; Cloud Run's front end reserves paths
	// ending in "z", so monitoring there uses /api/v1/health.
	health := func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"status": "ok"}) }
	r.GET("/healthz", health)

	v1 := r.Group("/api/v1")
	v1.GET("/health", health)

	// Public.
	v1.GET("/site", s.getPublicSite)
	v1.POST("/auth/login", s.login)

	// Any signed-in user (all users are administrators today).
	authed := v1.Group("/auth", md.AuthSession(s.store))
	authed.GET("/me", s.me)
	authed.POST("/logout", s.logout)
	authed.PUT("/password", s.changeOwnPassword)

	// Administrators only.
	admin := v1.Group("/admin", md.AuthSession(s.store), md.RequireAdmin())
	{
		admin.GET("/pages", s.listPages)
		admin.POST("/pages", s.createPage)
		admin.PUT("/pages/order", s.reorderPages)
		admin.GET("/pages/:id", s.getPage)
		admin.PUT("/pages/:id", s.updatePage)
		admin.DELETE("/pages/:id", s.deletePage)

		admin.GET("/profiles", s.listProfiles)
		admin.POST("/profiles", s.createProfile)
		admin.PUT("/profiles/order", s.reorderProfiles)
		admin.GET("/profiles/:id", s.getProfile)
		admin.PUT("/profiles/:id", s.updateProfile)
		admin.DELETE("/profiles/:id", s.deleteProfile)

		admin.GET("/nav", s.listNav)
		admin.PUT("/nav", s.replaceNav)

		admin.GET("/settings", s.getSettings)
		admin.PUT("/settings", s.updateSettings)

		admin.GET("/media", s.listMedia)
		admin.POST("/media", s.uploadMedia)
		admin.PATCH("/media/:id", s.updateMedia)
		admin.DELETE("/media/:id", s.deleteMedia)

		admin.GET("/users", s.listUsers)
		admin.POST("/users", s.createUser)
		admin.PUT("/users/:id", s.updateUser)
		admin.PUT("/users/:id/password", s.setUserPassword)
		admin.DELETE("/users/:id", s.deleteUser)

		admin.GET("/audit", s.listAudit)
	}

	// Uploaded files, streamed from the media store (local dir or bucket).
	r.GET(s.config.MediaURLPrefix+"/*key", s.serveMedia)
	r.HEAD(s.config.MediaURLPrefix+"/*key", s.serveMedia)

	if s.config.StaticDir != "" {
		r.NoRoute(s.serveSPA)
	} else {
		r.NoRoute(func(c *gin.Context) { c.JSON(http.StatusNotFound, gin.H{"error": "not found"}) })
	}

	s.router = r
}
