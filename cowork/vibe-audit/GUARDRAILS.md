# Architecture Guardrails Checklist

Walk this checklist during Layer 2 of the vibe-audit. For each item, verify the current state and note gaps. This checklist should be customized per project — add guardrails that match your architecture and remove ones that don't apply.

For each guardrail:
- **Implemented** — the code demonstrates this is in place. Note where.
- **Partially implemented** — some coverage, gaps exist. Note what's missing.
- **Not yet applicable** — the feature this guards doesn't exist yet. Note when it will matter.
- **Missing** — the feature exists but the guardrail doesn't. Flag severity.

---

## Authentication & Authorization
- [ ] API endpoints validate authentication before processing
- [ ] Session/token handling follows security best practices
- [ ] Admin operations require elevated privileges
- [ ] Auth middleware is applied consistently across routes

## Data Layer
- [ ] Database queries use parameterized statements (no string interpolation)
- [ ] User input is validated and sanitized at system boundaries
- [ ] Sensitive data is encrypted at rest where appropriate
- [ ] Database migrations are safe (no data loss on schema changes)

## API Security
- [ ] CORS origins are explicitly allowlisted (no wildcard in production)
- [ ] Rate limiting is applied to auth and public-facing endpoints
- [ ] Webhook endpoints validate request signatures (HMAC/similar)
- [ ] Error responses don't leak internal details (stack traces, DB schemas)

## Frontend / Client
- [ ] No API keys or secrets in client-visible code
- [ ] Output encoding applied to all rendered user content (XSS prevention)
- [ ] CSP headers set on served pages
- [ ] CSRF protection on form submissions

## Infrastructure
- [ ] Debug/test routes are not reachable in production
- [ ] Environment-specific configs don't leak between environments
- [ ] Secrets are managed via environment variables or a secrets manager (not hardcoded)
- [ ] Deployment configs follow principle of least privilege

## Dependency Management
- [ ] No known critical/high vulnerabilities in dependencies
- [ ] Lock files are committed and reviewed
- [ ] Postinstall scripts in dependencies are audited
- [ ] Dependencies are kept reasonably up to date
