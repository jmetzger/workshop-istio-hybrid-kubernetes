# Istio Hybrid: Multi-Cluster and VMs in a Service Mesh

Workshop on Istio in sidecar mode with the classic Istio APIs (VirtualService, DestinationRule, ServiceEntry, Gateway):
several Kubernetes clusters and virtual machines in one shared mesh, on an IPv6-only network.

All material in this repository is in English.

## Agenda

Day 1 – foundations on a ready-made lab

1. Explore the lab
   * [Look around the lab: nodes, pods, sidecar, `istioctl proxy-status`](explore-the-lab/01-look-around.md)
2. Ingress gateway on IPv6
   * [Expose Bookinfo through the ingress gateway over IPv6](ingress-gateway/01-expose-bookinfo-over-ipv6.md)

Day 2 – multi-cluster and virtual machines

1. Two clusters, one mesh
   * [Check the link between two clusters: `istioctl remote-clusters`](multi-cluster/01-check-the-link-between-clusters.md)
   * [Answer requests with pods from the other cluster](multi-cluster/02-answer-requests-from-the-other-cluster.md)
2. Virtual machines in the mesh
   * [Add a virtual machine to the mesh (IPv6 only)](virtual-machines/01-add-a-vm-to-the-mesh.md)

(more modules follow, every exercise is tested on the real lab)

## Related repositories

- General Istio training (sidecar and ambient mode, Gateway API, German): https://github.com/jmetzger/training-istio-kubernetes
