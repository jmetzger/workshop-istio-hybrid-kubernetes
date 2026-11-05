# Add a virtual machine to the mesh (IPv6 only)

![A virtual machine joins the mesh: the sidecar on the VM connects to istiod, istiod creates a WorkloadEntry, a pod calls the VM through the Service](../images/vm-in-the-mesh.svg)

## Background

A virtual machine joins the mesh with the Istio sidecar package (`istio-sidecar.deb`). The sidecar connects to `istiod`, gets a workload certificate and appears in the mesh like a pod. `istiod` creates a `WorkloadEntry` for it automatically (auto-registration). From then on a pod calls the VM through a normal Kubernetes `Service`, with mTLS.

What `WorkloadGroup`, `WorkloadEntry` and `EndpointSlice` are and how they differ: [who is who](00-workloadgroup-workloadentry-endpointslice.md).

The lab VM has no IPv4 address. Kubernetes and Istio run as IPv6 single stack, but the sidecar on a VM still needs the dual stack switches (`ISTIO_DUAL_STACK` in `istiod`, `DUAL_STACK` on the VM). We set them from the start. What the switches do and where you set them: [DUAL_STACK and ISTIO_DUAL_STACK](00-dual-stack-switches.md).

| Part | Name in this exercise |
|---|---|
| VM | `a-vm1` (reach it with `ssh a-vm1`) |
| Namespace, service account, workload group, service | `vm`, `diameter-adapter` |
| Application on the VM | a small Python echo server on port 8000 (`vm-echo-server.py`) |
| Address of `istiod` for the VM | a fixed `LoadBalancer` address (`istiod-lb`, port 15012) |

## How to do this exercise

We go through the steps one by one. For every step the trainer explains what happens and why. You do **not** type everything by hand: the script `vm-in-the-mesh.sh` (in the folder `virtual-machines` on your bastion host) runs the steps for you.

```
cd virtual-machines
./vm-in-the-mesh.sh
```

For every step the script prints the commands first and waits:

```
... to continue press ENTER
```

Press ENTER and the script runs exactly the commands you see. You can copy any of them and type it yourself. The run itself takes about one minute, plus the time for the explanations.

## The steps

### Step 1: Settings

The script sets the contexts of both clusters, the name of the VM and the IPv6 address of the VM.

```
export CTX_A=cluster-a
export CTX_B=cluster-b
export VM=a-vm1
export VM_IP=$(ssh $VM "ip -6 -o addr show dev eth0 scope global" | awk '{print $4}' | cut -d/ -f1 | head -1)
```

### Step 2: Make `istiod` ready for VMs

The VM is outside the cluster and must reach `istiod` from outside. The script does two things:

* It switches on auto-registration (`PILOT_ENABLE_WORKLOAD_ENTRY_AUTOREGISTRATION`), the DNS proxy and `ISTIO_DUAL_STACK` with `helm upgrade istiod ... --reuse-values`.
* It creates the Service `istiod-lb` of type `LoadBalancer` with a fixed IPv6 address (MetalLB), port 15012.

If your lab is already prepared, the script says so and skips the step.

```
kubectl --context $CTX_A -n istio-system get svc istiod-lb
```

```
NAME        TYPE           CLUSTER-IP          EXTERNAL-IP               PORT(S)
istiod-lb   LoadBalancer   fd00:10:96::d:ec63  2a01:4f8:1c17:5cbc::2:2   15012:32132/TCP
```

The VM uses the EXTERNAL-IP. The cluster IP (`fd00:...`) exists only inside the cluster.

### Step 3: Create the objects for the VM

Namespace `vm`, service account `diameter-adapter` and the Service `diameter-adapter` in **both** clusters (so that cluster b finds the VM, too). The `WorkloadGroup` (the template for the VM) only in cluster a. The Service finds the VM by the label `app=diameter-adapter`. The script writes the two files `01-vm-objects.yml` and `02-workloadgroup.yml` and shows their content.

```
kubectl --context $CTX_A apply -f 01-vm-objects.yml -f 02-workloadgroup.yml
kubectl --context $CTX_B apply -f 01-vm-objects.yml
```

### Step 4: Create the files for the VM

`istioctl` writes everything the VM needs: root certificate, token, mesh configuration, address of `istiod`. Then the script copies the folder to the VM.

```
istioctl --context $CTX_A x workload entry configure -f 02-workloadgroup.yml -o vmfiles --clusterID cluster-a --ingressIP $ISTIOD_ADDR --autoregister
scp -q -r vmfiles vm-echo-server.py $VM:/root/
```

`--autoregister` is important: without it `istiod` does not create the `WorkloadEntry`. The file `istio-token` is a secret. Do not print it and do not commit it.

### Step 5: Install the sidecar on the VM and start it

The script logs in to the VM and does this: install `istio-sidecar.deb`, copy the files to the places the sidecar reads them from, add `ISTIO_SVC_IP` (the address of the VM) and `DUAL_STACK='true'` to `cluster.env`, start the sidecar and the echo server.

### Step 6: Is the VM in the mesh?

```
istioctl --context $CTX_A proxy-status | grep -E "NAME|vm"
kubectl --context $CTX_A get workloadentry -n vm
```

```
NAME                 CLUSTER     ISTIOD                    VERSION   SUBSCRIBED TYPES
v6-tln1-a-vm1.vm     cluster-a   istiod-59c4f47fc9-b2vwb   1.29.9    5 (CDS,LDS,EDS,RDS,NDS)

NAME                                         AGE   ADDRESS
diameter-adapter-2a01-4f8-c013-541--1-net1   10s   2a01:4f8:c013:541::1
```

The VM is connected to `istiod`, and the `WorkloadEntry` holds the IPv6 address of the VM. This does not show yet that traffic works.

### Step 7: Test in three directions

From a pod to the VM:

```
kubectl --context $CTX_A exec deploy/client -c curl -- curl -s -m 8 -w "\nHTTP %{http_code}\n" http://diameter-adapter.vm.svc.cluster.local:8000/
```

```
VM diameter-adapter (IPv6), client=::6
x-forwarded-client-cert: By=spiffe://cluster.local/ns/vm/sa/diameter-adapter;Hash=...;URI=spiffe://cluster.local/ns/default/sa/default
HTTP 200
```

The header `x-forwarded-client-cert` shows the identities of both sides: mTLS between the pod and the VM.

From the VM to a service in the cluster (the sidecar of the VM resolves the name, DNS proxy):

```
ssh $VM 'curl -s -m 8 -o /dev/null -w "HTTP %{http_code}\n" http://productpage.default.svc.cluster.local:9080/productpage'
```

From a pod in **cluster b** to the VM (the VM is registered in cluster a, cluster b finds it through the mesh link):

```
kubectl --context $CTX_B exec deploy/client -c curl -- curl -s -m 8 -w "\nHTTP %{http_code}\n" http://diameter-adapter.vm.svc.cluster.local:8000/
```

All three answer `HTTP 200`.

## Why `ISTIO_SVC_IP`?

`ISTIO_SVC_IP` is a variable in `/var/lib/istio/envoy/cluster.env` on the VM. It tells the sidecar which address to register with `istiod`. That address becomes the `ADDRESS` of the `WorkloadEntry`, and it is the address other pods use to call the VM.

The start script `/usr/local/bin/istio-start.sh` (part of `istio-sidecar.deb`) reads `cluster.env` and then does this:

```
if [ -z "${ISTIO_SVC_IP:-}" ]; then
  ISTIO_SVC_IP=$(hostname --all-ip-addresses | cut -d ' ' -f 1)
fi
```

So if you do not set the variable, the sidecar takes the **first** address the operating system lists. A VM with both IPv4 and IPv6 can list the IPv4 address first. In our lab the VM has a private IPv4 address (`100.65.9.93`) and an IPv6 address:

```
ssh $VM hostname --all-ip-addresses
```

```
100.65.9.93 2a01:4f8:c013:541::1
```

We measured both cases (the sidecar was restarted after changing `cluster.env`):

| `cluster.env` | `ADDRESS` of the `WorkloadEntry` | Call from a pod |
|---|---|---|
| `ISTIO_SVC_IP='2a01:4f8:c013:541::1'` | `2a01:4f8:c013:541::1` | `HTTP 200`, mTLS |
| no `ISTIO_SVC_IP` | `100.65.9.93` | `HTTP 503` (3 of 3 calls) |

In an IPv6 single stack cluster nobody can reach the IPv4 address, so the VM is "in the mesh" but unreachable.

The order of the addresses comes from the operating system, not from Istio. On another VM the IPv6 address may come first. Do not rely on it: **always set `ISTIO_SVC_IP`** to the address that the cluster must use, one value per VM. If you create `cluster.env` again (a new `istioctl x workload entry configure`), the variable is gone and you must add it again.

Always check the result:

```
kubectl --context $CTX_A get workloadentry -n vm
```

The column `ADDRESS` must show the IPv6 address you expect.

## If you leave out the dual stack switches

Without `ISTIO_DUAL_STACK` and `DUAL_STACK` the VM still joins the mesh and shows up in `proxy-status`, but the call from a pod fails. Measured on an earlier lab VM:

| Missing | Result of the call |
|---|---|
| neither `DUAL_STACK` nor `ISTIO_DUAL_STACK` in `cluster.env` on the VM | no iptables rules for IPv6, the request reaches the application directly: `503`, `WRONG_VERSION_NUMBER` (the pod speaks TLS, the answer is plain text) |
| `ISTIO_DUAL_STACK` in `istiod` | rules exist, but Envoy on the VM listens on IPv4 only: `503`, `Connection refused` |

## Good to know

* The sidecar service is not enabled at boot (`systemctl is-enabled istio` shows `disabled`). After a reboot of the VM the sidecar does not start by itself.
* While the sidecar redirects IPv6 traffic to a port where Envoy does not listen, the outgoing IPv6 traffic of the VM is disturbed, too (a download with `curl` fails). SSH keeps working (port 22 is excluded).
* The files in `vmfiles` contain a token. Do not share them.

## Clean up

```
./vm-in-the-mesh.sh cleanup
```

The script deletes the namespace `vm` in both clusters, the two test pods and the sidecar files on the VM. The settings of `istiod` stay.
