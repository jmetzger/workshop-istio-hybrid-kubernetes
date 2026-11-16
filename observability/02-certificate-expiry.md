# Make the expiry of certificates visible

## What we do

A mesh has several certificates with very different lifetimes. You look at each of them and learn which one you must watch. Measured in our lab (Istio 1.29.9, cert-manager with istio-csr).

| Certificate | Lifetime in our lab | Renewed by | What happens when it expires |
|---|---|---|---|
| root CA | 30 days | **nobody** | every workload certificate becomes invalid: the whole mesh stops |
| intermediate CA of a cluster | 30 days | **nobody** | no new workload certificates in this cluster |
| certificate of `istiod` | 1 hour | cert-manager | proxies cannot connect to `istiod` |
| workload certificate (sidecar, gateway, VM) | 10 minutes (1 hour is the default of istio-csr) | the agent in the sidecar, after half of the lifetime | new connections of this workload fail, connections that are open keep working |

The last column is what follows from the chain of trust. We did not let a root or an intermediate CA expire in our lab; for workload certificates of pods and of a VM we measured it.

The short ones renew themselves. The dangerous ones are the long ones, because nobody renews them and nobody looks at them for months.

All commands run on your bastion host as your lab user, in cluster a.

## Step 1: The whole chain of one workload

```
istioctl proxy-config secret deploy/productpage-v1
```

```
RESOURCE NAME     TYPE           STATUS     VALID CERT     SERIAL NUMBER                                NOT AFTER                NOT BEFORE
default           Cert Chain     ACTIVE     true           3c86c8408d15841d9f5fa1ab6a843ff50774d4de     2026-11-14T10:17:45Z     2026-11-14T10:07:45Z
ROOTCA            CA             ACTIVE     true           622ad438aac119a3c725647160f33603ba53e4f7     2026-12-14T09:31:53Z     2026-11-14T09:31:53Z
```

`default` is the workload certificate (ten minutes), `ROOTCA` is the root (30 days in our lab). The intermediate CA is missing in this table. It is in the chain that the sidecar presents:

```
istioctl proxy-config secret deploy/productpage-v1 -o json | jq -r ".dynamicActiveSecrets[0].secret.tlsCertificate.certificateChain.inlineBytes" | base64 -d > chain.pem
while openssl x509 -noout -subject -enddate; do :; done < chain.pem 2>/dev/null
rm chain.pem
```

```
subject=O = 
notAfter=Nov 14 10:17:45 2026 GMT
subject=O = Lab, CN = Intermediate CA tln2 a
notAfter=Dec 14 09:31:54 2026 GMT
subject=O = Lab, CN = Lab Root CA tln2
notAfter=Dec 14 09:31:53 2026 GMT
```

Three certificates: workload, intermediate CA, root.

## Step 2: The root certificate

It is in a ConfigMap in every namespace:

```
kubectl get cm istio-ca-root-cert -o jsonpath="{.data.root-cert\.pem}" | openssl x509 -noout -subject -enddate
```

```
subject=O = Lab, CN = Lab Root CA tln2
notAfter=Dec 14 09:31:53 2026 GMT
```

## Step 3: The certificate of istiod

cert-manager manages it as a `Certificate` object and knows when it will renew it:

```
kubectl -n istio-system get certificate istiod -o jsonpath="{.status.notAfter} renew at {.status.renewalTime}{'\n'}"
```

```
2026-11-13T16:43:05Z renew at 2026-11-13T16:13:05Z
```

cert-manager also tells Prometheus (you need the add-ons from the [previous exercise](01-prometheus-grafana-kiali.md) and the helper `Q` from there). Seconds until the certificate expires:

```
Q 'certmanager_certificate_expiration_timestamp_seconds - time()'
```

The answer has one line, for the `Certificate` `istiod`, with the value `2551.9` in our lab (about 42 minutes). This metric only knows `Certificate` objects. Workload certificates are not `Certificate` objects, so they are not in it, and neither are the root and the intermediate CA.

## Step 4: A VM

On a VM the certificate is a file:

```
ssh a-vm1 "openssl x509 -noout -enddate -in /etc/certs/cert-chain.pem"
```

If the time shown is in the past, the VM cannot open new connections in the mesh. For a pod, `istioctl proxy-config secret` shows `false` in the column `VALID CERT`. See [Outage: what happens to the VM](../virtual-machines/03-outage-what-happens-to-the-vm.md).

## Step 5: All certificates at a glance in Grafana

Open Grafana (address and password are in `~/monitoring-access.md`). Choose **Dashboards**, the folder **lab**, and the dashboard **Lab: certificates and when they expire**.

It has one table for cluster a and one for cluster b. Every row is one certificate, the one that expires first is on top:

| Kind | Certificate | Where the number comes from |
|---|---|---|
| CA, nobody renews it | root CA and intermediate CA of the cluster | `x509_cert_not_after` (a small exporter reads the secret `istio-ca`) |
| istiod, renewed by cert-manager | `istiod` | `certmanager_certificate_expiration_timestamp_seconds` |
| workload, renewed by its agent | one row per pod with a sidecar, and the ingress gateway | `istio_agent_cert_expiry_seconds` (every sidecar reports it) |

The column **Expires in** is green with more than five minutes left, orange with less, and red when the certificate has expired. The workload rows move between ten and five minutes all the time: the agent renews after half of the lifetime. Below the tables you see this as a saw.

Now stop the component that signs the workload certificates in cluster a, and watch the table of cluster a:

```
kubectl -n cert-manager scale deploy cert-manager-istio-csr --replicas=0
```

Measured in our lab (seven workload certificates in cluster a):

| Time after the stop | Table of cluster a |
|---|---|
| 1 minute | shortest time left 246 seconds, nothing is red |
| 5 minutes | the first workload certificate has expired (red) |
| 10 minutes | all workload certificates have expired |
| 14 minutes | the table counts on below zero (minus 548 seconds) |

The rows of the CAs and of `istiod` stay green, and so does the whole table of cluster b: each cluster has its own istio-csr. Start it again:

```
kubectl -n cert-manager scale deploy cert-manager-istio-csr --replicas=1
```

One minute later every workload row is green again (565 seconds left in our lab). The agents ask again by themselves, you do not restart any pod.

The certificate of a VM is not in the table: Prometheus does not collect from the VM in our lab. For a VM, read the file as in step 4.

## What to watch, and how

| What | How we looked at it | Idea for an alert |
|---|---|---|
| root and intermediate CA | `openssl x509 -enddate` on the ConfigMap and on the chain | a job that reads the date and warns weeks ahead |
| certificate of `istiod` | `certmanager_certificate_expiration_timestamp_seconds` | less than half of the lifetime left: the renewal is late |
| workload certificates | `istioctl proxy-config secret`, on a VM the file | a workload is missing in `istioctl proxy-status` |

**A trap:** Envoy has a metric `envoy_server_days_until_first_cert_expiring`. It counts whole days. With certificates that live one hour it always showed `0` in our lab (and ten minutes are less than a day, too), so it is useless for an alert here.

The alerts in the last column are ideas, not tested rules. The three metrics of step 5 are the numbers such rules would use: an alert is the same question as the table, with a limit.

Previous: [Monitoring: Prometheus, Grafana, Kiali](01-prometheus-grafana-kiali.md)
Next: [Memory of the sidecars: many services, and the Sidecar object](03-sidecar-memory-and-the-sidecar-object.md)
