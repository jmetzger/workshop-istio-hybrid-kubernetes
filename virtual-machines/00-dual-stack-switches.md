# DUAL_STACK and ISTIO_DUAL_STACK: what they do and where you set them

![Two dual stack switches: DUAL_STACK in cluster.env controls the iptables rules, ISTIO_DUAL_STACK in istiod and the mesh configuration controls the Envoy listeners](../images/dual-stack-switches.svg)

## Background

Our Kubernetes clusters run IPv6 single stack. You would expect that a VM with an IPv6 address needs nothing special. It does: the Istio sidecar for VMs has no IPv6-only mode. It handles IPv6 only when dual stack is switched on, even if the VM has no IPv4 address that matters.

Two things on the VM must be dual stack aware, and each has its own switch:

| What | Who does it | Switch |
|---|---|---|
| The **iptables rules** that redirect the traffic of the VM to Envoy | `pilot-agent istio-iptables`, started by `istio-start.sh` | `DUAL_STACK` or `ISTIO_DUAL_STACK` in `cluster.env` (on the VM) |
| The **listeners of Envoy** on port 15001 and 15006 (IPv4 and IPv6) | `istiod` builds them and sends them to Envoy | `ISTIO_DUAL_STACK` in `istiod` **and** in the mesh configuration (`proxyMetadata`) |

The names look alike, but they are not the same setting. Where you set which name is the point of this page.

## Where do you set what?

| Name | Where | How you set it |
|---|---|---|
| `ISTIO_DUAL_STACK` | environment of `istiod` | Helm value `pilot.env.ISTIO_DUAL_STACK=true` |
| `ISTIO_DUAL_STACK` | mesh configuration | Helm value `meshConfig.defaultConfig.proxyMetadata.ISTIO_DUAL_STACK=true` |
| `ISTIO_DUAL_STACK` | file `cluster.env` on the VM | written by `istioctl x workload entry configure` (see below) |
| `DUAL_STACK` | file `cluster.env` on the VM | one line you add: `DUAL_STACK='true'` |

For the first two rows we use one Helm command (step 2 of the exercise):

```
helm --kube-context $CTX_A upgrade istiod istio/istiod -n istio-system --version $ISTIO_VERSION --reuse-values --wait \
  --set-string pilot.env.ISTIO_DUAL_STACK=true \
  --set-string meshConfig.defaultConfig.proxyMetadata.ISTIO_DUAL_STACK=true
```

The default of `ISTIO_DUAL_STACK` in `istiod` is `false` (Istio reference: "If true, Istio will enable the Dual Stack feature"). If you set nothing, you get no dual stack.

## Which parameter is it in `cluster.env`?

The file `/var/lib/istio/envoy/cluster.env` is read by `istio-start.sh`. The script switches on `set -a` before it reads the file, so every variable in the file becomes an environment variable. Then the script runs `pilot-agent istio-iptables` **without arguments**. The command takes its settings from the environment. `DUAL_STACK` is the environment form of its flag `--dual-stack` ("Enable ipv4/ipv6 redirects for dual-stack"). `ISTIO_DUAL_STACK` has the same effect for the iptables.

After the exercise, look at your file:

```
ssh $VM "grep -E 'DUAL_STACK|ISTIO_SVC_IP' /var/lib/istio/envoy/cluster.env"
```

```
ISTIO_DUAL_STACK='true'
ISTIO_SVC_IP='2a01:4f8:c013:541::1'
DUAL_STACK='true'
```

Two of the three lines come from you or the script: `ISTIO_SVC_IP` and `DUAL_STACK`. `ISTIO_DUAL_STACK='true'` was written by `istioctl`: `istiod` and the mesh configuration already had the switch when you created the files. We did not check which of the two settings `istioctl` copies. Also look at the mesh configuration file the VM got:

```
ssh $VM "grep -n DUAL /etc/istio/config/mesh"
```

```
7:    ISTIO_DUAL_STACK: "true"
```

## Try it: what does each name do for the iptables?

`pilot-agent istio-iptables --dry-run` prints what it would do and changes nothing. We count the lines that mention `ip6tables`:

```
ssh $VM "pilot-agent istio-iptables --dry-run 2>&1 | grep -c ip6tables"
ssh $VM "DUAL_STACK=true pilot-agent istio-iptables --dry-run 2>&1 | grep -c ip6tables"
ssh $VM "ISTIO_DUAL_STACK=true pilot-agent istio-iptables --dry-run 2>&1 | grep -c ip6tables"
ssh $VM "DUAL_STACK=false pilot-agent istio-iptables --dry-run 2>&1 | grep -c ip6tables"
```

```
0
1
1
0
```

Nothing set: no IPv6 rules. `DUAL_STACK=true` or `ISTIO_DUAL_STACK=true`: IPv6 rules.

## What happens in the real sidecar

We started the sidecar with each variant and removed all old rules before each start (`pilot-agent istio-iptables --cleanup-only` with `DUAL_STACK=true`, which cleans IPv4 and IPv6). The VM had the settings of `istiod` and the mesh configuration, `ISTIO_DUAL_STACK`, in place. Calls came from a pod in cluster a.

| `cluster.env` contains | IPv4 / IPv6 rules | Call from the pod |
|---|---|---|
| neither variable | 23 / 3 (the 3 are leftover lines, they were there before the start, too) | `HTTP 503` (3 of 3) |
| only `ISTIO_DUAL_STACK='true'` | 23 / 19 | `HTTP 200` (3 of 3) |
| only `DUAL_STACK='true'` | 23 / 19 | `HTTP 200` (3 of 3) |

In all three cases Envoy listened on `0.0.0.0` and `[::]` (ports 15001 and 15006), because `istiod` and the mesh configuration had the switch. With neither variable in `cluster.env` the IPv6 rules are missing, and the call fails with 503: the switch for the listeners alone is not enough.

We did not measure the other direction (rules with `DUAL_STACK`, but without `ISTIO_DUAL_STACK` in `istiod` and the mesh configuration) in this lab. In an earlier lab test with exactly this setting the call failed with `503`, `Connection refused`, because Envoy listened on IPv4 only. We also did not test the two Helm values separately.

## So what do you set?

* **In `istiod` and the mesh configuration:** `ISTIO_DUAL_STACK=true` in both places (the Helm command above).
* **On the VM:** one of the two names in `cluster.env`. If you create the files with `istioctl` **after** the Helm command, `ISTIO_DUAL_STACK='true'` is already in the file and is enough.
* **Our exercise script** adds `DUAL_STACK='true'` anyway. That line is redundant in our order of steps, but it does no harm, and it protects you when somebody creates the files before `istiod` is configured.

## What to take with you

* There is no default: nothing set means no dual stack, and a VM in an IPv6 cluster fails with 503.
* `DUAL_STACK` is a variable of the VM (iptables). `ISTIO_DUAL_STACK` is the Istio switch that exists in `istiod`, in the mesh configuration and, written by `istioctl`, in `cluster.env`.
* Look into `cluster.env` and into the number of IPv6 rules (`ip6tables-save -t nat | grep -c ISTIO`) before you search elsewhere.
