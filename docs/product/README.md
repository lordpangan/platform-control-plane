# Who this platform is for (the product brief)

A platform is a **product**, and a product has **users** and **needs**. This
project is not "spin up cool tools." It's "build the paved road a specific team
actually needs." Everything in the [roadmap](../../../ROADMAP.md) should trace
back to a need on this page. If a tool doesn't serve a need here, we don't build
it.

> The org and people below are **fictional but realistic** — a stand-in for a
> real internal-platform customer. Swap in your own if you have a real one.

## The company: "Meridian"

Meridian is a mid-size SaaS company (~120 engineers) in a regulated space
(payments-adjacent, so security and audit matter). Engineering is organized into
**~6 stream-aligned product teams**, each owning a few HTTP services. There is no
platform team yet — which is the problem.

### The pain today (why we're building this)

- **Every team reinvents the same plumbing.** Deployment, autoscaling, ingress,
  metrics, and policy are hand-rolled per team, inconsistently. Shipping a *new*
  service takes 2–3 weeks of copy-pasting another team's YAML.
- **Security is bolted on, not built in.** Some services run `:latest`, some have
  no resource limits, some run privileged. The security lead finds this in review,
  after the fact, service by service. It doesn't scale and it fails audits.
- **Ops is quietly a ticket queue.** The two most senior infra engineers spend
  their days provisioning databases and clusters for other teams. That's the
  DevOps failure mode we're trying to kill.
- **No one can answer fleet questions.** "Which services are on an old base
  image?" "Who owns this?" "What's our deploy frequency?" — nobody knows.

## The users (personas)

### Dana — product engineer (the primary user)
Ships features on a stream-aligned team. Knows her language and framework well;
does **not** want to learn Kubernetes networking, IAM trust policies, or Helm
templating to deploy a REST API.
- **Wants:** describe her app in a few lines, get a running, monitored service.
- **Success looks like:** idea → running in prod in an afternoon, not weeks.
- **Drives:** the golden path (Phase 5), Backstage front door (Phase 8),
  monitoring-by-default (Phase 7).

### Ravi — team lead / on-call
Owns a team's services and carries the pager. Wants consistency and a safe way to
ship and roll back. Doesn't want to be paged for platform problems he can't fix.
- **Wants:** the same reliable deploy/rollback for every service; clear ownership.
- **Success looks like:** a bad deploy rolls itself back before it pages him.
- **Drives:** progressive delivery + auto-rollback (Phase 9), SLOs (Phase 7),
  the service catalog (Phase 8).

### Priya — security & compliance lead (the differentiator)
Accountable for the platform passing audits. Today she nags in code review; she
wants the rules enforced automatically so "compliant" is the default, not a
checklist.
- **Wants:** no `:latest`, resource limits required, no privileged containers —
  enforced by the system, with audit evidence.
- **Success looks like:** an unsafe deploy is blocked automatically, no human in
  the loop, and there's a signed record of it.
- **Drives:** guardrails (Phase 6), policy-as-code, supply-chain security.

### Sam — the platform engineer (that's us / the builder)
Not a customer — the product owner. Success is measured by **adoption**, not by
how much tech got deployed.

## What "good" means (how we'll measure it)

- **Time-to-first-deploy** — a new service from request to prod. Target: minutes.
- **Adoption** — % of services on the golden path (a countable annotation, not a
  vibe). If adoption is low, the platform is wrong, not the users.
- **Cognitive load** — a new engineer deploys to prod on day one having learned
  **one** interface.
- **Guardrail coverage** — unsafe changes blocked automatically, with evidence.

## What this is NOT (non-goals)

- Not a mandate. The golden path is **paved, not walled** — teams *can* leave,
  they just lose the support guarantees.
- Not a black box. Kubernetes is hidden in *authoring*, but exposed in
  *debugging* (see [ADR 0002](../adr/0002-backstage-front-door-repo-escape-hatch.md)).
- Not every workload — we pave the common case (an HTTP service), on purpose, and
  invest deeply there.
