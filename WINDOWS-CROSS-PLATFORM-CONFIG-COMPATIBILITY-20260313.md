# Windows Cross-Platform Config Compatibility

## Outcome

The updated profile config is now verified on:

- Windows
- macOS
- iOS

The older profile config failed on Windows but could still work on Apple platforms.

## Root Cause

The primary incompatibility was in the profile itself, not in the intended routing behavior:

- Old tun IPv4 address: `172.18.0.1/30`
- `route_exclude_address` included: `172.16.0.0/12`

On Windows native tun with `auto_route=true`, sing-box infers the tun DNS peer as `172.18.0.2`.
Because `172.18.0.2` falls inside `172.16.0.0/12`, Windows installs an excluded route for that
destination via the physical NIC. DNS queries to the tun DNS server never enter the tunnel and
time out.

This is why the old profile showed:

- DNS timeout to `172.18.0.2:53`
- polluted or unrelated destination IPs for Google, YouTube, Gemini, and OpenAI domains

## Why Apple Platforms Could Still Work

Apple platforms do not rely on the same Windows native tun routing path. Their NetworkExtension-based
integration does not expose the same failure mode around excluded system routes to the inferred tun DNS
peer address.

That means the older profile was not truly cross-platform safe. It was only not failing on Apple.

## Config Changes That Made The Profile Portable

The working config made these profile-level changes:

- `dns.strategy = "ipv4_only"`
- tun IPv4 address changed to `198.18.0.1/15`
- tun IPv6 address changed to `fdfe:dcba::1/126`
- `route.rules` moved `action: sniff` before `action: hijack-dns`

These changes are now validated across Windows, macOS, and iOS.

## Code Policy

Windows should not silently rewrite profile semantics at runtime.

The Windows embedded core now follows these rules:

- preserve provider/profile config fields instead of deleting them
- do not rewrite tun address, DNS strategy, or route rule ordering at runtime
- emit compatibility warnings for suspicious Windows-native tun configs
- fail fast on Windows when a tun address overlaps `route_exclude_address`

## Practical Rule

For cross-platform sing-box profiles used with Windows native tun:

- do not place `tun.address` inside any `route_exclude_address` range
- prefer `198.18.0.0/15` for IPv4 tun addressing
- keep DNS behavior explicit in the profile
- ensure `sniff` appears before `hijack-dns` in `route.rules`
