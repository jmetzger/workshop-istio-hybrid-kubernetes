# Dual stack on the VM: DUAL_STACK and ISTIO_DUAL_STACK

![On the VM: DUAL_STACK sets the iptables rules, ISTIO_DUAL_STACK sets the rules and moves the ports of the sidecar to IPv6](../images/dual-stack-switches.svg)

## The short version

* Our Kubernetes clusters run IPv6 single stack, but **the lab VM has two addresses**: an IPv6 address and a private IPv4 address (`100.65.x.x`) that is not routed. Istio sees two address families and treats the VM as a dual stack workload.
* A dual stack workload needs a dual stack setting in the file `/var/lib/istio/envoy/cluster.env`. Without it the IPv6 traffic of the VM does not go through Envoy, and calls from a pod fail with `503`.
* **One line is enough.** `ISTIO_DUAL_STACK='true'` is written into `cluster.env` by `istioctl` (if `istiod` already has the setting). `DUAL_STACK='true'` does the same for the traffic. You do not need both.
* Always set `ISTIO_SVC_IP` as well (see [exercise](01-add-a-vm-to-the-mesh.md)), otherwise the sidecar may register the IPv4 address.

## Why: the VM has an IPv4 address

On Hetzner every server gets a private IPv4 address by DHCP, even if you create it without IPv4. There is no default route for it. Look at your VM:

```
ssh $VM "ip -o addr show scope global | awk '{print \$2, \$3, \$4}'"
ssh $VM "ip -4 route"
```

```
eth0 inet 100.65.9.93/32
eth0 inet6 2a01:4f8:c013:541::1/64
169.254.169.254 via 172.31.1.1 dev eth0 proto dhcp src 100.65.9.93 metric 100
172.31.1.1 dev eth0 proto dhcp scope link src 100.65.9.93 metric 100
188.40.24.200 via 172.31.1.1 dev eth0 proto dhcp src 100.65.9.93 metric 100
```

There is no line starting with `default`: IPv4 does not reach anywhere. But Istio looks at the addresses, not at the routes. In the Istio code (`DiscoverIPMode`, `pkg/model/proxy.go`) the mode of a workload is:

| Addresses of the VM | Mode |
|---|---|
| only IPv4 | IPv4 |
| only IPv6 | IPv6 |
| both | **Dual** |

Our VM is in the mode Dual. The sidecar then needs the dual stack settings.

## What each name does (measured)

We started the sidecar on the lab VM with each variant. Before each start we stopped the sidecar and removed all old rules. Then we looked at the real state (`ip6tables-save`, `ss -ltnp`) and called the VM three times from a pod.

| `cluster.env` contains | IPv6 rules | Envoy admin `15000` | Ports `15021` and `15090` | Call |
|---|---|---|---|---|
| nothing | 0 | `127.0.0.1` | `0.0.0.0` only | `503` (3 of 3) |
| `DUAL_STACK='true'` | 19 | `127.0.0.1` | `0.0.0.0` only | `200` (3 of 3) |
| `ISTIO_DUAL_STACK='true'` | 19 | `[::1]` only | `0.0.0.0` **and** `[::]` | `200` (3 of 3) |
| both | 19 | `[::1]` only | `0.0.0.0` **and** `[::]` | `200` (3 of 3) |

* **`DUAL_STACK`** sets only the iptables rules (`ip6tables`): IPv6 traffic is redirected to Envoy. The ports of the sidecar itself stay on IPv4.
* **`ISTIO_DUAL_STACK`** sets the same rules **and** moves the ports of the sidecar to IPv6 (Envoy admin on `[::1]`, `15021` and `15090` on `[::]`, too).
* Both lines together behave like `ISTIO_DUAL_STACK` alone.
* The DNS proxy (`15053`) stays on `127.0.0.1`, the status port `15020` of `pilot-agent` listens on all addresses in every case.

How it looks in the Istio code (version 1.29.9):

* The tool `pilot-agent istio-iptables` has the flag `--dual-stack`. It reads the environment variables `DUAL_STACK` **and** `ISTIO_DUAL_STACK`: two names for the same switch (`tools/istio-iptables/pkg/cmd/root.go`). `istio-start.sh` reads `cluster.env` with `set -a`, so every line in the file is an environment variable.
* `ISTIO_DUAL_STACK` is also read by the agent for the setup of Envoy (`pkg/bootstrap/config.go`, `pilot/pkg/features/experimental.go`, default `false`). With mixed addresses it takes the address family of the first address as the main family. That is why the admin port moves to `[::1]`.

Look at the file and at the real state yourself:

```
ssh $VM "grep -E 'DUAL_STACK|ISTIO_SVC_IP' /var/lib/istio/envoy/cluster.env"
ssh $VM "echo \"IPv4: \$(iptables-save -t nat | grep -c ISTIO)  IPv6: \$(ip6tables-save -t nat | grep -c ISTIO)\""
ssh $VM "ss -ltnp | grep -E ':150[0-9][0-9] ' | awk '{print \$4, \$NF}' | sort -t: -k2 -n"
```

```
ISTIO_DUAL_STACK='true'
ISTIO_SVC_IP='2a01:4f8:c013:541::1'
DUAL_STACK='true'
IPv4: 23  IPv6: 19
```

IPv4 rules are always set (the tool never sets IPv6 rules alone). With working dual stack you see 23 IPv4 and 19 IPv6 rules.

`pilot-agent istio-iptables --dry-run` prints what it would do and changes nothing. Counting the lines with `ip6tables` shows the effect of a name without touching the VM:

```
ssh $VM "pilot-agent istio-iptables --dry-run 2>&1 | grep -c ip6tables"
ssh $VM "DUAL_STACK=true pilot-agent istio-iptables --dry-run 2>&1 | grep -c ip6tables"
ssh $VM "ISTIO_DUAL_STACK=true pilot-agent istio-iptables --dry-run 2>&1 | grep -c ip6tables"
```

```
0
1
1
```

## The health probe (`probe` in the WorkloadGroup)

A `probe` in the `WorkloadGroup` is a health check for the VM. It is **not** run by Envoy but by the `pilot-agent` on the VM. The agent checks two things: is Envoy ready (it asks the admin port `15000`) and does the application answer the `probe`. It reports the result to `istiod`. `istiod` sets `Healthy` in the `WorkloadEntry` and removes an unhealthy VM from the lists it sends to the other sidecars.

In the mode Dual the agent uses IPv4 addresses for its checks: `127.0.0.1` for the admin port and `127.0.0.6` as source address of the probe. The default target of the probe is the first address of the VM, our IPv6 address. That causes two problems. We tested a `probe` with `httpGet` on port 8000 (app: Python echo server on `::`, which also accepts IPv4):

| `cluster.env` | `probe` | App running | App stopped | App started again |
|---|---|---|---|---|
| `ISTIO_DUAL_STACK` | standard | `Healthy=False`, `503` | `Healthy=False`, `503` | `Healthy=False`, `503` |
| `DUAL_STACK` | standard | `Healthy=False`, `503` | `Healthy=False`, `503` | `Healthy=False`, `503` |
| `DUAL_STACK` | `host: 127.0.0.1` | **`Healthy=True`, `200`** | `Healthy=False`, `503` | **`Healthy=True`, `200`** |

The agent log (`/var/log/istio/istio.log`) tells why:

* With `ISTIO_DUAL_STACK`: the admin port is only on `[::1]`, but the agent asks `http://127.0.0.1:15000/...`. The check of Envoy fails, the VM never gets healthy.
* With `DUAL_STACK` and the standard `probe`: `dial tcp: address 127.0.0.6:0: no suitable address found`. The agent connects from an IPv4 address to the IPv6 address of the VM.

So a `probe` on our VM works only with these three things together:

1. `DUAL_STACK='true'` in `cluster.env` (not `ISTIO_DUAL_STACK`),
2. `httpGet.host: 127.0.0.1` in the `probe`,
3. an application that also listens on IPv4.

```
  probe:
    periodSeconds: 3
    failureThreshold: 2
    httpGet:
      host: 127.0.0.1
      port: 8000
      path: /
```

We did not test `tcpSocket`, `exec` and `host: "::1"`. Without a `probe` there is no health check at all: a VM with a stopped application stays `HEALTHY` and calls fail with `503`.

## What the cluster provides: `istiod`

The listeners `15001` and `15006` of Envoy (inbound and outbound redirect) are not decided on the VM. `istiod` builds them. They exist on `[::]` only if `ISTIO_DUAL_STACK=true` is set in the environment of `istiod` (Helm value `pilot.env.ISTIO_DUAL_STACK`, default `false`). In a real environment this is part of the cluster provisioning (our lab script sets it in step 2 of the exercise).

| `istiod` | `cluster.env` | Envoy listens on (15001, 15006) | Call |
|---|---|---|---|
| on | a dual stack variable | `0.0.0.0` and `[::]` | `200` |
| on | nothing | `0.0.0.0` and `[::]` | `503` |
| off | a dual stack variable | `0.0.0.0` only | `503` |
| off | nothing | `0.0.0.0` only | `503` |

The variables on the VM do not change these two listeners, and the line `ISTIO_DUAL_STACK` in the file `mesh.yaml` of the VM made no difference either.

## What if the VM had no IPv4 address?

On Hetzner you cannot create such a VM. We removed the address by hand (`ip addr del`) to see what Istio does: the mode becomes IPv6, and everything worked **without** a dual stack variable on the VM, even with `ISTIO_DUAL_STACK` off in `istiod`: Envoy on `[::]`, the IPv6 rules were set by themselves (19, plus the always present 23 IPv4 rules), the `probe` with default values worked, and a stopped application made the `WorkloadEntry` `Healthy=False` (`503`), a started one `Healthy=True` (`200`).

So all the dual stack topics on this page come from the additional IPv4 address. We tested this only with the address removed by hand on one VM.

## What to take with you

* A VM with an IPv6 and an IPv4 address is in the mode Dual. It needs `ISTIO_DUAL_STACK='true'` or `DUAL_STACK='true'` in `cluster.env`, and `ISTIO_SVC_IP` for the right address.
* `DUAL_STACK` = the IPv6 rules and nothing else. `ISTIO_DUAL_STACK` = the IPv6 rules **and** the ports of the sidecar on IPv6.
* The `probe` is run by the `pilot-agent`. On a dual stack VM it needs `DUAL_STACK`, `host: 127.0.0.1` and an application that listens on IPv4.
* `ISTIO_DUAL_STACK` is also a setting of `istiod` (the IPv6 listeners). That part belongs to the cluster provisioning.
* If a VM fails with `503`, look at three things: the number of IPv6 rules (expected 19), the listeners (`[::]:15001` and `[::]:15006` must exist) and the `ADDRESS` of the `WorkloadEntry`.
