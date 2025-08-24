---
title: "Talos + Terraform: ♥️"
date: 2025-08-05
summary: "My experience with Talos and Terraform"
tags:
  - Talos
  - Kubernetes
  - Terraform
  - Infrastructure-as-Code
  - Homelab
featuredImage: "featured.png"
---

<div class="translation-note" style="background:#ffeeba; color:#856404; padding:1em; border-radius:6px; margin-bottom:2em;">
  <strong>Note:</strong> This article was translated from French to English by an AI. Some nuances may differ from the original.
</div>

# Introduction

For the past few months, I’ve been deeply interested in **Talos**, a minimalist operating system designed specifically for Kubernetes.

I installed my first Talos cluster in **December 2024**, and since then, my “production” — made up of two physical servers running **Proxmox** — has been running with this stack.

After several months of experimentation, I decided to share my feedback, especially on integrating **Talos with Terraform** to provision and manage my clusters declaratively.

---

## 🤖 What is Talos?

**Talos** is an immutable, ultra-minimalist Linux OS, fully dedicated to Kubernetes.
Forget classic distributions: no shell, no package manager, no unnecessary attack surface.

Imagine an OS that boots directly with Kubernetes preconfigured! That’s exactly what Talos is. No need to install Docker, containerd, or configure systemd — everything is already integrated and optimized.

This streamlined design brings several advantages:

- ⚡️ **Installation in minutes**: no more hours spent configuring each node
- 🔐 **Administration only via a dedicated API**: no more risky SSH connections
- 🛡️ **Enhanced security**: minimal attack surface, read-only system

Even without SSH, the `talosctl` tool lets you manage everything remotely:

- 📜 Access system logs (like `journalctl`, but better)
- 🌐 Collect network reports (`pcap` for debugging network issues)
- 🩺 Complete node diagnostics
- 🔄 Declarative system updates (just like Kubernetes!)

**SideroLabs**, the company behind Talos, provides excellent documentation, and the community is active. It’s a mature project, used in production by many organizations — not just a homelab toy!

---

## 🏗️ Why Terraform with Talos?

I was already using **Terraform** to provision my VMs on Proxmox. So I thought: _“Why not go further and manage Talos configs with Terraform too?”_

The idea might seem crazy at first — after all, Talos has its own tools. But in reality, this approach completely revolutionizes the workflow!

The goal: automate **everything** in the cluster lifecycle, from boot to app deployment.

What this approach brings me concretely:

- 🔧 **Version control** for all my configs in Git (no more scattered YAML files)
- 📦 **Integrate my Helm charts** right from initialization (Cilium, ArgoCD, cert-manager… all at once)
- 🚀 **Automatic cluster bootstrap** (completely hands-off startup)
- 🔁 **100% reproducible deployment** (even after a full homelab wipe at 2am)

The idea is to have a **production-ready Kubernetes cluster from the first boot**:
with `Cilium` as CNI, `ArgoCD` for GitOps, SSL certificate management, and all my favorite tools already in place. No more remembering the installation order!

---

# 🛠️ Setting up Talos without Terraform

Before diving into Terraform magic, let’s see how Talos works “by hand.” It’s important to understand the basics!

To bootstrap a classic Talos cluster, use this command:

```bash
talosctl gen config talos-proxmox-cluster https://$CONTROL_PLANE_IP:6443 --output-dir _out
```

**Breakdown of this command:**

- `talos-proxmox-cluster`: your cluster name (choose something meaningful!)
- `https://$CONTROL_PLANE_IP:6443`: the URL where the Kubernetes API will be accessible (replace with your IP)
- `--output-dir _out`: the folder where all files will be generated

In the `_out/` folder, you’ll find three essential files:

- `controlplane.yaml` — The recipe for your control plane nodes
- `worker.yaml` — The configuration for worker nodes (the cluster’s workforce)
- `talosconfig` — Your master key for talking to `talosctl`

These files contain **all your cluster’s secrets**: certificates, keys, tokens… Keep them safe!

---

## ✍️ Important Configuration Fields

Let’s get to the heart of the matter! Here are the crucial sections of the Talos config:

### 1. Cluster Configuration

```yaml
cluster:
  clusterName: talos-proxmox-cluster
  controlPlane:
    endpoint: https://$CONTROL_PLANE_IP:6443
  network:
    dnsDomain: cluster.local
    podSubnets:
      - 10.244.0.0/16
    serviceSubnets:
      - 10.96.0.0/12
```

**Explanations:**

- `clusterName`: your cluster’s nickname (visible in `kubectl config`)
- `endpoint`: address to access the Kubernetes API from outside
- `dnsDomain`: internal DNS suffix (usually `cluster.local`)
- `podSubnets`: network for your pods (avoid conflicts with your LAN!)
- `serviceSubnets`: network for Kubernetes services

### 2. Machine Configuration

```yaml
machine:
  type: controlplane # or worker
  token: wNf8GvZz... # Machine authentication token
  ca:
    crt: LS0tLS1CRU... # Cluster root CA certificate
    key: LS0tLS1CRU... # CA private key (sensitive!)
  certSANs:
    - $CONTROL_PLANE_IP
  kubelet:
    image: ghcr.io/siderolabs/kubelet:v1.x.x
```

**What’s happening here:**

- `type`: defines the machine’s role (controlplane = conductor, worker = executor)
- `token`: shared secret for machines to recognize each other
- `ca.crt` and `ca.key`: cluster root certificates (protect them like your eyes!)
- `certSANs`: IP/DNS addresses allowed for the API (important to avoid certificate errors)
- `kubelet.image`: kubelet version to use

---

## 🧩 inlineManifests: The Magic of Automatic Deployment

`inlineManifests` are **THE killer feature** of Talos! They let you apply Kubernetes manifests **at cluster startup**.

Basically? Your cluster starts with Cilium, ArgoCD, and all your tools already installed. No more running 15 `kubectl apply` after each bootstrap!

Here’s a basic example with Flannel (network CNI):

```yaml
cluster:
  inlineManifests:
    - name: "flannel"
      contents: |
        ---
        apiVersion: apps/v1
        kind: DaemonSet
        metadata:
          name: kube-flannel-ds
          namespace: kube-system
        spec:
          selector:
            matchLabels:
              app: flannel
          # ... rest of Flannel config
```

**How does it work?**

1. Talos boots and initializes Kubernetes
2. As soon as the API is available, it automatically applies all `inlineManifests`
3. Your cluster is immediately operational with your favorite stack!

The huge advantage: **total reproducibility**. Every time you bootstrap the cluster, you get exactly the same thing.

---

# 📦 The Magic Trick: Inline Manifests (with Terraform this time!)

Now that we’ve seen the basics, let’s level up! The brilliant idea is to **dynamically generate** these manifests via Terraform and Helm.

Instead of manually writing hundreds of YAML lines (hello maintenance hell), let Helm do the job and Terraform orchestrate everything.

---

## 🌐 Terraform Providers Used

For this adventure, I need two Terraform providers:

```hcl
terraform {
  required_version = ">= 1.10.0"
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "0.8.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.0.2"
    }
  }
}
```

**Why these two?**

- **`talos` provider**: created by SideroLabs, lets you generate Talos machine configs directly in Terraform
- **`helm` provider**: templates Helm charts like Cilium or ArgoCD **without deploying** (we just want the final YAML)

This combo is magic: Helm generates the perfect YAML for each chart, and the Talos provider injects it into `inlineManifests`!

---

## 🔌 Provisioning Cilium with Helm + Terraform

**Cilium** is my CNI of choice (Container Network Interface). It manages the network between pods and Kubernetes services. Here’s how I integrate it into my Talos configs:

```hcl
locals {
  # Some custom manifests Helm can't generate
  cilium_manifest_objects = [
    # Load Balancer to expose services on my LAN
    {
      apiVersion = "cilium.io/v2alpha1"
      kind       = "CiliumL2AnnouncementPolicy"
      metadata = {
        name = "external"
      }
      spec = {
        loadBalancerIPs = true
        interfaces = ["eth0"]
        nodeSelector = {
          matchExpressions = [
            {
              key      = "node-role.kubernetes.io/control-plane"
              operator = "DoesNotExist"
            }
          ]
        }
      }
    },
    # IP pool for the load balancer
    {
      apiVersion = "cilium.io/v2alpha1"
      kind       = "CiliumLoadBalancerIPPool"
      metadata = {
        name = "external"
      }
      spec = {
        blocks = [
          {
            start = "10.10.1.10"  # First available IP
            stop  = "10.10.1.15"  # Last available IP
          }
        ]
      }
    }
  ]
  # Convert to YAML for inlineManifests
  cilium_external_lb_manifest = join("---\n", [for d in local.cilium_manifest_objects : yamlencode(d)])
}

# The magic: Helm generates the full Cilium manifest
data "helm_template" "cilium" {
  namespace    = "kube-system"
  name         = "cilium"
  repository   = "https://helm.cilium.io"
  chart        = "cilium"
  version      = "1.18.0"
  kube_version = var.kubernetes_version
  values       = [file("${path.module}/helm/cilium-values.yaml")]
}
```

**What’s happening here:**

1. **`locals`**: I define specific Cilium resources that the standard Helm chart doesn’t handle (like the L2 load balancer)
2. **`data "helm_template"`**: Terraform asks Helm to generate all the Cilium YAML, but **without deploying**
3. **`values`**: I use a `cilium-values.yaml` file to customize Cilium (enable Hubble, network config, etc.)

The result? Perfect YAML, tested by the Cilium community, but customized for my environment!

---

# 🧱 Bootstrapping Machine Configs with Terraform

Now, the main course! Here’s how I generate Talos configs with Terraform:

```hcl
resource "talos_machine_secrets" "talos" {
  talos_version = "v${var.talos_version}"
}
```

This resource generates **all the secrets** needed for the cluster: CA certificates, authentication tokens, encryption keys… It’s the equivalent of `talosctl gen config` but in Terraform.

Then, I define the control plane configuration:

```hcl
data "talos_machine_configuration" "controller" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.cluster_vip}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.talos.machine_secrets

  # Basic network config common to all machines
  config_patches = [
    yamlencode(local.common_machine_config),
    # Control plane-specific config: VIP for high availability
    yamlencode({
      machine = {
        network = {
          interfaces = [{
            interface = "eth0"
            vip = {
              ip = var.cluster_vip  # Virtual IP shared between control planes
            }
          }]
        }
      }
    }),
    # THE BIG PART: inlineManifests with Cilium
    yamlencode({
      cluster = {
        inlineManifests = [
          {
            name     = "cilium"
            contents = join("---\n", [
              data.helm_template.cilium.manifest,  # YAML generated by Helm
              "# Custom load balancer config\n${local.cilium_external_lb_manifest}",
            ])
          }
        ]
      }
    })
  ]
}
```

**Explanation:**

- `cluster_endpoint`: VIP (Virtual IP) shared between all control planes
- `config_patches`: YAML modifications applied on top of the base config
- The **VIP** allows multiple control planes behind one IP (high availability)
- **`inlineManifests`** injects Cilium YAML directly into the Talos config

And now, applying these configs to the actual machines:

```hcl
# Apply config to each control plane
resource "talos_machine_configuration_apply" "controller" {
  count                       = var.controller_count
  client_configuration        = talos_machine_secrets.talos.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controller.machine_configuration
  endpoint                    = local.controller_nodes[count.index].address
  node                        = local.controller_nodes[count.index].address

  # Machine-specific patch (hostname, DNS, NTP)
  config_patches = [
    yamlencode({
      machine = {
        network = {
          hostname    = local.controller_nodes[count.index].name  # talos-cp-01, talos-cp-02, etc.
          nameservers = var.dns_serveurs                          # My local DNS
        }
        time = {
          servers = var.ntp_serveurs                              # NTP servers for sync
        }
      }
    }),
  ]
}

# Same for workers (but without VIP and inlineManifests)
resource "talos_machine_configuration_apply" "worker" {
  count                       = var.worker_count
  client_configuration        = talos_machine_secrets.talos.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  endpoint                    = local.worker_nodes[count.index].address
  node                        = local.worker_nodes[count.index].address

  config_patches = [
    yamlencode({
      machine = {
        network = {
          hostname    = local.worker_nodes[count.index].name
          nameservers = var.dns_serveurs
        }
        time = {
          servers = var.ntp_serveurs
        }
      }
    }),
  ]
}
```

**What happens concretely:**

1. Terraform generates the Talos config with Cilium integrated
2. For each machine, it applies this config + specific patches (name, DNS, NTP)
3. Each node reboots with its new configuration
4. At boot, Talos automatically applies Cilium via `inlineManifests`
5. The cluster is operational with the network configured!

---

# 🔧 Cluster Upgrade via Terraform

## 🆙 How I Manage Upgrades

No more upgrades that give you cold sweats! With Terraform + Talos, it’s surprisingly simple.

In my variables file, I just have:

```hcl
variable "kubernetes_version" {
  description = "Kubernetes version to deploy"
  type        = string
  default     = "v1.33.3"
}
```

**Upgrade workflow:**

1. I change the version in my variable: `v1.33.2` → `v1.33.3`
2. I run `terraform plan` to see what will change
3. I run `terraform apply`
4. Talos automatically detects the version difference
5. It upgrades node by node, in rolling update

That’s it! No weird bash scripts, no commands to remember, no risk of forgetting a node.

## ✅ My Experience After Many Upgrades

**What I love about this approach:**

- **Progressive and automated updates**: Talos upgrades one node at a time, waits for stability, then moves to the next
- **Zero downtime**: with multiple control planes and workers, my apps keep running
- **Easy rollback**: if things go wrong, I revert to the old version and `terraform apply`
- **Terraform keeps state up to date**: never out of sync between my files and reality

A concrete example:
I recently upgraded from Kubernetes 1.32 to 1.33. The process took about 20 minutes for a 5-node cluster, and I had zero service interruption.

### ⚠️ Points to Watch (Lessons Learned)

- **Always read release notes**: sometimes there are breaking changes (especially between major versions)
- **Test on a dev cluster first**: This can be done easily locally
- **Backup configs beforehand**: `git commit` all your Terraform configs
- **Monitor logs during upgrade**: `talosctl logs -f` on each node to see if everything goes well
- **Set aside time**: even if automated, stay available to monitor

---

# 📁 My Homelab in Practice

If you want to see all this in action, I’ve put **all my code** open source! You’ll find:

- Complete Terraform configurations
- Helm values files for each chart
- My automation scripts
- Documentation to reproduce at home

[**florianspk/home-lab-talos** on GitHub](https://github.com/florianspk/home-lab-talos)

**What you’ll find concretely:**

- Proxmox + Terraform config to create VMs
- Full Talos bootstrap with Cilium, ArgoCD, cert-manager
- Ingress with Traefik and auto SSL certificates
- Examples of apps deployed via GitOps

Feel free to check it out, and a star ⭐️ is always appreciated (and helps others discover the project)!

---

# 🎉 One Year with Talos + Terraform: The Verdict

## ✅ The Positives (and there are many!)

- **Disarming simplicity**: no more OS to patch, configure, maintain
- **Enhanced security**: immutable system, minimal attack surface, no shell
- **Modern administration**: everything via the API with `talosctl` (no more risky SSH)
- **Stress-free upgrades**: automatic rolling updates, easy rollback
- **Top-notch Terraform + Helm integration**: Infrastructure as Code at its best
- **Perfect reproducibility**: I can rebuild my identical cluster in 30 minutes
- **Active community**: excellent docs, responsive support

## 🤔 Some Drawbacks (Let’s Be Honest)

- **Learning curve**: switching from traditional SSH to API-only requires a change in habits
- **Debugging sometimes less obvious**: when something goes wrong, you need to learn Talos-specific tools
- **Still a young ecosystem**: fewer tutorials and examples than for Kubernetes with kubeadm or others

## 🚀 My Tips for Getting Started

1. **Start with a small cluster**: 1 control plane + 1 worker in VMs
2. **Master `talosctl`**: take time to explore all commands
3. **Manage your configs with Terraform from the start**: don’t wait until you have 10 manual clusters
4. **Integrate your Helm charts into inlineManifests**: that’s where the magic happens

## 🔮 What’s Next?

This **Talos + Terraform + Helm** stack has truly revolutionized how I manage my clusters. But I’m not stopping here!

**Next step**: explore **Omni**, SideroLabs’ SaaS tool for managing Talos clusters. The idea: a web interface to control all my Talos clusters, with upgrade management, integrated monitoring, and multi-cloud deployment.

If you’re starting your Talos journey, feel free to share your feedback! I’m always curious to see how others use this stack.