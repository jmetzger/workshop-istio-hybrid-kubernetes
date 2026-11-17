# Build the certificate dashboard by hand

## What we do

In [Make the expiry of certificates visible](02-certificate-expiry.md) (step 5) you opened a ready-made dashboard. Here you build a smaller copy yourself, click by click, so that you can build the same for your own mesh. You need three things: numbers (metrics), a place that stores them (Prometheus) and a screen (Grafana). In the lab, Prometheus and Grafana are installed. You add the dashboard.

The dashboard you build is called **My certificates**. It does not touch the ready-made one **Lab: certificates and when they expire** (folder **lab**), you can open both side by side and compare.

The queries in steps 2 and 3 were run against Prometheus in cluster a and cluster b of the lab (Istio 1.29.9, cert-manager with istio-csr). The clicks in Grafana (steps 4 to 8) follow the menus of Grafana 12, the version of our lab. If a menu is named differently in your Grafana, look for the same word in the panel editor.

Address of Grafana and the login are in `~/monitoring-access.md`.

**Shortcut:** if you only want the result, import the finished dashboard from this repository: [certificates-dashboard.json](certificates-dashboard.json) (raw file: https://raw.githubusercontent.com/jmetzger/workshop-istio-hybrid-kubernetes/main/observability/certificates-dashboard.json). In Grafana choose **Dashboards**, **New**, **Import**, paste the address of the raw file or the content, click **Load** and **Import**. It is called **My certificates (imported)**. It expects the two data sources of our lab with the identifiers `prometheus-a` and `prometheus-b`. In another Grafana, pick your own data source in the panels afterwards. Then do steps 1 to 3 to understand what the panels ask, and compare it with what you see.

## Step 1: Where do the numbers come from

A certificate has no metric of its own. Three different components report their own certificates:

| Kind | Metric | Reported by | Unit |
|---|---|---|---|
| root CA and intermediate CA | `x509_cert_not_after` | `x509-certificate-exporter`, reads the secret `istio-ca` | point in time (seconds since 1970) |
| certificate of `istiod` | `certmanager_certificate_expiration_timestamp_seconds` | cert-manager | point in time |
| workload certificate (every sidecar and the ingress gateway) | `istio_agent_cert_expiry_seconds` | the Istio agent in every sidecar | seconds left |

Mind the units. Two metrics give a point in time, one gives the time left. To compare them you subtract `time()` (now) from the first two. You do this in step 3.

The exporter is the only part that is not in a standard Istio installation. The lab installed it with Helm (nothing to do for you, it is running):

```
kubectl -n istio-system get pods | grep x509
```

You see `x509-certificate-exporter-...` in `Running`. For your own mesh it is installed like this (values and version as in our lab, not repeated in this exercise):

```
# values.yaml
prometheusServiceMonitor: {create: false}
prometheusRules: {create: false}
secretsExporter:
  includeNamespaces: [istio-system]
  configMapKeys: [root-cert.pem]
  podAnnotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9793"
```

```
helm upgrade --install x509-certificate-exporter x509-certificate-exporter --repo https://charts.enix.io --version 4.2.4 -n istio-system -f values.yaml
```

The annotations tell the Prometheus of the Istio sample to collect from the exporter. With the Prometheus Operator you would use a `ServiceMonitor` instead.

## Step 2: Ask Prometheus first

Always check a query in Prometheus before you put it into a panel. A panel that stays empty tells you nothing about the reason. We ask from inside the cluster, with a small helper:

```
Q() { kubectl -n istio-system exec deploy/prometheus -c prometheus-server -- wget -qO- "http://localhost:9090/api/v1/query?query=$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$1")" | jq -r '.data.result[] | [(.metric | to_entries | map(.value) | join(" | ")), .value[1]] | @tsv'; }
```

How many series does each metric have?

```
Q 'count(x509_cert_not_after{secret_name="istio-ca"})'
Q 'count(certmanager_certificate_expiration_timestamp_seconds)'
Q 'count(istio_agent_cert_expiry_seconds)'
```

In our lab, cluster a gave `2`, `1` and `11`, cluster b gave `2`, `1` and `9`. Two CAs, one `istiod`, and one line per pod with a sidecar. The numbers of the workloads depend on what runs in your cluster. If one of the three gives nothing, stop here: the dashboard cannot show what Prometheus does not have.

## Step 3: One query per kind, then all three in one

**CAs: time left**

```
Q 'min by (subject_CN) (x509_cert_not_after{secret_name="istio-ca"} - time())'
```

```
Intermediate CA tln12 a	2486480.8
Lab Root CA tln12	2486479.8
```

About 2.49 million seconds, that is 28.8 days. `min by (subject_CN)` keeps one line per certificate, even if the exporter reports it twice.

**istiod: time left**

```
Q 'min by (name) (certmanager_certificate_expiration_timestamp_seconds - time())'
```

```
istiod	3068.3
```

**Workloads: time left** (already in seconds, no `time()`)

```
Q 'min by (pod) (istio_agent_cert_expiry_seconds)'
```

```
istio-ingressgateway-5dc49cc6bf-h5g9w	305.9
sleep-7bf44b8df8-dhd4m	546.0
helloworld-v1-696f8879d6-gwhqz	509.4
reviews-v1-64546cb656-p5lnv	387.9
```

The workload certificates in our lab live 10 minutes, so the values are always between 0 and 600.

**All three in one table.** For one table, every row needs the same two labels: a name (`certificate`) and a kind (`kind`). `label_replace` copies a label into a new one, and the `or` puts the three results below each other:

```
Q 'sort(min by (kind, certificate) (label_replace(label_replace(x509_cert_not_after{secret_name="istio-ca"} - time(), "certificate", "$1", "subject_CN", "(.*)"), "kind", "CA, nobody renews it", "", "")) or min by (kind, certificate) (label_replace(label_replace(certmanager_certificate_expiration_timestamp_seconds - time(), "certificate", "$1", "name", "(.*)"), "kind", "istiod, renewed by cert-manager", "", "")) or min by (kind, certificate) (label_replace(label_replace(istio_agent_cert_expiry_seconds, "certificate", "$1", "pod", "(.*)"), "kind", "workload, renewed by its agent", "", "")))' | head -6
```

```
reviews-v2-7ffdf844b8-zqgtd | workload, renewed by its agent	304.4
istio-ingressgateway-5dc49cc6bf-h5g9w | workload, renewed by its agent	305.9
reviews-v1-64546cb656-p5lnv | workload, renewed by its agent	387.9
client-7b7df66fb8-lmnfk | workload, renewed by its agent	389.5
details-v1-8445d9f444-8wgtz | workload, renewed by its agent	424.7
productpage-v1-55678c7f78-js2nf | workload, renewed by its agent	435.6
```

Read the query from the inside out. `label_replace(X, "kind", "CA, nobody renews it", "", "")` adds the label `kind` with a fixed text to every series of X (the empty source and the empty regex match always). The outer `min by (kind, certificate)` keeps only these two labels. This is the query you paste into Grafana in the next step. The ready-made dashboard uses exactly this one.

## Step 4: Create the dashboard and the first panel

1. Open Grafana in your browser (address in `~/monitoring-access.md`) and log in.
2. In the menu choose **Dashboards**, then **New**, then **New dashboard**, then **Add visualization**.
3. As data source choose **Prometheus cluster a**. (The other one, **Prometheus cluster b**, reads cluster b. You use it in step 8.)
4. At the top right of the panel editor, set the visualization to **Table**.
5. Under the query box switch the editor from **Builder** to **Code**. Paste the long query of step 3 (the text between the single quotes, without `Q` and without `| head -6`).
6. Under the query, open **Options**. Set **Format** to **Table** and **Type** to **Instant**. (An instant query asks for the value now. A table needs one row per certificate, not a line over time.)
7. Click **Run queries**. You see one row per certificate, with the columns `Time`, `certificate`, `kind` and `Value`.
8. On the right, give the panel a title: `Cluster a: all certificates, the one that expires first on top`.

## Step 5: Make the table readable

Open the tab **Transformations** (below the query) and add two transformations:

1. **Organize fields by name**: hide `Time` (click the eye), drag `certificate` to the top and `kind` below it, and rename the fields to `Certificate`, `Kind` and `Expires in` (click the pencil next to the name).
2. **Sort by**: field `Expires in`, do not reverse. The certificate that expires first is on top.

## Step 6: Show the time as a time, and the colors

On the right side, search for the option and set it for the column `Expires in` (in Grafana: **Add field override**, then **Fields with name**, then `Expires in`):

| Option | Value | Why |
|---|---|---|
| **Standard options > Unit** | **Time > Duration (d, h, m, s)** | the numbers are seconds, `2486480` becomes `28d 18h 41m 20s` |
| **Standard options > Decimals** | `0` | no fractions of a second |
| **Table > Cell options > Cell type** | **Colored background** | the whole cell gets the color |
| **Thresholds** | red as base, orange from `0`, green from `300` | red: expired (negative), orange: less than 5 minutes, green: more |

You see the rows of the CAs and of `istiod` in green. The workload rows move between orange and green all the time (the agent renews after half of the lifetime, so a workload with 10 minutes never gets much above 600 and renews at about 300). Why 300 as the limit: it is half of the 10 minutes of our lab. For your own mesh, put the limit where you would want to be warned: for the CAs weeks, not minutes.

Click **Save dashboard** at the top right. Name: **My certificates**, folder: **Dashboards** (not **lab**, so that you do not mix it with the ready-made one).

## Step 7: A second panel for the saw

A table shows now. A time series shows the history, and with it whether a certificate is renewed.

1. Click **Add**, then **Visualization**. Data source **Prometheus cluster a**, visualization **Time series**.
2. Query, in **Code** mode:

```
istio_agent_cert_expiry_seconds
```

3. Under **Options** set **Legend** to `{{pod}}`, so that every line carries the pod name. Leave **Type** on **Range**.
4. Unit: **Time > Duration (d, h, m, s)**.
5. Title: `Cluster a: workload certificates, time until they expire`.
6. At the top right of the dashboard set the time range to **Last 30 minutes** and the refresh to **10s**.

You see a saw. The line falls to about 300, the agent gets a new certificate, the line jumps up to 600. A line that falls to zero and goes below is a certificate that nobody renews.

## Step 8: The same for cluster b

The quickest way is to copy the panel and only change the data source:

1. In the title of the table panel open the menu (three dots), choose **More...**, then **Duplicate**.
2. In the new panel, open **Edit**, and change the **data source** to **Prometheus cluster b**.
3. Change the title to `Cluster b: all certificates, the one that expires first on top`.
4. Do the same with the saw panel.
5. Save the dashboard.

The query stays the same. The metrics have the same name in both clusters, only the data source decides which cluster you look at. Our dashboard shows the two tables side by side: drag the panels to place them.

## Step 9: Let it show a problem

Stop the component that signs the workload certificates in cluster a, and watch your table:

```
kubectl -n cert-manager scale deploy cert-manager-istio-csr --replicas=0
```

The workload rows fall below 300 (orange), then below 0 (red). In our lab the first one was red after about 5 minutes. The rows of the CAs and of `istiod` stay green. Start it again:

```
kubectl -n cert-manager scale deploy cert-manager-istio-csr --replicas=1
```

Within a minute the workload rows are green again. Your pods are not restarted.

## Step 10: Keep the dashboard

A dashboard you click together lives only in the Grafana database. If the Grafana pod is replaced without storage (in our lab it is, the sample add-on has none), it is gone. Two ways to keep it:

- **Export**: at the top of the dashboard choose **Export**, **Export as JSON**, and save the file. You can import it again with **Dashboards**, **New**, **Import**.
- **As code**: the file [certificates-dashboard.json](certificates-dashboard.json) in this folder is such an export. Put the JSON into a ConfigMap and mount it into Grafana with a dashboard provider, as the lab does for the ready-made dashboard. The file is `certificates-dashboard.json` in the lab setup.

Compare your export with the ready-made dashboard: it is the same few parts, a query, two transformations, a unit and thresholds, repeated for each cluster.

## Clean up

Delete your dashboard (**Dashboard settings**, **Delete dashboard**) if you do not want to keep it. Make sure `cert-manager-istio-csr` runs again:

```
kubectl -n cert-manager get deploy cert-manager-istio-csr
```
