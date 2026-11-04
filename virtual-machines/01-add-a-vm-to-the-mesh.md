# Add a virtual machine to the mesh (IPv6 only)

## Background

A virtual machine joins the mesh with the Istio sidecar package (`istio-sidecar.deb`). The VM connects to `istiod`, gets a workload certificate and appears in the mesh like a pod. Istio creates a `WorkloadEntry` for it automatically (auto-registration).

The lab VM has no IPv4 connectivity: it owns one IPv6 address and nothing else. Kubernetes and Istio run as IPv6 single stack. You will see that the sidecar on a VM still needs dual stack switches. You first do it without them, see it fail in two different ways, and fix it step by step.

| Part | Name in this exercise |
|---|---|
| Namespace, service account, workload group, service | `vm`, `diameter-adapter` |
| Application on the VM | a small Python echo server on port 8000 (`vm-echo-server.py`, next to this file) |
| Address of `istiod` for the VM | a fixed `LoadBalancer` address (`istiod-lb`, port 15012) |

Commands marked **bastion** run on your bastion host (cluster A), commands marked **VM** run on the VM (as root).

```
export CTX_A=<context of cluster A>
export CTX_B=<context of cluster B>
```

## Step 1: Create the objects (bastion)

Do this in cluster A. In cluster B you only need the namespace, the service account and the service (so that cluster B finds the VM, too).

```
# vi 01-vm-objects.yml
apiVersion: v1
kind: Namespace
metadata:
  name: vm
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: diameter-adapter
  namespace: vm
---
apiVersion: v1
kind: Service
metadata:
  name: diameter-adapter
  namespace: vm
  labels:
    app: diameter-adapter
spec:
  ipFamilyPolicy: SingleStack
  ipFamilies: [IPv6]
  ports:
    - name: http
      port: 8000
      targetPort: 8000
  selector:
    app: diameter-adapter
```

```
# vi 02-workloadgroup.yml
apiVersion: networking.istio.io/v1
kind: WorkloadGroup
metadata:
  name: diameter-adapter
  namespace: vm
spec:
  metadata:
    labels:
      app: diameter-adapter
  template:
    serviceAccount: diameter-adapter
    network: net1
    ports:
      http: 8000
```

```
kubectl --context $CTX_A apply -f 01-vm-objects.yml -f 02-workloadgroup.yml
kubectl --context $CTX_B apply -f 01-vm-objects.yml
```

## Step 2: Check that `istiod` is ready for VMs (bastion)

```
kubectl --context $CTX_A -n istio-system get deploy istiod -o jsonpath='{.spec.template.spec.containers[0].env[*].name}'
```

The list must contain `PILOT_ENABLE_WORKLOAD_ENTRY_AUTOREGISTRATION`. Without it a VM appears in `istioctl proxy-status`, but no `WorkloadEntry` is created.

Find the address the VM uses to reach `istiod`:

```
kubectl --context $CTX_A get svc istiod-lb -n istio-system
```

```
NAME        TYPE           CLUSTER-IP           EXTERNAL-IP               PORT(S)
istiod-lb   LoadBalancer   fd00:10:96::3:78aa   2a01:4f8:c016:dab1::2:2   15012:32073/TCP
```

The cluster IP (`fd00:...`) cannot be reached from the VM, it only exists inside the cluster. The VM needs the EXTERNAL-IP.

```
export ISTIOD_ADDR=<EXTERNAL-IP of istiod-lb>
```

## Step 3: Create the files for the VM (bastion)

```
istioctl --context $CTX_A x workload entry configure -f 02-workloadgroup.yml -o vmfiles --clusterID <name of cluster A> --ingressIP $ISTIOD_ADDR --autoregister
ls vmfiles
```

```
cluster.env
hosts
istio-token
mesh.yaml
root-cert.pem
```

`--autoregister` is important: without it `cluster.env` lacks `ISTIO_META_AUTO_REGISTER_GROUP`. The file `istio-token` is a secret. Do not print it and do not commit it.

Copy the folder `vmfiles` and `vm-echo-server.py` to the VM:

```
scp -r vmfiles vm-echo-server.py root@[<IPv6 address of the VM>]:/root/
```

## Step 4: Install the sidecar on the VM (VM)

```
curl -fsSL https://storage.googleapis.com/istio-release/releases/1.29.9/deb/istio-sidecar.deb -o /tmp/istio-sidecar.deb
dpkg -i /tmp/istio-sidecar.deb
```

Put the files in place:

```
mkdir -p --mode=1777 /etc/certs /var/run/secrets/tokens /var/run/secrets/istio
mkdir -p /etc/istio/proxy /etc/istio/config /var/lib/istio/envoy
cd /root/vmfiles
cp root-cert.pem /etc/certs/root-cert.pem
cp istio-token /var/run/secrets/tokens/istio-token
cp cluster.env /var/lib/istio/envoy/cluster.env
cp mesh.yaml /etc/istio/config/mesh
cat hosts >> /etc/hosts
```

The file `hosts` maps `istiod.istio-system.svc` to the address of `istiod`. Now set the address of the VM itself in `cluster.env`. Without it the sidecar may register with another address of the VM:

```
echo "ISTIO_SVC_IP='<IPv6 address of the VM>'" >> /var/lib/istio/envoy/cluster.env
chown -R istio-proxy: /var/lib/istio /etc/certs /etc/istio/proxy /etc/istio/config /var/run/secrets
```

Start the sidecar and the application:

```
systemctl start istio
systemd-run --unit vm-echo python3 /root/vm-echo-server.py
```

Check on the bastion:

```
istioctl --context $CTX_A proxy-status | grep -E "NAME|vm"
kubectl --context $CTX_A get workloadentry -n vm
```

```
NAME       CLUSTER        ISTIOD                      VERSION     SUBSCRIBED TYPES
h6-vm.vm   cluster-h6     istiod-54fdb549db-z6lzq     1.29.9      5 (CDS,LDS,EDS,RDS,NDS)

NAME                                          AGE   ADDRESS
diameter-adapter-2a01-4f8-c016-17b5--1-net1   25s   2a01:4f8:c016:17b5::1
```

The VM is in the mesh, and the `WorkloadEntry` has the IPv6 address of the VM. This only shows that the VM is connected to `istiod`. It does not show that traffic works.

## Step 5: Call the VM from a pod (bastion)

Create a client with a sidecar (the namespace `default` has the label `istio-injection=enabled`):

```
kubectl --context $CTX_A create deploy client --image=curlimages/curl:8.11.1 -- sleep infinity
kubectl --context $CTX_A rollout status deploy/client
kubectl --context $CTX_A exec deploy/client -c curl -- curl -s -m 8 -w "\nHTTP %{http_code}\n" http://diameter-adapter.vm.svc.cluster.local:8000/
```

Expected (the problem):

```
upstream connect error or disconnect/reset before headers. retried and the latest reset reason: remote connection failure, transport failure reason: TLS_error:|268435703:SSL routines:OPENSSL_internal:WRONG_VERSION_NUMBER:TLS_error_end
HTTP 503
```

The sidecar of the client speaks TLS (mTLS). The answer comes back as plain text. So the request reached the application directly and was not taken over by the sidecar on the VM.

## Step 6: Find the first cause (VM)

The sidecar redirects traffic with iptables rules. Count them for both address families:

```
echo "IPv4: $(iptables-save -t nat | grep -c ISTIO)  IPv6: $(ip6tables-save -t nat | grep -c ISTIO)"
```

At this point the IPv6 count is 0 (the IPv6 nat table holds only the four empty default chains), while IPv4 has 23 rules. There are rules for IPv4 only, although the VM has only IPv6. The start script of the sidecar (`pilot-agent istio-iptables`) has no IPv6-only mode. It has only `--dual-stack`, which is switched on with the variable `DUAL_STACK`:

```
echo "DUAL_STACK='true'" >> /var/lib/istio/envoy/cluster.env
systemctl restart --no-block istio
```

Use `--no-block`, otherwise your SSH session may hang. After a few seconds:

```
echo "IPv4: $(iptables-save -t nat | grep -c ISTIO)  IPv6: $(ip6tables-save -t nat | grep -c ISTIO)"
```

```
IPv4: 23  IPv6: 19
```

Call the VM again from the bastion (step 5, the last command). Now the answer is different:

```
upstream connect error or disconnect/reset before headers. retried and the latest reset reason: remote connection failure, transport failure reason: delayed connect error: Connection refused
HTTP 503
```

## Step 7: Find the second cause (VM)

The traffic is redirected now, but to a port where nothing listens on IPv6:

```
ss -ltn | awk '{print $4}' | grep -E ':(15001|15006)$'
```

```
0.0.0.0:15001
0.0.0.0:15006
```

Envoy on the VM listens on IPv4 only. `istiod` creates the listeners and decides by the information the VM sends. The switch is `ISTIO_DUAL_STACK`, in two places: as environment variable of `istiod` and in the mesh configuration (`proxyMetadata`). With Helm (bastion):

```
helm upgrade istiod istio/istiod -n istio-system --version 1.29.9 --reuse-values --wait \
  --set-string pilot.env.ISTIO_DUAL_STACK=true \
  --set-string meshConfig.defaultConfig.proxyMetadata.ISTIO_DUAL_STACK=true
```

If your `istiod` was installed in another way, ask your trainer. The VM reads its mesh configuration from `mesh.yaml`, so create the files again (step 3, same command), copy them to the VM and put them in place again (step 4). Append `ISTIO_SVC_IP` and `DUAL_STACK` to the new `cluster.env` again, because the tool writes a fresh file. Then:

```
systemctl restart --no-block istio
sleep 8
ss -ltn | awk '{print $4}' | grep -E ':(15001|15006)$' | sort -u
```

```
0.0.0.0:15001
0.0.0.0:15006
[::]:15001
[::]:15006
```

## Step 8: Test in both directions

From a pod to the VM (bastion):

```
kubectl --context $CTX_A exec deploy/client -c curl -- curl -s -m 8 -w "\nHTTP %{http_code}\n" http://diameter-adapter.vm.svc.cluster.local:8000/ | grep -E "VM diameter|x-forwarded-client-cert|HTTP"
```

```
VM diameter-adapter (IPv6), client=::6
x-forwarded-client-cert: By=spiffe://cluster.local/ns/vm/sa/diameter-adapter;Hash=...;Subject="";URI=spiffe://cluster.local/ns/default/sa/default
HTTP 200
```

The header `x-forwarded-client-cert` shows the identities of both sides: mTLS between the pod and the VM.

From the VM to a service in the cluster (VM). The name is resolved by the DNS proxy of the sidecar:

```
curl -s -m 8 -o /dev/null -w "HTTP %{http_code}\n" http://productpage.default.svc.cluster.local:9080/productpage
```

```
HTTP 200
```

From a pod in **cluster B** to the VM (the VM is registered in cluster A). Cluster B finds it through the remote secret:

```
kubectl --context $CTX_B create deploy client --image=curlimages/curl:8.11.1 -- sleep infinity
kubectl --context $CTX_B rollout status deploy/client
kubectl --context $CTX_B exec deploy/client -c curl -- curl -s -m 8 -w "\nHTTP %{http_code}\n" http://diameter-adapter.vm.svc.cluster.local:8000/ | grep -E "VM diameter|HTTP"
```

```
VM diameter-adapter (IPv6), client=::6
HTTP 200
```

## Summary

| Step | Setting | Result |
|---|---|---|
| 5 | standard files, `--autoregister`, `ISTIO_SVC_IP` | VM in the mesh, call fails: 503 `WRONG_VERSION_NUMBER` |
| 6 | `DUAL_STACK='true'` in `cluster.env` of the VM | IPv6 rules exist, call fails: 503 `Connection refused` |
| 7 | `ISTIO_DUAL_STACK` in `istiod` | Envoy listens on `[::]`, call works: HTTP 200 with mTLS |

## Good to know

* The sidecar service is not enabled at boot (`systemctl is-enabled istio` shows `disabled`). After a reboot of the VM the sidecar does not start by itself.
* While the sidecar redirects IPv6 traffic to a port where Envoy does not listen (between step 6 and step 7), the outgoing IPv6 traffic of the VM is disturbed, too. A download with `curl` fails with "Couldn't connect". SSH keeps working (port 22 is excluded).
* The lab VM has a private IPv4 address without a default route (provider default). Whether a VM without any IPv4 address would work without `ISTIO_DUAL_STACK` was not tested.

## Clean up

On the VM:

```
systemctl stop istio
systemctl stop vm-echo
```

On the bastion:

```
kubectl --context $CTX_A delete namespace vm
kubectl --context $CTX_B delete namespace vm
kubectl --context $CTX_A delete deploy client
kubectl --context $CTX_B delete deploy client
```
