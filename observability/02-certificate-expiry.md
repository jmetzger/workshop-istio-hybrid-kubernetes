# Make the expiry of certificates visible

## What we do

A mesh has several certificates with very different lifetimes. You look at each of them and learn which one you must watch. Measured in our lab (Istio 1.29.9, cert-manager with istio-csr).

| Certificate | Lifetime in our lab | Renewed by | What happens when it expires |
|---|---|---|---|
| root CA | 30 days | **nobody** | every workload certificate becomes invalid: the whole mesh stops |
| intermediate CA of a cluster | 30 days | **nobody** | no new workload certificates in this cluster |
| certificate of `istiod` | 1 hour | cert-manager | proxies cannot connect to `istiod` |
| workload certificate (sidecar, gateway, VM) | 1 hour | the agent in the sidecar | this workload drops out of the mesh |

The last column is what follows from the chain of trust. We did not let a root or an intermediate CA expire in our lab; for a workload certificate on a VM we measured it.

The short ones renew themselves. The dangerous ones are the long ones, because nobody renews them and nobody looks at them for months.

All commands run on your bastion host as your lab user, in cluster a.

## Step 1: The whole chain of one workload

```
istioctl proxy-config secret deploy/productpage-v1
```

```
RESOURCE NAME     TYPE           STATUS     VALID CERT     SERIAL NUMBER                                NOT AFTER                NOT BEFORE
default           Cert Chain     ACTIVE     true           2424d12790a7e085a47402f062cc44b93e1fef8c     2026-11-13T16:45:18Z     2026-11-13T15:45:18Z
ROOTCA            CA             ACTIVE     true           1df340f6da967124abca2b0e744b523aa5774535     2026-12-13T15:42:37Z     2026-11-13T15:42:37Z
```

`default` is the workload certificate (one hour), `ROOTCA` is the root (30 days in our lab). The intermediate CA is missing in this table. It is in the chain that the sidecar presents:

```
istioctl proxy-config secret deploy/productpage-v1 -o json | jq -r ".dynamicActiveSecrets[0].secret.tlsCertificate.certificateChain.inlineBytes" | base64 -d > chain.pem
while openssl x509 -noout -subject -enddate; do :; done < chain.pem 2>/dev/null
rm chain.pem
```

```
subject=O = 
notAfter=Nov 13 16:45:18 2026 GMT
subject=O = Lab, CN = Intermediate CA tln4 a
notAfter=Dec 13 15:42:39 2026 GMT
subject=O = Lab, CN = Lab Root CA tln4
notAfter=Dec 13 15:42:37 2026 GMT
```

Three certificates: workload, intermediate CA, root.

## Step 2: The root certificate

It is in a ConfigMap in every namespace:

```
kubectl get cm istio-ca-root-cert -o jsonpath="{.data.root-cert\.pem}" | openssl x509 -noout -subject -enddate
```

```
subject=O = Lab, CN = Lab Root CA tln4
notAfter=Dec 13 15:42:37 2026 GMT
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

If the time shown is in the past, the VM is out of the mesh. See [Outage: what happens to the VM](../virtual-machines/03-outage-what-happens-to-the-vm.md).

## What to watch, and how

| What | How we looked at it | Idea for an alert |
|---|---|---|
| root and intermediate CA | `openssl x509 -enddate` on the ConfigMap and on the chain | a job that reads the date and warns weeks ahead |
| certificate of `istiod` | `certmanager_certificate_expiration_timestamp_seconds` | less than half of the lifetime left: the renewal is late |
| workload certificates | `istioctl proxy-config secret`, on a VM the file | a workload is missing in `istioctl proxy-status` |

**A trap:** Envoy has a metric `envoy_server_days_until_first_cert_expiring`. It counts whole days. With certificates that live one hour it always shows `0` in our lab, so it is useless for an alert here.

The alerts in the last column are ideas, not tested rules.

Previous: [Monitoring: Prometheus, Grafana, Kiali](01-prometheus-grafana-kiali.md)
