# Kubernetes Bootstrap Toolkit (`k8s-bootstrap-toolkit`)

[![Kubernetes Version](https://img.shields.io/badge/kubernetes-v1.28%2B-blue.svg)](https://kubernetes.io/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform Engineering](https://img.shields.io/badge/Platform-Engineering-orange.svg)](#)

A production-ready foundation and bootstrap architecture for Kubernetes clusters. This repository provides foundational manifests, infrastructure definitions, network policy enforcement, zero-trust configurations, and automation scripts to bootstrap modern cloud-native environments.

---

## Architecture Overview

The toolkit implements a layered platform engineering architecture adhering to the principle of least privilege, zero-trust network segmentation, and automated GitOps/declarative workflows.

```mermaid
flowchart TD
    subgraph External ["External Traffic"]
        Client["Clients & Users"]
        LE["Let's Encrypt ACME"]
    end

    subgraph Cluster ["Kubernetes Cluster"]
        subgraph IngressLayer ["Ingress & TLS Layer"]
            Traefik["Traefik Ingress Controller\n(v3.x / Proxy Protocol)"]
            CertManager["cert-manager\n(ClusterIssuer)"]
        end

        subgraph CorePlatform ["Platform Services"]
            CoreDNS["CoreDNS\n(kube-system)"]
        end

        subgraph ProdNamespace ["Namespace: production (PSS: Restricted)"]
            NP["Default-Deny Ingress/Egress\nNetworkPolicies"]
            App["Workload Pods\n(Non-root, Read-only FS)"]
        end
    end

    Client -->|HTTPS (443)| Traefik
    LE <-->|HTTP-01 Challenge| CertManager
    CertManager -->|Issues TLS Secrets| Traefik
    Traefik -->|IngressRoute CRD| App
    App -.->|Port 53 UDP/TCP Allowed| CoreDNS
    NP -.->|Enforces Zero-Trust Boundary| App
```

### Key Pillars

1. **Defense-in-Depth & Pod Security Standards (PSS)**:
   - Namespaces are preconfigured with `pod-security.kubernetes.io/enforce: restricted`, mandating non-root execution, privilege escalation prevention, and read-only root filesystems.
2. **Zero-Trust Network Policies**:
   - Out-of-the-box `default-deny-all` ingress and egress network policies.
   - Granular egress rules for CoreDNS resolution (`kube-system`), with all unauthorized pod-to-pod and egress traffic blocked by default.
3. **Ingress & Edge Routing**:
   - Traefik Proxy configured for high availability, resource limits, structured JSON logging, Prometheus metrics, and native Kubernetes CRD support (`IngressRoute`).
4. **Automated Certificate Lifecycle**:
   - Automated issuance and renewal of TLS certificates via Let's Encrypt production ACME endpoints using `cert-manager`'s `ClusterIssuer`.
5. **Reproducible Cluster Bootstrapping**:
   - Idempotent bootstrap automation via `scripts/cluster-init.sh` supporting pre-flight checks, dry-run flags, and Helm chart orchestrations.

---

## Directory Structure

```text
k8s-bootstrap-toolkit/
├── README.md                                  # Platform overview, architecture, and guides
├── clusters/
│   └── base/
│       ├── namespace.yaml                     # Hardened production namespace with PSS Restricted
│       └── network-policies.yaml              # Default deny-all ingress/egress & baseline DNS egress
├── infrastructure/
│   ├── cert-manager/
│   │   └── cluster-issuer.yaml                # Let's Encrypt production ClusterIssuer (HTTP-01)
│   └── traefik/
│       ├── ingress-route.yaml                 # Sample Traefik IngressRoute CRD manifest
│       └── values.yaml                        # Production-ready Traefik Helm values configuration
└── scripts/
    └── cluster-init.sh                        # Bash cluster bootstrapping and verification script
```

---

## Prerequisites

Ensure the following client binaries are installed and accessible in your `$PATH`:

- **kubectl** (v1.28+)
- **helm** (v3.12+)
- **bash** (v4.0+)
- Active `kubeconfig` pointing to your target Kubernetes cluster with `cluster-admin` privileges.

---

## Quickstart & Deployment

### 1. Preflight Validation

Verify connectivity to your target cluster:

```bash
kubectl cluster-info
kubectl get nodes
```

### 2. Run the Initialization Script

Execute the bootstrap automation script to install prerequisites, core namespaces, network policies, and infrastructure controllers:

```bash
# Make executable if needed
chmod +x scripts/cluster-init.sh

# Run cluster initialization
./scripts/cluster-init.sh
```

To validate without applying changes, run with dry-run mode:

```bash
DRY_RUN=true ./scripts/cluster-init.sh
```

### 3. Deploy Application Ingress Route

Once Traefik and cert-manager are initialized, deploy the sample `IngressRoute`:

```bash
kubectl apply -f infrastructure/traefik/ingress-route.yaml
```

Inspect the route status:

```bash
kubectl get ingressroutes -n production
```

---

## Security & Compliance Notes

- **Pod Security Admission**: The `production` namespace enforces the Kubernetes `restricted` profile. Any pod running as root (`runAsUser: 0`) or requesting `hostPath` / privilege escalation will be rejected by the API server.
- **Network Segmentation**: All incoming and outgoing connections in `production` are severed by `default-deny-all`. When adding a microservice, provide an accompanying `NetworkPolicy` specifying explicit ingress/egress rules.
- **ACME Production Rate Limits**: The cluster issuer targets the Let's Encrypt production directory (`https://acme-v02.api.letsencrypt.org/directory`). When testing or iterating in development, switch the endpoint to the staging directory (`https://acme-staging-v02.api.letsencrypt.org/directory`) to avoid strict rate limits.
