# What Istio costs: CPU and memory of the sidecars and of istiod

This page is theory. You measure it yourself in the two exercises of this chapter: [what Istio costs in the lab](01-prometheus-grafana-kiali.md) (step 4) and [many services and the Sidecar object](03-sidecar-memory-and-the-sidecar-object.md).

## Where the cost comes from

| Part | How often | What it needs |
|---|---|---|
| Sidecar (`istio-proxy`) | once per pod | memory for the configuration it holds, CPU for every request it forwards |
| `istiod` (control plane) | once per cluster (or a few replicas) | memory for all services and configuration objects, CPU when something changes |
| Ingress gateway | once per gateway pod | like a sidecar, but it only holds the routes it serves |

The sidecar is the part that adds up: 500 pods are 500 sidecars.

## What drives it

**Memory of a sidecar: the number of services it knows.** The Istio documentation ([Performance and Scalability](https://istio.io/v1.29/docs/ops/deployment/performance-and-scalability/)):

> The memory consumption of the proxy depends on the total configuration state the proxy holds. A large number of listeners, clusters, and routes can increase memory usage.

And by default a sidecar knows the whole mesh ([Sidecar reference](https://istio.io/v1.29/docs/reference/config/networking/sidecar/)):

> By default, Istio will program all sidecar proxies in the mesh with the necessary configuration required to reach every workload instance in the mesh

So a pod that only calls two services still holds the configuration for all of them.

**CPU of a sidecar: the traffic.** The same page lists the factors: number of client connections, request rate, request and response size, number of proxy worker threads, protocol, CPU cores, and the proxy features in use ("telemetry filters (logging, tracing, and metrics) are known to have a moderate impact").

**`istiod`: the amount of configuration and the rate of change.**

> Istiod's CPU and memory requirements scale with the amount of configurations and possible system states. The CPU consumption scales with the following factors: The rate of deployment changes. The rate of configuration changes. The number of proxies connecting to Istiod.

## Numbers from the Istio project

Measured by the Istio project for **Istio 1.24** (the page for 1.29 still shows these numbers), with 1000 HTTP requests per second, 1 KB payload, 2 worker threads, mTLS on, on bare-metal machines:

| Proxy | CPU | Memory |
|---|---|---|
| one sidecar | about 0.20 vCPU | about 60 MB |
| one waypoint proxy (ambient, layer 7) | about 0.25 vCPU | about 60 MB |
| one ztunnel (ambient, layer 4, one per node) | about 0.06 vCPU | about 12 MB |

The page adds: "Different hardware will give different values."

## No mesh, sidecar, ambient: an independent comparison

The company LiveWyer ran the same load test against three clusters: without a mesh, with Istio in sidecar mode and with Istio in ambient mode ([test report](https://github.com/livewyer-ops/poc-servicemesh2024/blob/main/docs/test-report-istio.md), [blog article](https://livewyer.io/blog/2024/06/06/comparison-of-service-meshes-part-two/)). Bookinfo on AWS (`c5.large`), load tool `oha`, 300000 requests from a pod to the service `productpage`:

| 32 connections | Requests per second | Response time, 50 % | Response time, 99 % |
|---|---|---|---|
| no mesh | 143.8 | 220 ms | 329 ms |
| ambient | 130.7 | 244 ms | 354 ms |
| sidecar | 124.5 | 255 ms | 374 ms |

Over all three load levels of the report (32, 64 and 128 connections) the sidecar cluster served 13 to 25 percent fewer requests per second than the cluster without a mesh, the ambient cluster 9 to 22 percent fewer.

On resources the report concludes: with sidecars the need grows with every pod, with ambient "the resource requirement per node remains relatively constant regardless of the number of pods". For a single pod it found nearly the same CPU, "but almost four times less memory" for ambient.

**Read these numbers with care:**

* Istio **1.22** from May 2024. Ambient was beta at that time.
* The application was the bottleneck (about 150 requests per second), and the result without a mesh moved by about 10 percent between the runs. The percentages are rough.
* CPU and memory are only shown as charts in the report, there is no table to quote.
* `istiod` is left out ("similar for all environments and loads").

The relation is what you can take from it: a mesh costs throughput and some latency, ambient costs less than sidecars. The numbers for your own platform you have to measure there.

## Numbers from our lab

Istio 1.29.9, 7 sidecars, no traffic, small cloud servers (2 vCPU, 4 GB). The sidecar of every pod, in the same state:

| Services in the cluster | Memory per sidecar |
|---|---|
| 14 (lab as it is) | about 34 MiB |
| 114 | about 43 MiB |
| 514 | about 84 MiB |
| 514, with a `Sidecar` object that limits the view to the own namespace, pods restarted | about 29 MiB |

That is about 0.1 MiB per service and sidecar. `istiod` stayed below 100 MiB in all of these states, its CPU went up only while services were created or pods restarted. The CPU of an idle sidecar was 3 to 4 millicores.

## The knobs

| Knob | What it does | Where |
|---|---|---|
| Requests and limits of the sidecar | reserve and cap CPU and memory of `istio-proxy` | Helm `global.proxy.resources`, per pod the annotations `sidecar.istio.io/proxyCPU`, `proxyMemory`, `proxyCPULimit`, `proxyMemoryLimit` |
| `Sidecar` object | the sidecars of a namespace only get the services they are allowed to see, so they hold less configuration | object `Sidecar` (`networking.istio.io`) with `egress.hosts` |
| `discoverySelectors` | `istiod` ignores whole namespaces | mesh configuration |
| Worker threads of the proxy (`concurrency`) | how many threads Envoy runs | proxy configuration; the reference says: "If unset, which is recommended, this will be automatically determined based on CPU requests/limits." |
| Requests of `istiod` | reserve CPU and memory for the control plane | Helm values of the chart `istiod` |

For large meshes the Istio documentation is clear: "At large scale, configuration scoping is highly recommended." The `Sidecar` object is the tool for it.

Next: [Prometheus, Grafana, Kiali, and what Istio costs](01-prometheus-grafana-kiali.md)
