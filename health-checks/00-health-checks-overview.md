# Health checks in the mesh: what you can check, and with what

"Health check" is not one feature of Istio. It is four different questions, and each has its own tool. Ask first which question you mean.

| # | Question | Tool | Where in this workshop |
|---|---|---|---|
| 1 | Are the two clusters connected, in both directions? | `istioctl remote-clusters` (both lines `synced`) | [Check the link between two clusters](../multi-cluster/01-check-the-link-between-clusters.md) |
| 2 | Is every proxy, and every VM, connected to `istiod` and up to date? | `istioctl proxy-status` | [Add a virtual machine to the mesh](../virtual-machines/01-add-a-vm-to-the-mesh.md) |
| 3 | Does the **application** answer? | Probes: Kubernetes probes on a pod, the `probe` of the `WorkloadGroup` on a VM | [Probes on pods and on VMs](01-probes-on-pods-and-vms.md), [Health check of the VM](../virtual-machines/04-health-check-of-the-vm.md) |
| 4 | Does traffic really flow, and are the certificates valid? | A test call, Kiali, Prometheus and Grafana | [Read the day-2 values in Grafana](../observability/07-read-the-day-2-values-in-grafana.md), [Certificate expiry](../observability/02-certificate-expiry.md) |

## Questions 1 and 2: is the mesh itself healthy?

They say something about the **control plane and the sidecars**, not about your application. `remote-clusters` shows whether `istiod` of one cluster can read the other cluster. `proxy-status` shows whether a proxy is connected. A VM with a running sidecar is in `proxy-status` even when its application is dead.

## Question 3: is the application alive?

Only a probe can tell. A probe is a small check that someone runs again and again against the application.

| | Who runs the probe | What happens when it fails |
|---|---|---|
| Pod | the `kubelet` of the node | the pod is not ready and leaves the `EndpointSlice` (readiness), or the container is restarted (liveness) |
| VM | the agent (`pilot-agent`) on the VM, configured in the `WorkloadGroup` | the `WorkloadEntry` gets `Healthy=False` and `istiod` takes the VM out of the distribution |

Two things surprise people:

* **With a sidecar, Istio rewrites the probes of a pod.** The `kubelet` has no certificate, so with mTLS `STRICT` it could not reach the application any more. The probe is sent to the agent in the sidecar (port `15020`), and the agent asks the application.
* **A VM without a `probe` is always healthy.** The mesh knows only that the sidecar is connected. And not every probe type works on a VM: `httpGet` and `exec` find a stopped application, `tcpSocket` does not.

## Question 4: does it really work?

A probe says "the application answers". It does not say that a caller gets the right answer, that the certificate is still valid for the next hour, or that the traffic between the clusters arrives. For that you look at the traffic and the certificates: access logs, Kiali, and the values in Grafana.

## What to take away

* Name the question first: link, proxy, application, or traffic.
* `remote-clusters` and `proxy-status` check the mesh. A probe checks the application.
* On a VM you must configure the probe yourself, and you must choose the type: `httpGet` or `exec`, not `tcpSocket`.
* On a dual stack VM you cannot have the probe and the scraping of Envoy metrics together, see [why](../virtual-machines/00-why-health-check-or-scraping.md).

Next: [Probes on pods and on VMs](01-probes-on-pods-and-vms.md)
