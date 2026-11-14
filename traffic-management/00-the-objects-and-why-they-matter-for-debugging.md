# Steering traffic: the four objects, and why they matter for debugging

This page is theory. The trainer shows two examples on the next page, you do not have to type anything.

## The four objects (Istio API)

| Object | Question it answers | Where it acts |
|---|---|---|
| `Gateway` | Which port, protocol and host name does the ingress gateway open? | in the Envoy of the ingress gateway (a listener) |
| `VirtualService` | A request for this host arrives: where does it go? (match, weight, timeout, retry, fault) | in the Envoy of the **caller** (a route) |
| `DestinationRule` | The request goes to this service: how do we talk to it? (subsets, load balancing, TLS, connection limits) | in the Envoy of the **caller** (a cluster) |
| `ServiceEntry` | Which hosts outside the mesh are known to the mesh? | adds a service to the registry of `istiod` |

Two things to keep in mind:

* **None of them is needed for plain traffic.** Without any of these objects, a call to a Kubernetes `Service` works and is spread over all its pods. The objects only change the default.
* **They act on the side of the caller.** A `VirtualService` for `reviews` changes the Envoy of `productpage`, not the Envoy of `reviews`.

## How they fit together

A `VirtualService` names a **host** and, optionally, a **subset**. The subset is defined in a `DestinationRule` for the same host, by a label of the pods:

```
VirtualService reviews            DestinationRule reviews           Pods
  route:                            subsets:
    host: reviews                     name: v1  -> labels version=v1    reviews-v1
    subset: v1          ------->      name: v3  -> labels version=v3    reviews-v3
```

The two objects are bound only by names: the host and the name of the subset. Nothing checks at `kubectl apply` that the other side exists.

## From the object to Envoy

`istiod` reads the objects, translates them and sends the result to every proxy that needs it (xDS). An application never reads these objects, and Envoy never reads them either: Envoy only knows listeners, routes, clusters and endpoints.

| You write | Envoy gets | You see it with |
|---|---|---|
| `Gateway` | a listener | `istioctl proxy-config listeners` |
| `VirtualService` | a route | `istioctl proxy-config routes` |
| `DestinationRule` | a cluster (per subset) and its settings | `istioctl proxy-config clusters` |
| `Service`, pods, `WorkloadEntry`, `ServiceEntry` | endpoints | `istioctl proxy-config endpoints` |

## Why this matters for debugging

* **What you applied is not what runs.** What counts is what Envoy has. If a rule does not work, compare the object with the configuration of the proxy of the **caller**.
* **A mistake in these objects is a typical cause of `503`.** Example: the `VirtualService` sends to the subset `v1`, but no `DestinationRule` defines it. Envoy has a route to a cluster that does not exist. The application is healthy, the pods are running, and every call fails.
* **Nothing fails at `kubectl apply`.** The objects are valid on their own. `istioctl analyze` finds the broken reference.
* **Several clusters, one mesh:** a `VirtualService` that exists only in cluster a does not change the callers in cluster b (measured in the demo). Rules must be applied in every cluster.

The order to look at things when a call fails:

1. `istioctl analyze`: are the objects consistent?
2. `istioctl proxy-status`: is the proxy of the caller connected to `istiod`?
3. `istioctl proxy-config routes|clusters|endpoints` on the caller: what does Envoy really have?

Next: [Trainer demo: traffic shifting, fault injection, and a broken rule](01-trainer-demo-shifting-fault-injection-broken-rule.md)
