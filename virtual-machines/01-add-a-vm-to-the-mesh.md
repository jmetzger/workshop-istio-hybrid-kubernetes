# Add a virtual machine to the mesh (IPv6 only)

![A virtual machine joins the mesh: the sidecar on the VM connects to istiod, istiod creates a WorkloadEntry, a pod calls the VM through the Service](/images/vm-in-the-mesh.svg)

> **Attention:** When you use IPv6 only on the VMs (Istio hybrid), be sure that the IPv4 address on the VM is disabled. That is the best and easiest way. Otherwise you need to fiddle around (dual stack switches, `ISTIO_SVC_IP`, health `probe` workarounds).

Theory first: [How a VM joins the mesh](00-how-a-vm-joins-the-mesh.md). This page is the exercise.

## What we do

We bring one virtual machine into the mesh with the Istio sidecar. Afterwards a pod calls the VM through a normal `Service`, with mTLS, and the VM calls a service in the cluster.

| Part | Name in this exercise |
|---|---|
| VM | `a-vm1` (reach it with `ssh a-vm1`) |
| Namespace, service account, workload group, service | `vm`, `diameter-adapter` |
| Application on the VM | a small Python echo server on port 8000 (`vm-echo-server.py`) |
| Address of `istiod` for the VM | a fixed `LoadBalancer` address (`istiod-lb`, port 15012) |

The exercise has eight steps:

1. **Settings:** contexts, the name and the IPv6 address of the VM.
2. **Make `istiod` ready for VMs:** auto-registration, DNS proxy and a fixed address for `istiod`.
3. **Create the objects for the VM:** namespace, service account, `WorkloadGroup` and `Service`.
4. **Create the files for the VM:** `istioctl` writes the files the VM needs.
5. **Install the sidecar on the VM and start it.**
6. **Check:** is the VM in the mesh?
7. **Test in three directions:** pod to VM, VM to pod, cluster b to VM.
8. **Check on the VM:** iptables rules and listeners.

## Before you start

The lab VM must have **no IPv4 address**. Check it on the VM:

```
ssh a-vm1 "ip -4 -br addr show eth0; ip -6 -br addr show eth0"
```

The first command prints nothing, the second the IPv6 address. If your VM has an IPv4 address, switch it off first. The file tells the VM not to ask for an IPv4 address by DHCP:

```
ssh a-vm1 "printf 'network:\n  version: 2\n  ethernets:\n    eth0:\n      dhcp4: false\n' > /etc/netplan/99-vm-no-ipv4.yaml && chmod 600 /etc/netplan/99-vm-no-ipv4.yaml && netplan apply"
```

(Or follow the optional page [with IPv4 and IPv6 (dual stack)](02-add-a-vm-to-the-mesh-dual-stack-optional.md).)

## How to do this exercise

We go through the steps one by one. For every step the trainer explains what happens and why. You do **not** type everything by hand: the script `vm-in-the-mesh.sh` (in the folder `virtual-machines` on your bastion host) runs the steps for you.

```
cd ~/virtual-machines
./vm-in-the-mesh.sh
```

For every step the script prints the commands first and waits:

```
... to continue press ENTER
```

Press ENTER and the script runs exactly the commands you see. You can copy any of them and type it yourself. The run itself takes about one minute, plus the time for the explanations.

## The steps

### Step 1: Settings

The script sets the contexts of both clusters, the name of the VM and the IPv6 address of the VM. It also reads the IPv4 address of the VM and stops if there is one.

```
export CTX_A=cluster-a
export CTX_B=cluster-b
export VM=a-vm1
export VM_IP=$(ssh $VM "ip -6 -o addr show dev eth0 scope global" | awk '{print $4}' | cut -d/ -f1 | head -1)
export VM_IP4=$(ssh $VM "ip -4 -o addr show dev eth0 scope global" | awk '{print $4}' | head -1)
```

### Step 2: Make `istiod` ready for VMs

The VM is outside the cluster and must reach `istiod` from outside. The script does two things:

* It switches on auto-registration (`PILOT_ENABLE_WORKLOAD_ENTRY_AUTOREGISTRATION`) and the DNS proxy with `helm upgrade istiod ... --reuse-values`.
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

The command is `istioctl x workload entry configure` (`x` is short for `experimental`). It reads the `WorkloadGroup` and the mesh configuration of the cluster and writes everything the VM needs into a folder. Then the script copies the folder to the VM.

```
istioctl --context $CTX_A x workload entry configure -f 02-workloadgroup.yml -o vmfiles --clusterID cluster-a --ingressIP $ISTIOD_ADDR --autoregister
ls vmfiles
scp -q -r vmfiles vm-echo-server.py $VM:/root/
```

| Option | Meaning |
|---|---|
| `-f 02-workloadgroup.yml` | the `WorkloadGroup` of the VM (name, namespace, labels, service account, ports, network) |
| `-o vmfiles` | the folder for the files |
| `--clusterID cluster-a` | the name of the cluster the VM registers with |
| `--ingressIP $ISTIOD_ADDR` | the address of `istiod` that the VM can reach (our `istiod-lb`, see step 2) |
| `--autoregister` | `istiod` creates the `WorkloadEntry` when the VM connects. Without it the `WorkloadEntry` is missing |

The command writes five files:

```
cluster.env  hosts  istio-token  mesh.yaml  root-cert.pem
```

What the five files are and what is in them: [What the VM gets from `istioctl`](00-how-a-vm-joins-the-mesh.md#what-the-vm-gets-from-istioctl).

### Step 5: Install the sidecar on the VM and start it

The script logs in to the VM and does this: install `istio-sidecar.deb` (the download goes over IPv6), copy the files to the places the sidecar reads them from, start the sidecar and the echo server.

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


### Step 8: Check on the VM

The sidecar sets iptables rules, and Envoy listens on the IPv6 wildcard address. This step is not part of the script: type the commands yourself on the VM (`ssh a-vm1`):

```
echo "IPv4 rules: $(iptables-save -t nat | grep -c ISTIO)  IPv6 rules: $(ip6tables-save -t nat | grep -c ISTIO)"
ss -lnt | grep -E ':1500[16] '
```

```
IPv4 rules: 23  IPv6 rules: 19
LISTEN 0      4096            [::]:15006         [::]:*
LISTEN 0      4096            [::]:15006         [::]:*
LISTEN 0      4096            [::]:15001         [::]:*
LISTEN 0      4096            [::]:15001         [::]:*
```

Every port shows twice in our lab; what matters is `[::]`, the IPv6 wildcard address. What the rules mean: [What the sidecar sets on the VM](00-how-a-vm-joins-the-mesh.md#what-the-sidecar-sets-on-the-vm).

## Clean up

```
./vm-in-the-mesh.sh cleanup
```

The script deletes the namespace `vm` in both clusters and the two test pods. On the VM it stops the sidecar and the echo server and removes the sidecar package, its files and the echo server. The VM is back in the state before the exercise. The settings of `istiod` stay.
