package middleware

import (
	"net/http"
	"strconv"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

// RateLimit is a fixed-window limiter keyed by client IP, for public routes
// that write (the consultation form, sign-up). It is per-process and held in
// memory: with more than one instance the effective limit is per instance,
// which is enough to stop a script without a shared store.
func RateLimit(limit int, window time.Duration) gin.HandlerFunc {
	var (
		mu      sync.Mutex
		hits    = map[string]int{}
		resetAt = time.Now().Add(window)
	)
	return func(c *gin.Context) {
		ip := c.ClientIP()
		mu.Lock()
		if now := time.Now(); now.After(resetAt) {
			hits = map[string]int{}
			resetAt = now.Add(window)
		}
		hits[ip]++
		over := hits[ip] > limit
		retry := time.Until(resetAt)
		mu.Unlock()
		if over {
			c.Header("Retry-After", strconv.Itoa(int(retry.Seconds())+1))
			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{
				"error": "too many requests; please try again shortly",
			})
			return
		}
		c.Next()
	}
}
