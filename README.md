# Istio Hybrid: Multi-Cluster and VMs in a Service Mesh

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
  
  1. Explore the lab
     * [Look around the lab: nodes, pods, sidecar, `istioctl proxy-status`](explore-the-lab/01-look-around.md)

  1. Ingress gateway on IPv6
     * [Expose Bookinfo through the ingress gateway over IPv6](ingress-gateway/01-expose-bookinfo-over-ipv6.md)
        
  1. Two clusters, one mesh
     * [Check the link between two clusters: `istioctl remote-clusters`](multi-cluster/01-check-the-link-between-clusters.md)
     * [Answer requests with pods from the other cluster](multi-cluster/02-answer-requests-from-the-other-cluster.md)
      
  1. Virtual machines in the mesh
     * [WorkloadGroup, WorkloadEntry and EndpointSlice: who is who](virtual-machines/00-workloadgroup-workloadentry-endpointslice.md)
     * [How a VM joins the mesh](virtual-machines/00-how-a-vm-joins-the-mesh.md)
     * [Add a virtual machine to the mesh (IPv6 only, VM without IPv4)](virtual-machines/01-add-a-vm-to-the-mesh.md)
     * [Ports of istiod and of the sidecar on the VM](virtual-machines/00-ports-of-sidecar-and-istiod.md)
     * (Optional) [Add a virtual machine to the mesh with IPv4 and IPv6 (dual stack)](virtual-machines/02-add-a-vm-to-the-mesh-dual-stack-optional.md)
     * (Optional) [Dual stack on the VM: what to set (`DUAL_STACK` and `ISTIO_DUAL_STACK`)](virtual-machines/00-dual-stack-switches.md)
     * (Optional) [Reference: Dual stack on the VM: details and measurements](virtual-machines/00-dual-stack-switches-details.md)

  1. Debugging Istio
     * [Logs and log levels](debugging/01-logs-and-log-levels.md)
     * [ControlZ: the debug page of istiod](debugging/02-controlz.md)
