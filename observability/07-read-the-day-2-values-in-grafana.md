# Read the day-2 values in Grafana

## What we do

You look at the values that an operations team watches in a mesh: is `istiod` healthy, does the configuration arrive in the proxies, how long do the certificates live, are there errors in the traffic. You find each value in a ready-made Grafana dashboard and ask Prometheus for the same number. Measured in our lab (Istio 1.29.9, cert-manager with istio-csr).

Prometheus (both clusters) and Grafana (cluster a) are part of the lab, you do not install anything. The address and the login are in `~/monitoring-access.md`. You need some traffic in the mesh; if you did [Prometheus, Grafana, Kiali](01-prometheus-grafana-kiali.md) step 2, you have it.

## Step 1: Open the dashboards

In Grafana choose **Dashboards**. You find the folder **istio** with the dashboards that come with Istio, and the folder **lab** with the certificate dashboard.

| Dashboard | Look for | What it tells you |
|---|---|---|
| Istio Control Plane Dashboard | **Connections**, **Push Errors**, **Push Time**, **Memory Usage** | is `istiod` healthy, do proxies get their configuration |
| Istio Mesh Dashboard | **Success Rate**, **5xxs**, **Traffic Volume** | is the traffic in the whole mesh fine |
| Istio Service Dashboard | **Client Request Duration**, **Server Success Rate** | one service: how fast, how many errors |
| Lab: certificates and when they expire (folder **lab**) | the table and the saw | which certificate ends when |

Open each one and write down one number from it. Set the time range to **Last 1 hour**.

## Step 2: Ask Prometheus for the same numbers

In Grafana choose **Explore** and the data source `prometheus-a` (cluster a). Run each query and compare it with the dashboard.

1. How many proxies are connected to `istiod`?

```
sum(pilot_xds)
```

We got `9` in each cluster. The value should match the number of pods with a sidecar plus the VMs. A value that drops and stays low means proxies lost the connection.

2. How long does it take until a configuration change arrives in the proxies (99 % of the cases)?

```
histogram_quantile(0.99, sum(rate(pilot_proxy_convergence_time_bucket[1h])) by (le))
```

We got `0.099` (seconds). Use a long window. With `[5m]` and no change in the mesh the result is `NaN`, because nothing was pushed.

3. How much memory does `istiod` use?

```
sum(container_memory_working_set_bytes{container="discovery"}) / 1048576
```

We got `62` (MiB) in cluster a and `77` in cluster b.

4. How much memory does each sidecar use?

```
sum by (pod) (container_memory_working_set_bytes{container="istio-proxy"}) / 1048576
```

We got between `38` and `45` MiB per pod.

5. How long is the shortest workload certificate still valid?

```
min(istio_agent_cert_expiry_seconds)
```

We got `363` (seconds). In our lab workload certificates live 10 minutes and are renewed after half of it, so the value jumps between about 600 and 300.

6. How long is the shortest certificate of the whole mesh still valid (CAs, `istiod`)?

```
min(x509_cert_not_after) - time()
```

We got `2131` (seconds). Compare with the table in the dashboard **Lab: certificates and when they expire**.

7. Is any target of Prometheus down?

```
sum(up == 0) or vector(0)
```

We got `0`.

8. How many requests are answered with an error (5xx)?

```
sum(increase(istio_requests_total{response_code!~"5.."}[1h])) / sum(increase(istio_requests_total[1h]))
```

We got `1`, which means no 5xx at all in the last hour. The share of requests that were not an error should be close to 1.

## Step 3: What to alert on

For each value decide: would you wake somebody up, or is it only a picture on a dashboard? Our suggestion, to talk about in the group. The limits are starting points. Measure your own normal values for a week before you set them.

| Value | Alarm when |
|---|---|
| `pilot_xds` | stays away from the number of pods and VMs for more than 5 minutes |
| convergence time p99 | above 5 seconds |
| rejected configuration | any increase (the counters `pilot_total_xds_rejects` and `pilot_xds_push_context_errors` do not exist in our lab as long as nothing was rejected) |
| `istiod` memory | above 80 % of its limit |
| certificate of a CA | less than 90 days left (warning), less than 30 days (critical) |
| 5xx share | above 1 % for 5 minutes |
| a target of Prometheus | `up == 0` for more than 5 minutes |

**Note:** the metric `citadel_server_csr_sign_error_count` only exists when `istiod` signs the certificates itself. In our lab `istio-csr` signs them, so look into the log of `istio-csr` for signing errors.

## What you cannot see in a dashboard

The state of the link between the clusters is not a metric. You check it with the command from [Check the link between the clusters](../multi-cluster/01-check-the-link-between-clusters.md) (`istioctl remote-clusters`, it must show `synced` in both directions). In production you run this command on a timer and alert on the result.
