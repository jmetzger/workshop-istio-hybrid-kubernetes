# Dual stack on the VM: what to set

![On the VM: DUAL_STACK sets the iptables rules, ISTIO_DUAL_STACK sets the rules and moves the ports of the sidecar to IPv6](../images/dual-stack-switches.svg)

> **Attention:** When you use IPv6 only on the VMs (Istio hybrid), be sure that the IPv4 address on the VM is disabled. That is the best and easiest way. Otherwise you need to fiddle around (dual stack switches, `ISTIO_SVC_IP`, health `probe` workarounds).

## The rule

| The VM has | You set |
|---|---|
| **IPv6 only** | nothing |
| **IPv4 and IPv6** (our lab VM: IPv6 plus a private, not routed `100.65.x.x`) | one dual stack line in `/var/lib/istio/envoy/cluster.env`, and `ISTIO_SVC_IP` |

Why: A VM with IPv4 and IPv6 is a dual stack workload for Istio. Without a dual stack line, Istio sets the iptables rules only for IPv4. Traffic that arrives over IPv6 then bypasses the sidecar and reaches the application directly. The calling pod speaks mTLS, the application does not, and the call fails with `503`.

## Two names, two jobs

Both names are lines in `cluster.env`. Both switch on the IPv6 iptables rules. They differ in what else they change:

| | `DUAL_STACK='true'` | `ISTIO_DUAL_STACK='true'` |
|---|---|---|
| IPv6 rules (traffic goes through Envoy) | yes | yes |
| Envoy admin port `15000` | stays on `127.0.0.1` | moves to `[::1]` |
| Envoy metrics `15090` and readiness `15021` over IPv6 | **not reachable** | reachable |
| Health `probe` in the WorkloadGroup | **works** (with `host: 127.0.0.1`) | **does not work** |
| Who writes it | you (our script adds it) | `istioctl x workload entry configure`, if `istiod` has `ISTIO_DUAL_STACK=true` when you create the files (the Helm chart then puts it into the mesh configuration, `istioctl` copies it) |

## What do you want?

A word first: **scraping** means that Prometheus pulls metrics from a URL, for example `http://<VM>:15090/stats/prometheus`. The sidecar has two ports of its own for this: `15090` (the metrics of Envoy) and `15021` (the readiness of Envoy). In our lab only IPv6 reaches the VM, so these two ports must listen on IPv6 to be reachable from the cluster.

You have two choices:

* **You do not need a health `probe`:** keep what `istioctl` wrote, `ISTIO_DUAL_STACK`. Prometheus can scrape `15090`, and `15021` answers over IPv6. Nothing to do.
* **You need a health `probe` in the WorkloadGroup:** use `DUAL_STACK` and **delete the line `ISTIO_DUAL_STACK`** from `cluster.env`, then restart the sidecar. Add `host: 127.0.0.1` to the `probe`. The price: `15090` and `15021` listen on IPv4 only, so Prometheus cannot scrape the Envoy metrics and nothing can ask the Envoy readiness over IPv6. The metrics of the agent on port `15020` work with both names.

You cannot have both. The reason is that the health check of the agent talks IPv4 on a dual stack VM (`127.0.0.1` for Envoy, `127.0.0.6` as source address), while `ISTIO_DUAL_STACK` moves Envoy to IPv6. Details and measurements: [reference page](00-dual-stack-switches-details.md).

## The cluster side

`istiod` needs `ISTIO_DUAL_STACK=true` in its environment (Helm value `pilot.env.ISTIO_DUAL_STACK`). It decides whether Envoy listens on `[::]` for the traffic redirect (ports `15001`, `15006`). In a real environment this is part of the cluster provisioning. Without it, nothing on the VM helps.

## Look at your VM

```
ssh $VM "ip -o addr show scope global | awk '{print \$3, \$4}'"
ssh $VM "grep -E 'DUAL_STACK|ISTIO_SVC_IP' /var/lib/istio/envoy/cluster.env"
ssh $VM "echo \"IPv4 rules: \$(iptables-save -t nat | grep -c ISTIO)  IPv6 rules: \$(ip6tables-save -t nat | grep -c ISTIO)\""
ssh $VM "ss -ltnp | grep -E ':150[0-9][0-9] ' | awk '{print \$4}' | sort -u"
```

Healthy dual stack: 23 IPv4 rules and 19 IPv6 rules, and the listeners `[::]:15001` and `[::]:15006`. IPv4 rules are always set, the tool never sets IPv6 rules alone. If a call fails with `503`, look here first, then at the `ADDRESS` of the `WorkloadEntry`.

## If a call fails with 503

The text of the error comes from Envoy, the sidecar of the **calling pod** (response header `server: envoy`), not from the VM. The VM never answered.

| What the error says, or what you see | Cause | Fix |
|---|---|---|
| `... TLS_error ... WRONG_VERSION_NUMBER` | No IPv6 rules on the VM (0 instead of 19): the IPv6 traffic bypasses the sidecar, the application answers in plain text to a TLS client | dual stack line in `cluster.env`, restart the sidecar |
| `... delayed connect error: Connection refused` | The IPv6 rules exist, but Envoy has no listener on `[::]` | `ISTIO_DUAL_STACK=true` in `istiod` (cluster side) |
| `503`, and the `ADDRESS` of the `WorkloadEntry` is the IPv4 address (`100.65.x.x`) | `ISTIO_SVC_IP` is missing, the sidecar registered the wrong address | set `ISTIO_SVC_IP` to the IPv6 address, restart the sidecar |
| `503`, and the `WorkloadEntry` shows `Healthy=False` | The health `probe` fails (the application is down, or the `probe` does not fit the VM, see above) | `/var/log/istio/istio.log` on the VM shows why |

We measured the first two texts. For the other two rows we saw the status `503`, but we did not save the text.

