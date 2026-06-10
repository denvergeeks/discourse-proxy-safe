# Discourse Proxy Safe

`discourse-proxy-safe` is a companion plugin for the
[`discourse-rich-previews`](https://github.com/denvergeeks/discourse-rich-previews)
theme component.

It provides a narrowly scoped, allowlisted backend proxy endpoint for fetching
remote Discourse topic JSON or other allowed content server-side.

## Purpose

This plugin exists primarily to support remote-topic preview fetching for the
Discourse Rich Previews theme component.

It is not intended to be a general-purpose browsing proxy.

## Installation

Add the plugin to your Discourse container in `app.yml`:

```yml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone https://github.com/denvergeeks/discourse-proxy-safe.git
```

Then rebuild the container.

## Site settings

After installation, review and configure:

- `proxy_safe_enabled`
- `proxy_safe_access_level`
- `proxy_safe_allowed_domains`
- `proxy_safe_subdomain_policy`
- `proxy_safe_block_private_networks`
- `proxy_safe_rate_limit_per_minute`
- `proxy_safe_cache_seconds`
- `proxy_safe_max_response_size_kb`
- `proxy_safe_request_timeout_seconds`
- `proxy_safe_only_json`

## Security model

The endpoint is intentionally narrow:

- Only `http` and `https` URLs are accepted.
- The target host must be allowlisted.
- Host matching is controlled by `proxy_safe_subdomain_policy`.
- Localhost, loopback, link-local, and private-network targets can be blocked.
- The endpoint can be restricted to logged-in users or valid sessions.
- Per-user or per-IP rate limiting is applied.
- JSON-only upstream responses are recommended and enabled by default.

## Subdomain policy

`proxy_safe_subdomain_policy` supports:

- `exact_only` — only the listed hosts are allowed
- `always_include_subdomains` — any subdomain of a listed host is also allowed

Example allowlist entries:

- `meta.discourse.org`
- `forum.example.com`

With `always_include_subdomains`, a listed host like `example.com` would also
permit `sub.example.com`.

## Endpoint

```text
/discourse-proxy-safe/fetch.json?url=https%3A%2F%2Fmeta.discourse.org%2Ft%2Ftopic-slug%2F123.json
```

## Expected theme-component alignment

If you use this plugin with `discourse-rich-previews`, keep the host allowlist
in sync with the remote host configuration used by the theme component’s remote
topic provider.

A host should be allowed by both:

- the theme component’s remote preview provider configuration
- this plugin’s `proxy_safe_allowed_domains` setting

## Response behavior

- `200` for successful proxied responses
- `400` for missing or invalid URL input
- `403` for blocked hosts, localhost/private-network targets, or insufficient access
- `429` for rate limit violations
- `502` for upstream timeout, invalid upstream content type, oversized response, or unsupported upstream status
- `500` for unexpected internal errors

## Testing

This plugin has request specs covering the split proxy contract:

- `GET /discourse-proxy-safe/fetch.json` for strict JSON-only remote topic proxying.
- `GET /discourse-proxy-safe/fetch_external.json` for broader external webpage proxying (`text/html`, `text/plain`, and JSON).

### What the specs cover

The request specs verify:

- allowlist enforcement
- access-level enforcement
- rate limiting
- maximum response size handling
- cache separation between the two routes
- upstream status passthrough for supported statuses
- strict content-type rejection on the JSON route
- broader content-type acceptance on the external route
- outbound `Accept` header behavior for each route

### Spec files

Expected spec files:

- `spec/requests/discourse_proxy_safe/proxy_controller_spec.rb`
- `spec/requests/discourse_proxy_safe/proxy_accept_headers_spec.rb` (optional, if kept as a separate focused spec)

### Run just this plugin's request specs

From the main Discourse app root:

```bash
bundle exec rspec plugins/discourse-proxy-safe/spec/requests/discourse_proxy_safe/proxy_controller_spec.rb
```

Run the companion outbound-header spec:

```bash
bundle exec rspec plugins/discourse-proxy-safe/spec/requests/discourse_proxy_safe/proxy_accept_headers_spec.rb
```

Run both together:

```bash
bundle exec rspec \
  plugins/discourse-proxy-safe/spec/requests/discourse_proxy_safe/proxy_controller_spec.rb \
  plugins/discourse-proxy-safe/spec/requests/discourse_proxy_safe/proxy_accept_headers_spec.rb
```

### Recommended local workflow

1. Run the proxy request specs after any change to:
   - `config/routes.rb`
   - `app/controllers/discourse_proxy_safe/proxy_controller.rb`
   - caching logic
   - allowlist or access-level behavior
   - content-type validation
2. Re-run after any route rename in the plugin or provider endpoint change in the theme component.
3. Treat failures in the outbound `Accept` header assertions as compatibility regressions, because they directly affect whether remote-topic previews stay JSON-strict while external previews remain HTML-capable.

### Notes

- The JSON route should reject upstream HTML responses with `502`.
- The external route should accept upstream `text/html`, `text/plain`, and JSON responses.
- Cache keys should remain route-specific so the same upstream URL cannot poison the cache across fetch modes.
- If authentication helpers differ in a custom test setup, only the sign-in lines may need local adjustment; the request-spec structure should remain the same.
