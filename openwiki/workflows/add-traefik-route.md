---
type: workflow
title: Adding a Traefik Route for a Stack
description: Learn how to expose a new service via Traefik by defining middleware in the rules/ directory and configuring routers and services either through Docker labels or static rules files.
tags: [traefik, routing, middleware, docker-compose, workflow]
verified:
  - by: openwiki/0.5.0
    at: 2026-09-06T09:58:25.192Z
sources:
  - id: openwiki-source-63b6ca0f80e36f9622bd01f1
    resource: repo://stacks/traefik/README.md
generated: { by: "openwiki/0.5.0", at: "2026-09-06T09:58:25.192Z" }
---

Traefik in this homelab setup uses both the file provider (for static/middleware configuration) and the Docker provider (for dynamic service discovery). This workflow describes two common methods to expose a new service: defining middleware in `rules/` and configuring routers/services via Docker labels, or defining everything statically in `rules/`.

## Prerequisites

- Access to the `stacks/traefik/rules/` directory
- The target stack must be deployed and its service accessible via the Docker network that Traefik monitors
- Basic understanding of Traefik routers, middlewares, and services

## Method 1: Middleware in rules/, Router/Service via Docker Labels

This method keeps shared middleware definitions in version control while keeping router and service specifics close to the application stack.

### Step 1: Define Custom Middleware (Optional)

If you need middleware not already provided in `rules/base.yml` (e.g., custom rate limits, headers, or authentication), create a new YAML file in `stacks/traefik/rules/`:

```yaml
# Example: stacks/traefik/rules/my-middleware.yml
http:
  middlewares:
    my-rate-limit:
      rateLimit:
        average: 50   # requests/sec
        burst: 100
    my-headers:
      headers:
        customRequestHeaders:
          X-Custom-Header: "value"
```

### Step 2: Label the Service in compose.yaml

In your stack's `compose.yaml`, add Traefik labels to define the router, service, and attach middleware:

```yaml
# Example: stacks/your-stack/compose.yaml
services:
  web:
    image: your-web-image
    labels:
      - "traefik.enable=true"
      # Router definition
      - "traefik.http.routers.web.rule=Host(`web.example.com`)"
      - "traefik.http.routers.web.entrypoints=websecure-external"
      - "traefik.http.routers.web.tls=true"
      # Attach middleware: custom middleware from file + existing chain
      - "traefik.http.routers.web.middlewares=my-rate-limit@file,chain-external@file"
      # Service definition (points to container port)
      - "traefik.http.services.web.loadbalancer.server.port=80"
```

**Key points:**
- Use `@file` suffix to reference middleware defined in `rules/` directory
- The `chain-external@file` middleware includes CrowdSec bouncer and security headers
- `websecure-external` entrypoint is for external HTTPS traffic
- The service name (`web` in example) must match across router and service labels

### Step 3: Deploy or Update the Stack

After updating the compose file, deploy or restart the stack. Traefik's Docker provider will automatically detect the new router labels and merge them with the file provider configuration.

## Method 2: Everything Defined in rules/

This method keeps all routing configuration in version control, useful for static infrastructure or when you prefer not to modify application compose files.

### Step 1: Create a Static Configuration File

Create a new YAML file in `stacks/traefik/rules/` (e.g., `my-service.yml`):

```yaml
# Example: stacks/traefik/rules/my-service.yml
http:
  middlewares:
    # Reuse existing middleware or define new ones
    # Example: reuse chain-external from base.yml (no redefinition needed)
  services:
    # Optional: define service statically (skip if using Docker service discovery)
    my-service:
      loadBalancer:
        servers:
          - url: "http://private-service:8080"  # internal Docker address
  routers:
    my-service-router:
      rule: "Host(`my-service.example.com`)"
      entryPoints:
        - websecure-external
      tls: {}
      service: my-service  # matches service name above OR Docker service name
      middlewares:
        - chain-external   # references middleware from base.yml or other rules files
```

**Important notes:**
- If you omit the `services` section, Traefik will look for a service named `my-service` via Docker service discovery (using container name or labels)
- The `rule` uses standard Traefik matchers (`Host()`, `PathPrefix()`, etc.)
- `tls: {}` enables Let's Encrypt certificates if configured
- Middleware references use the name as defined in any `rules/` file (no `@file` suffix needed here)

### Step 2: Ensure Service Discoverability

If relying on Docker service discovery (no static service definition):
- Make sure the container is connected to a Docker network accessible by Traefik
- The service name in Traefik defaults to the container name unless overridden by labels like `traefik.http.services.<name>.loadbalancer.server.port`

### Step 3: Automatic Reload

Traefik's file provider monitors the `rules/` directory. Adding a new file triggers automatic reload of the dynamic configuration—no restart needed.

## Verification

After applying either method:
1. Check Traefik dashboard (if enabled) for new router and service
2. Test the route externally: `curl -I https://your-service.example.com`
3. Review Traefik logs for errors:
   ```bash
   docker logs traefik  # assuming container name is traefik
   ```

## Troubleshooting

- **Middleware not found:** Verify the middleware name and that it's defined in a `.yml` file under `rules/` (for `@file` references)
- **502 Bad Gateway:** Ensure the service is healthy and listening on the specified port; check Docker network connectivity
- **TLS issues:** Confirm `websecure-external` entrypoint is configured for TLS in Traefik's static configuration
- **Rule conflicts:** Ensure your `Host()` rule is unique and doesn't conflict with existing routers

## Related Concepts

<!-- openwiki: broken internal link [/openwiki/concepts/traefik-middleware.md] file "/openwiki/concepts/traefik-middleware.md" does not exist. Fix the href or restore the target, then delete this comment. -->
- See [Traefik Middleware Concepts](/openwiki/concepts/traefik-middleware.md) for middleware chain details
- See [Traefik as Ingress](/openwiki/integrations/traefik-as-ingress.md) for architectural context
