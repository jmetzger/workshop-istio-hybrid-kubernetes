f# Istio Hybrid: Multi-Cluster and VMs in a Service Mesh

Workshop on Istio in sidecar mode with the classic Istio APIs (VirtualService, DestinationRule, ServiceEntry, Gateway):
several Kubernetes clusters and virtual machines in one shared mesh, on an IPv6-only network.

All material in this repository is in English.

## Agenda

  1. Fundamentals: service mesh and Istio   
     * [What is a service mesh, and what is Istio? Sidecar and ambient](fundamentals/01-what-is-a-service-mesh.md)
     * [Why a service mesh?](fundamentals/02-why-a-service-mesh.md)
     * [Challenges and benefits](fundamentals/03-challenges-and-benefits.md)
     * [Istio architecture and components](fundamentals/04-istio-architecture-and-components.md)
     * [Istio ingress gateway vs. Kubernetes Gateway API](fundamentals/05-ingress-gateway-vs-gateway-api.md)
     * [Ports of istiod and of the sidecar (sidecar mode)](fundamentals/06-ports-of-istiod-and-the-sidecar.md)
     * [How the sidecar gets into the pod (sidecar injection)](fundamentals/07-sidecar-injection.md)
     * [Who signs the certificates: cert-manager with istio-csr](fundamentals/08-certificates-with-cert-manager-and-istio-csr.md)

  1. Several Cluster and virtual machines in one mesh
     * [The big picture: several clusters and virtual machines in one mesh](fundamentals/00-the-big-picture-multi-cluster-and-vms.md)
  
  1. Explore the lab
     * [Our lab: servers, VMs, bastion and monitoring (everything is IPv6)](explore-the-lab/00-our-lab.md)
     * [Look around the lab: nodes, pods, sidecar, `istioctl proxy-status`](explore-the-lab/01-look-around.md)
     * [How Istio is installed in the lab (Helm releases, settings, APIs)](explore-the-lab/02-how-istio-is-installed.md)

  1. Ingress gateway on IPv6
     * [Expose Bookinfo through the ingress gateway over IPv6](ingress-gateway/01-expose-bookinfo-over-ipv6.md)

  1. Steering traffic (theory and trainer demo)
     * [The four objects, and why they matter for debugging](traffic-management/00-the-objects-and-why-they-matter-for-debugging.md)
     * [Trainer demo: traffic shifting, fault injection, and a broken rule](traffic-management/01-trainer-demo-shifting-fault-injection-broken-rule.md)

  1. Security
     * [mTLS between workloads: PERMISSIVE and STRICT](security/01-mtls-permissive-and-strict.md)
     * [Zero trust with Bookinfo: deny all, then allow each path](security/02-zero-trust-with-authorization-policies.md)

  1. Outages
     * [Outage: istiod is gone](outage/01-istiod-is-gone.md)
        
  1. Two clusters, one mesh
     * [Connect cluster a and cluster b to one mesh (multi-primary)](multi-cluster/00-connect-the-two-clusters.md)
     * [Check the link between two clusters: `istioctl remote-clusters`](multi-cluster/01-check-the-link-between-clusters.md)
     * [Answer requests with pods from the other cluster](multi-cluster/02-answer-requests-from-the-other-cluster.md)
      
  1. Virtual machines in the mesh
     * [WorkloadGroup, WorkloadEntry and EndpointSlice: who is who](virtual-machines/00-workloadgroup-workloadentry-endpointslice.md)
     * [How a VM joins the mesh](virtual-machines/00-how-a-vm-joins-the-mesh.md)
     * [Add a virtual machine to the mesh (IPv6 only, VM without IPv4)](virtual-machines/01-add-a-vm-to-the-mesh.md)
     * [Ports of istiod and of the sidecar on the VM](virtual-machines/00-ports-of-sidecar-and-istiod.md)
     * [Health check: is the application on the VM alive?](virtual-machines/04-health-check-of-the-vm.md)
     * [Outage: what happens to the VM, and how it comes back](virtual-machines/03-outage-what-happens-to-the-vm.md)
     * (Optional) [Add a virtual machine to the mesh with IPv4 and IPv6 (dual stack)](virtual-machines/02-add-a-vm-to-the-mesh-dual-stack-optional.md)
     * (Optional) [Dual stack on the VM: what to set (`DUAL_STACK` and `ISTIO_DUAL_STACK`)](virtual-machines/00-dual-stack-switches.md)
     * (Optional) [Reference: Dual stack on the VM: details and measurements](virtual-machines/00-dual-stack-switches-details.md)

  1. Debugging Istio
     * [Logs and log levels](debugging/01-logs-and-log-levels.md)
     * [ControlZ: the debug page of istiod](debugging/02-controlz.md)
     * [See the traffic: access logs instead of tcpdump](debugging/03-access-logs-instead-of-tcpdump.md)
     * [Test a connection between two pods, and read a hidden REST call](debugging/04-test-a-connection-and-read-a-rest-call.md)

  1. Monitoring
     * [What Istio costs: CPU and memory of the sidecars and of istiod](observability/00-what-istio-costs.md)
     * [Prometheus, Grafana, Kiali, and what Istio costs](observability/01-prometheus-grafana-kiali.md)
     * [Make the expiry of certificates visible](observability/02-certificate-expiry.md)
     * [Build the certificate dashboard by hand in Grafana](observability/06-build-the-certificate-dashboard-by-hand.md)
     * [Memory of the sidecars: many services, and the Sidecar object](observability/03-sidecar-memory-and-the-sidecar-object.md)
     * [Kiali in practice: read the graph, find a broken rule](observability/04-kiali-in-practice.md)
     * [Latency: a pod without a sidecar and a pod with one](observability/05-latency-with-and-without-a-sidecar.md)
     * [Read the day-2 values in Grafana](observability/07-read-the-day-2-values-in-grafana.md)

  1. Upgrade
     * [Upgrade Istio: control plane first, then the proxies](upgrade/01-upgrade-istio-in-place.md)
     * [Upgrade Istio with revisions: two control planes side by side](upgrade/02-upgrade-istio-with-revisions.md)
     * [How the sidecar on a VM is upgraded](upgrade/00-how-the-vm-sidecar-is-upgraded.md)
     * [Upgrade a VM in place](upgrade/03-upgrade-the-vm-in-place.md)
     * [Upgrade a VM with revisions](upgrade/04-upgrade-the-vm-with-revisions.md)
     * [Upgrade two VMs, one after the other](upgrade/05-upgrade-two-vms-one-after-the-other.md)
