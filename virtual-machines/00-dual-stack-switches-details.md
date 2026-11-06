# Dual stack on the VM: details and measurements

This page is the reference behind the short page [Dual stack on the VM: what to set](00-dual-stack-switches.md). It has all measurements, the checks and the places in the Istio code.

## The short version

* Our Kubernetes clusters run IPv6 single stack, but **the lab VM has two addresses**: an IPv6 address and a private IPv4 address (`100.65.x.x`) that is not routed. Istio sees two address families and treats the VM as a dual stack workload.
* A dual stack workload needs a dual stack setting in the file `/var/lib/istio/envoy/cluster.env`. Without it the IPv6 traffic of the VM does not go through Envoy, and calls from a pod fail with `503`.
* **One line is enough.** `ISTIO_DUAL_STACK='true'` is written into `cluster.env` by `istioctl` (if `istiod` already has the setting). `DUAL_STACK='true'` does the same for the traffic. You do not need both.
* Always set `ISTIO_SVC_IP` as well (see [optional exercise](02-add-a-vm-to-the-mesh-dual-stack-optional.md)), otherwise the sidecar may register the IPv4 address.

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

**Why would you want `ISTIO_DUAL_STACK` on the VM?** Only if something outside the VM must reach the own ports of the sidecar over IPv6. We tested this from a pod **without** sidecar in cluster a (IPv4 of the VM is not routed, so the only way in is IPv6):

| Port | Content | only `DUAL_STACK` | only `ISTIO_DUAL_STACK` |
|---|---|---|---|
| `15090` | Prometheus metrics of Envoy | no connection (curl exit 7) | `200` |
| `15021` | health/readiness of Envoy | no connection (curl exit 7) | `200` |
| `15020` | `pilot-agent` (agent metrics) | `200` | `200` |

A pod **with** sidecar reached all three ports in both cases. Its own Envoy changes the path, so use a pod without sidecar for this kind of test. Port `15020` works with either name. We did not check whether it also returns the Envoy metrics.

How it looks in the Istio code (version 1.29.9):

* The tool `pilot-agent istio-iptables` has the flag `--dual-stack`. It reads the environment variables `DUAL_STACK` **and** `ISTIO_DUAL_STACK`: two names for the same switch (`tools/istio-iptables/pkg/cmd/root.go`). `istio-start.sh` reads `cluster.env` with `set -a`, so every line in the file is an environment variable.
* (Code only, effect not tested) With `ISTIO_DUAL_STACK` the bootstrap of Envoy uses the DNS lookup family `ALL` for its own static clusters instead of `V4_ONLY`.
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

## Where the `ISTIO_DUAL_STACK` line in `cluster.env` comes from

`istioctl x workload entry configure` copies every entry of `proxyMetadata` from the mesh configuration (ConfigMap `istio` in `istio-system`, key `mesh`) into `mesh.yaml` and `cluster.env`. The `istiod` Helm chart (1.29.9) adds `ISTIO_DUAL_STACK` to that mesh configuration by itself when `pilot.env.ISTIO_DUAL_STACK=true` is set. We checked it with the values of the Helm release:

| `pilot.env.ISTIO_DUAL_STACK` | own `meshConfig...proxyMetadata.ISTIO_DUAL_STACK` | in the ConfigMap `istio` | line in the generated `cluster.env` |
|---|---|---|---|
| `true` | `true` | yes | yes |
| `true` | removed | yes | yes |
| `false` | `true` | yes | yes |
| `false` | removed | no | **no** |

So the line comes with `ISTIO_DUAL_STACK=true` in `istiod`, and our own `--set meshConfig...` in the exercise is not needed. If you want a `cluster.env` without the line (for the `probe`), you delete it by hand on the VM.

## The health probe (`probe` in the WorkloadGroup)

A `probe` in the `WorkloadGroup` is a health check for the VM. It is **not** run by Envoy but by the `pilot-agent` on the VM. The agent checks two things: is Envoy ready (it asks the admin port `15000`) and does the application answer the `probe`. It reports the result to `istiod`. `istiod` sets `Healthy` in the `WorkloadEntry` and removes an unhealthy VM from the lists it sends to the other sidecars.

In the mode Dual the agent uses IPv4 addresses for its checks: `127.0.0.1` for the admin port and `127.0.0.6` as source address of the probe. The default target of the probe is the address you gave as `ISTIO_SVC_IP` (the agent takes the first address of its list, and `ISTIO_SVC_IP` comes first), in our case the IPv6 address. That causes two problems. We tested a `probe` with `httpGet` on port 8000 (app: Python echo server on `::`, which also accepts IPv4):

| `cluster.env` | `probe` | App running | App stopped | App started again |
|---|---|---|---|---|
| `ISTIO_DUAL_STACK` | standard | `Healthy=False`, `503` | `Healthy=False`, `503` | `Healthy=False`, `503` |
| `DUAL_STACK` | standard | `Healthy=False`, `503` | `Healthy=False`, `503` | `Healthy=False`, `503` |
| `DUAL_STACK` | `host: 127.0.0.1` | **`Healthy=True`, `200`** | `Healthy=False`, `503` | **`Healthy=True`, `200`** |
| **both lines** | `host: 127.0.0.1` | `Healthy=False`, `503` | `Healthy=False`, `503` | `Healthy=False`, `503` |

The agent log (`/var/log/istio/istio.log`) tells why:

* With `ISTIO_DUAL_STACK` (alone or together with `DUAL_STACK`): the admin port is only on `[::1]`, but the agent asks `http://127.0.0.1:15000/...`. The check of Envoy fails, the VM never gets healthy, even with `host: 127.0.0.1` in the `probe` and a running application. `DUAL_STACK` does not undo the effect of `ISTIO_DUAL_STACK`.
* With `DUAL_STACK` and the standard `probe`: `dial tcp: address 127.0.0.6:0: no suitable address found`. The agent connects from an IPv4 address to the IPv6 address of the VM.

So a `probe` on our VM works only with these three things together:

* **`DUAL_STACK='true'` in `cluster.env` and no `ISTIO_DUAL_STACK` line.** `istioctl x workload entry configure` writes that line itself (it copies it from the mesh configuration, where the `istiod` Helm chart puts it when `pilot.env.ISTIO_DUAL_STACK=true`), so you have to delete it and restart the sidecar:

  ```
  ssh $VM "sed -i '/^ISTIO_DUAL_STACK=/d' /var/lib/istio/envoy/cluster.env"
  ssh $VM "grep -q '^DUAL_STACK=' /var/lib/istio/envoy/cluster.env || echo \"DUAL_STACK='true'\" >> /var/lib/istio/envoy/cluster.env"
  ssh $VM "systemctl restart --no-block istio"
  ```

* **`httpGet.host: 127.0.0.1` in the `probe`** of the `WorkloadGroup` (create the files for the VM after you changed the `WorkloadGroup`):

  ```
    probe:
      periodSeconds: 3
      failureThreshold: 2
      httpGet:
        host: 127.0.0.1
        port: 8000
        path: /
  ```

* **An application that also listens on IPv4.**

We tested the other probe types only on a VM with IPv6 only (see below), not on the dual stack VM. Without a `probe` there is no health check at all: a VM with a stopped application stays `HEALTHY` and calls fail with `503`.

## What the cluster provides: `istiod`

The listeners `15001` and `15006` of Envoy (inbound and outbound redirect) are not decided on the VM. `istiod` builds them. They exist on `[::]` only if `ISTIO_DUAL_STACK=true` is set in the environment of `istiod` (Helm value `pilot.env.ISTIO_DUAL_STACK`, default `false`). In a real environment this is part of the cluster provisioning (our lab script sets it in step 2 of the exercise).

| `istiod` | `cluster.env` | Envoy listens on (15001, 15006) | Call |
|---|---|---|---|
| on | a dual stack variable | `0.0.0.0` and `[::]` | `200` |
| on | nothing | `0.0.0.0` and `[::]` | `503` |
| off | a dual stack variable | `0.0.0.0` only | `503` |
| off | nothing | `0.0.0.0` only | `503` |

The variables on the VM do not change these two listeners, and the line `ISTIO_DUAL_STACK` in the file `mesh.yaml` of the VM made no difference either.

## What if the VM has IPv6 only?

On Hetzner every server gets the private IPv4 address by DHCP. We switched it off on the VM `b-vm2` for good: `dhcp4: false` in `/etc/netplan/50-cloud-init.yaml` and `network: {config: disabled}` in `/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg` (so cloud-init does not write it back), then a reboot. Afterwards the VM had one global address, the IPv6 address, and no IPv4 route; SSH and downloads worked over IPv6. The mode of this VM is IPv6, and the whole exercise ran with the same files and the same script (`VM=b-vm2`). Results:

| What we tested | Result |
|---|---|
| Exercise with both lines in `cluster.env` (`ISTIO_DUAL_STACK` from `istioctl`, `DUAL_STACK` from the script) | works, `200`; the variables do no harm |
| No dual stack variable in `cluster.env` | works: 19 IPv6 rules (plus the 23 IPv4 rules, those are always set), Envoy on `[::]`, `200` |
| Also without `ISTIO_SVC_IP` | works, the `WorkloadEntry` gets the IPv6 address (it is the only address) |
| `ISTIO_DUAL_STACK` in `istiod` off | works, `200` |
| `probe` `httpGet` without `host` | works: `Healthy=True`; app stopped: `Healthy=False`, `503`; app started: `Healthy=True`, `200` |
| `probe` `httpGet` with `host: "::1"` | works like the one above (log: `dial tcp [::6]:0->[::1]:8000`) |
| `probe` `exec` (`curl` against `[::1]:8000`) | works like the one above |
| `probe` `tcpSocket` on port 8000 | **does not notice a stopped application**: `Healthy=True` although the calls fail with `503` |
| Ports `15090`, `15021`, `15020` from a pod over IPv6 | all `200` (they listen on `[::]`) |
| Reboot of the VM | no IPv4 address after the reboot; the sidecar does not start by itself (`istio` is `disabled`), the `WorkloadEntry` is gone and calls fail with `503`; after `systemctl start istio` and the application it works again |

So all the dual stack topics on this page come from the additional IPv4 address. On a VM with IPv6 only, Istio uses `::1` and `::6` for its checks, and you need no dual stack setting and no workaround for the `probe`.

The `tcpSocket` probe has no source address of its own in the code (`NewTCPProber` has no `ipv6` parameter). Our explanation is that the connection to the address of the VM itself is redirected to Envoy by the iptables rules, and Envoy accepts it even when the application is down. We did not prove that. Use `httpGet` or `exec` for the VM.

## What to take with you

* A VM with an IPv6 and an IPv4 address is in the mode Dual. It needs `ISTIO_DUAL_STACK='true'` or `DUAL_STACK='true'` in `cluster.env`, and `ISTIO_SVC_IP` for the right address.
* `DUAL_STACK` = the IPv6 rules and nothing else. `ISTIO_DUAL_STACK` = the IPv6 rules **and** the ports of the sidecar on IPv6.
* The `probe` is run by the `pilot-agent`. On a dual stack VM it needs `DUAL_STACK`, `host: 127.0.0.1` and an application that listens on IPv4.
* On the VM, `ISTIO_DUAL_STACK` is only needed if something outside reaches the ports `15090` or `15021` of the sidecar over IPv6. For the metrics, port `15020` of the agent works with either name.
* `ISTIO_DUAL_STACK` is also a setting of `istiod` (the IPv6 listeners). That part belongs to the cluster provisioning.
* A VM with IPv6 only needs none of this. Do not use the `tcpSocket` probe on a VM: it does not notice a stopped application.
* If a VM fails with `503`, look at three things: the number of IPv6 rules (expected 19), the listeners (`[::]:15001` and `[::]:15006` must exist) and the `ADDRESS` of the `WorkloadEntry`.
