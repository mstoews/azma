import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { catchError, throwError } from 'rxjs';
import { AuthService } from './auth.service';

/** Adds the CMS bearer token to API calls and signs out when it is rejected. */
export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const auth = inject(AuthService);
  const token = auth.token();
  const isApi = req.url.startsWith('/api/');
  if (isApi && token && !req.url.endsWith('/auth/login')) {
    req = req.clone({ setHeaders: { Authorization: `Bearer ${token}` } });
  }
  return next(req).pipe(
    catchError((err: unknown) => {
      if (isApi && err instanceof HttpErrorResponse && err.status === 401 && !req.url.endsWith('/auth/login')) {
        auth.expire();
      }
      return throwError(() => err);
    }),
  );
};

/** Pulls the server's `{error: "..."}` message out of a failed request. */
export function errorMessage(err: unknown): string {
  if (err instanceof HttpErrorResponse) {
    const msg = (err.error as { error?: string } | null)?.error;
    if (msg) return msg;
    if (err.status === 0) return 'Cannot reach the CMS server.';
    return `Request failed (${err.status}).`;
  }
  return err instanceof Error ? err.message : String(err);
}
