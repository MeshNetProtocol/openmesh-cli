# AGENTS.md instructions for /Users/wesley/MeshNetProtocol/openmesh-cli

<INSTRUCTIONS>
## Skills
A skill is a set of local instructions stored in a `SKILL.md` file. This repository contains project-local skills that Codex should use when the task matches their scope.

### Project-local skills
- `openmesh-v2-openrouter`: Use when working on OpenMesh V2 in `openmesh-apple/MeshFluxMac` or `openmesh-apple/docs/v2`, especially for OpenMesh UI, official limited access, DIY/private nodes, commercial providers, wallet/signer session, x402 payment flow, provider discovery, receipts, or V2 architecture updates. (file: `/Users/wesley/MeshNetProtocol/openmesh-cli/skills/openmesh-v2-openrouter/SKILL.md`)
- `openmesh-commercial-provider`: Use when designing or implementing the commercial-provider path for OpenMesh V2, including chain registry discovery, supplier metadata, user wallets, signer sessions, x402 automatic payments, bucket renewal, supplier receipts, or sing-box data-plane integration for paid provider switching. (file: `/Users/wesley/MeshNetProtocol/openmesh-cli/skills/openmesh-commercial-provider/SKILL.md`)
- `openmesh-wallet-signer-session`: Use when designing or implementing OpenMesh wallet behavior, encrypted wallet storage, device-bound protection, signer sessions, auto-sign limits, unlock UX, or any x402 signing flow that touches mnemonic, private key, Keychain, Secure Enclave, or LocalAuthentication. (file: `/Users/wesley/MeshNetProtocol/openmesh-cli/skills/openmesh-wallet-signer-session/SKILL.md`)

## How to use skills
- Discovery: The skills above are repository-local skills. Read the `SKILL.md` only after deciding the task matches.
- Trigger rules: If the user names one of these skills, or the task clearly matches its description, you must use it for that turn. Multiple matches mean use the minimal set that covers the task.
- Coordination: Prefer the broad skill first and add narrower skills only when needed.
  For example:
  Use `openmesh-v2-openrouter` for general V2 work.
  Add `openmesh-commercial-provider` for the paid supplier path.
  Add `openmesh-wallet-signer-session` when wallet or signing safety is involved.
- Context hygiene: Do not bulk-load all V2 docs. Follow the reading rules inside the selected skill and load only the referenced docs needed for the current task.
- Source of truth: `openmesh-apple/docs/v2` remains the product and architecture source of truth. Skills are execution guides, not replacements for the docs.
- Safety: If a proposed change conflicts with the V2 docs or a selected skill, stop and align with the documented architecture before editing code.
</INSTRUCTIONS>
