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

This repository uses Discourse’s shared reusable GitHub Actions workflow for primary plugin CI:

- `.github/workflows/discourse-plugin.yml`
- `uses: discourse/.github/.github/workflows/discourse-plugin.yml@v1`

That workflow should remain the main CI entry point for full plugin validation.

### Proxy request specs

This plugin also includes focused request specs for the split proxy design:

- `GET /discourse-proxy-safe/fetch.json` for strict JSON-only remote-topic proxying
- `GET /discourse-proxy-safe/fetch_external.json` for broader external webpage proxying

Recommended spec files:

- `spec/requests/discourse_proxy_safe/proxy_controller_spec.rb`
- `spec/requests/discourse_proxy_safe/proxy_accept_headers_spec.rb`

These specs cover:

- route behavior
- allowlist enforcement
- access-level enforcement
- rate limiting
- maximum response size handling
- content-type validation
- cache separation between fetch modes
- outbound `Accept` header behavior for each route

### Running the focused proxy specs locally

From a Discourse-aware plugin test environment, run:

```bash
bundle exec rspec spec/requests/discourse_proxy_safe/proxy_controller_spec.rb
```

Run the companion header-focused spec:

```bash
bundle exec rspec spec/requests/discourse_proxy_safe/proxy_accept_headers_spec.rb
```

Run both together:

```bash
bundle exec rspec \
  spec/requests/discourse_proxy_safe/proxy_controller_spec.rb \
  spec/requests/discourse_proxy_safe/proxy_accept_headers_spec.rb
```

### CI strategy

Keep the shared Discourse plugin workflow for full plugin CI.

Because the shared reusable workflow does not currently expose an input for narrowing the rspec target, any faster proxy-only CI should be implemented as a separate supplemental workflow rather than by replacing or overloading the shared workflow.

### Maintenance note

If the proxy route names, provider endpoints, controller behavior, or content-type rules change, re-run these focused request specs immediately.

The split-route contract is intentional:

- `/fetch.json` must remain JSON-strict
- `/fetch_external.json` must remain broader for external webpage previews

A regression in content-type validation, cache separation, or outbound `Accept` headers can silently break previews.
