# Istio Hybrid: Multi-Cluster and VMs in a Service Mesh

Workshop on Istio in sidecar mode with the classic Istio APIs (VirtualService, DestinationRule, ServiceEntry, Gateway):
several Kubernetes clusters and virtual machines in one shared mesh, on an IPv6-only network.

All material in this repository is in English.

## Agenda

Day 1 – foundations on a ready-made lab

1. Explore the lab
   * [Look around the lab: nodes, pods, sidecar, `istioctl proxy-status`](explore-the-lab/01-look-around.md)

Day 2 – multi-cluster and virtual machines

1. Two clusters, one mesh
   * [Check the link between two clusters: `istioctl remote-clusters`](multi-cluster/01-check-the-link-between-clusters.md)

(more modules follow, every exercise is tested on the real lab)

## Related repositories

- General Istio training (sidecar and ambient mode, Gateway API, German): https://github.com/jmetzger/training-istio-kubernetes
