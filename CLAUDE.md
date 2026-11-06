# Hinweise für Claude: Workshop Istio Hybrid

Diese Datei ist **kein Teilnehmer-Material** (Deutsch, nur für die Arbeit mit Claude). Alles andere im Repo ist Teilnehmer-Material und steht **auf Englisch**.
Die deutschen Vorbereitungsnotizen (Telekom-Gespräche, Messungen, Probleme, Agenda-Entwurf) liegen im Repo `~/projects/02-training/vorbereitung/training-istio-telekom`.
Format der Übungen: Skill `workshop-training`. Stand dieser Datei: 2026-11-06.

## Aufbau des Repos

`fundamentals/` 01 bis 07 (Erklärseiten mit Grafiken, kurz), `explore-the-lab/`, `ingress-gateway/`, `multi-cluster/`, `virtual-machines/` (`01` IPv6 only, `02` Dual Stack optional), `debugging/` (`01` Logs und Log-Level, `02` ControlZ), `images/` (SVG). Die Agenda steht in der `README.md`.

## Regeln für Seiten

- Englisch, **keine Umlaute**, Code-Blöcke **ohne Sprach-Annotation**, Manifeste `.yml`.
- Jede Seite in die Agenda der `README.md` eintragen. In `fundamentals/` und `debugging/` gibt es eine Kette `Previous:` / `Next:` am Ende jeder Seite; beim Anfügen einer Seite beide Enden pflegen und alle Links prüfen.
- **Befehle nur nach Test am echten Lab.** Ausgaben auf den Seiten sind die echten Ausgaben vom Lab. Nie schätzen (Zeiten, `AGE`, Adressen).
- **Aussagen über Istio belegen:** Messung am Lab oder Istio-Doku (Zitat). Eigenes Wissen als solches kennzeichnen und **nicht auf eine Seite schreiben, solange es nicht geprüft ist.** Bewusst nicht auf Seiten, weil nicht ausprobiert: `pilot-agent request POST logging?level=…`, die Pod-Annotationen für das Log-Level, eine Helm-Änderung von `global.logging.level` auf dem Cluster.
- Kein Abschnitt "Background". **Kurz halten und nichts wiederholen, was die Grafik schon zeigt** (Entscheidung 2026-11-06).
- Flüsse in **einer Richtung** beschreiben (Pod B ruft Pod C), den Rückweg nicht zeichnen.
- **Bestehende Seitennamen nicht umbenennen** (Links sind in Umlauf). Neue Seiten hinten anhängen. Entschieden: `fundamentals/06` (Ports) und `07` (Injection) bleiben so. In `debugging/` zuerst Logs, dann ControlZ ("so wie man es im Alltag braucht").
- Keine Telekom-Interna in Teilnehmer-Seiten. Aussagen über die Telekom nur mit Transkript-Zeilen, im Vorbereitungsrepo.
- Hinweis "Attention" für VMs: IPv6 only, IPv4-Adresse der VM abschalten, sonst Dual-Stack-Gefrickel.

## Grafiken (`images/*.svg`)

- Breite 1200, Schrift Segoe UI/Arial, Pfeile mit Markern, nummerierte Kreise, Legende unten. Farben: Cluster/`istiod` grün (`#3b8a3b`, `#f3faf3`), Pod/Proxy blau (`#4a6fa5`, `#1a5fb4`), Ambient/Waypoint violett (`#7a4fa5`), Verkehr orange (`#d9730d`).
- **Immer rendern und ansehen**: `rsvg-convert -w 1200 x.svg -o <png>`, dann mit Read ansehen. Prüfen: kein überlappender Text, Pfeile kreuzen sich nicht, Beschriftungen kleben nicht an Pfeilspitzen.
- Dem User zeigen: SVG nach `%TEMP%` kopieren (`cmd.exe /c "echo %TEMP%"`, `wslpath -u`) und mit `"/mnt/c/Program Files/Google/Chrome/Application/chrome.exe"` öffnen (Skill `show-user-content`). Danach die Kopie löschen. Nachfragen, ob es angekommen ist.
- Auf GitHub sieht man Änderungen an Bildern erst nach `Strg+F5`.

## Lab für Tests

- Training `tk-test`, Teilnehmer `tln1`, aufgebaut mit dem Skill `training-hetzner-ipv6-cluster` (Skripte **aus dem Root des Vorbereitungsrepos** starten, dort liegen die Tokens). Zwei Cluster `cluster-a`, `cluster-b`, je ein Worker und eine VM, Istio 1.29.9, Kubernetes IPv6 single stack.
- Bastion `client-istio-telekom.do.t3isp.de`. Tests laufen als `tln1` (`su - tln1`). Technik: `source …/scripts/lib.sh; init tk-test; B_write <ziel> tln1 755 < skript; bssh "su - tln1 -c 'bash skript'"`. **Testskripte danach vom Bastion löschen**, nichts in `/home/tln1` liegen lassen.
- **Kosten:** 6 Server, etwa 0,2 EUR/h. Abbau nur nach Bestätigung des Users (`destroy.sh tk-test tln1`, vorher ohne `--yes` die Liste zeigen). Hängt ein Server: `hcloud server reset <name>`.
- **Zustand (2026-11-06):** `istiod` hat **kein** `ISTIO_DUAL_STACK` (Helm-Revision 8), nur `PILOT_ENABLE_WORKLOAD_ENTRY_AUTOREGISTRATION` sowie `ISTIO_META_DNS_CAPTURE` und `ISTIO_META_DNS_AUTO_ALLOCATE`: der Stand nach der IPv6-only-Übung. Die optionale Dual-Stack-Übung setzt `ISTIO_DUAL_STACK` zusätzlich.
- **VMs haben standardmäßig keine IPv4** (Skill: `vm-ipv4.sh <training> on|off|status`, Netplan-Drop-in `99-vm-no-ipv4.yaml`). Die Übung `virtual-machines/01` läuft so. `02` (Dual Stack) ist optional und schaltet IPv4 auf der VM an und am Ende wieder aus.
- **`vm-in-the-mesh.sh cleanup`** setzt die VM auf den Stand vor der Übung zurück: Dienste stoppen, Paket `istio-sidecar` entfernen (`apt-get purge`), `/etc/istio`, `/etc/certs`, `/var/lib/istio`, `/var/run/secrets/{tokens,istio}`, Echo-Datei und Benutzer `istio-proxy` löschen. 2026-11-06 getestet: cleanup, ganze Übung (3x `HTTP 200`), cleanup. Vorher blieb das Paket installiert.
- **Helm-Falle:** `helm upgrade --reuse-values --set key=null` entfernt einen Wert **nicht** (Revision 7 war wirkungslos). Funktioniert hat: `helm get values -o yaml > v.yaml`, die Zeilen streichen, `helm upgrade -f v.yaml` ohne `--reuse-values`. Danach prüfen: Deployment-Env, ConfigMap `istio`, ControlZ `/envj/`, `proxy-status`, ein Aufruf durch einen Sidecar.
- Änderungen am Lab (Log-Level, Helm) nur wenn abgesprochen, danach zurücksetzen. Messungen sonst zuerst lesend.

### Wie das Cluster auf IPv6 only gebaut ist (Skript `build-cluster.sh`, `lib.sh`, `cloud-init-node.yaml`)

- Server ohne öffentliche IPv4 (`--without-ipv4`), jeder bekommt von Hetzner ein eigenes `/64`.
- `cloud-init-node.yaml` gilt **nur für Control Plane und Worker**, nicht für VMs. Das Skript `prep.sh` darin: Module `overlay` und `br_netfilter`, Sysctls (`bridge-nf-call-iptables`/`-ip6tables`, `ip_forward`, IPv6-`forwarding` für `all` und `default`), Swap aus, `containerd` mit `SystemdCgroup = true`, `kubelet`/`kubeadm`/`kubectl` von `pkgs.k8s.io` mit `apt-mark hold`, zum Schluss `/root/prep.done`.
- Der Platzhalter `@K8S_MINOR@` wird in `create_server` mit `sed` aus `K8S_MINOR` (`config.env`, `v1.35`) ersetzt, über eine Hilfsdatei mit `$$` und `mv` (parallele Aufrufe). `${K8S_MINOR}` in der Datei löst erst die Shell auf dem Server auf. **Das ist unser eigenes Muster, kein Standard**; cloud-init-Jinja (`## template: jinja`) kennt keine eigenen Variablen.
- `kubeadm init`: `advertiseAddress` und `kubelet --node-ip` sind die IPv6 des Servers, `podSubnet` ein IPv6-Block (`2a01:4f8::/32`, ein `/32` um den ersten Server), `serviceSubnet fd00:10:96::/108`, `allocate-node-cidrs: false`. Worker treten mit `--node-ip` auf ihre IPv6 bei.
- Calico (Operator, `v3.33.0`): ein IPPool je Knoten (`/112` im eigenen `/64`), `encapsulation: None`, `natOutgoing: Disabled`, BGP, Adresse über `NodeInternalIP`. `kube-proxy` mit `bindAddress: '::'`. Services `SingleStack` IPv6.
- **Die Nodes (Control Plane, Worker) haben auf `eth0` trotzdem die private IPv4 `100.65.x.x/32`** (Hetzner-DHCP, nicht geroutet, keine IPv4-Standardroute). Kubernetes kennt nur die IPv6 als `InternalIP`. Nur die VMs sind ohne IPv4. Beim Sprechen sauber trennen: "im Cluster" meint Kubernetes-Objekte (Pods, Services), nicht die Netzwerkkarten der Nodes.
- **Quellenlage dazu:** Gegen kubernetes.io belegt sind der `pkgs.k8s.io`-Pfad, `apt-mark hold`, Swap aus, `ip_forward` und der systemd-Cgroup-Treiber (die `containerd`-Zeile `SystemdCgroup = true` selbst nicht gelesen). **Nicht belegt:** die Brücken-Module und -Sysctls, die IPv6-Weiterleitung (eigene Einstellung), `accept_ra`: **seit 2026-11-06 nicht mehr in `prep.sh`** (Skill gepusht), weil die Standardroute statisch aus `netplan` kommt und die Einstellung unnötig Router-Rufe annahm (*Rogue-RA*-Weg). Messung davor an allen fünf Servern: auf `a-w1`, `b-cp`, `b-w1` im laufenden Kernel `2`, auf `a-cp` nach einem Neustart und auf `a-vm1` nach `netplan apply` `0`, die Einstellung ging also bei Neustart oder `netplan apply` verloren (Vermutung, nicht bewiesen: `systemd-networkd` schreibt `0`). **Am 2026-11-06 auf allen laufenden Servern angeglichen:** im Kernel `0` (auf `a-w1`, `b-cp`, `b-w1` zur Laufzeit gesetzt) und die Zeile aus `/etc/sysctl.d/k8s.conf` gestrichen (auch auf `a-cp`); Route und Knoten unverändert, alle `Ready`. Die Messkopie `netztest-hetzner-v6only/cloud-init-node.yaml` im Vorbereitungsrepo ist bewusst unverändert. Nicht belegt außerdem: Calico ohne Overlay auf Hetzner (eigene Entscheidung, `netztest-hetzner-v6only/ergebnis.md` im Vorbereitungsrepo).

## Gemessen und belegt (Istio 1.29.9, IPv6 only)

- **Sidecar** ist ein Kubernetes *native sidecar*: `istio-proxy` unter `initContainers` mit `restartPolicy: Always`, Pod zeigt `2/2`. Details: `fundamentals/06`, `07`.
- **Injection:** Webhook `istio-sidecar-injector` ruft `istiod:443/inject` (Container-Port `15017`), `failurePolicy: Fail`. Gilt nur beim Anlegen des Pods.
- **Ports von `istiod`:** `15010`, `15012`, `15014`, `15017`, `8080` auf allen Adressen (`*`), ControlZ `9876` nur auf `127.0.0.1`. Die Liste ist mit und ohne `ISTIO_DUAL_STACK` gleich. `Service istiod`: `15010`, `15012`, `443` nach `15017`, `15014`.
- **Erreichbarkeit** (Test von einem Pod ohne Sidecar): `15014` und `15010` über den Service gehen, `8080` geht über den Service nicht, aber direkt über die Pod-IP (**der Service ist keine Sicherheitsgrenze**, dafür NetworkPolicy), `9876` geht nie. `15010` (xDS im Klartext) ist von jedem Pod aus erreichbar.
- **Service → Pod von `istiod` ist IPv6** (Service `SingleStack`, EndpointSlice und Pod-IP IPv6).
- **`ISTIO_DUAL_STACK` bei `istiod`** betrifft die Konfiguration der **Proxys**, nicht `istiod` selbst. Im IPv6-only-Cluster ist es nicht nötig (Lab ohne, neuer Sidecar liefert `HTTP 200`). Nötig nur bei Workloads mit IPv4 **und** IPv6 (Dual-Stack-Seite). Ob es in `istiod` gesetzt ist, sieht man in ControlZ: `curl localhost:9876/envj/`.
- **xDS:** `istiod` schickt die Konfiguration als Delta-Updates (Scopes `delta`, `deltaadsc`). `ads` = der eine Stream (*Aggregated Discovery Service*), `adsc` = der ADS-**Client** (Istio-Paket `pkg/adsc`). Warum `istiod` einen `adsc`-Scope hat, ist nicht belegt.
- **Logs:** Zeile = Zeit, Level, **Scope**, Meldung. `-c istio-proxy` enthält `pilot-agent` (Scope z. B. `xdsproxy`) und Envoy (`envoy http …`) zusammen. Standard: `istiod` und `pilot-agent` `info`, Envoy `warning`.
- **Log-Level setzen:** Helm `global.logging.level` (wirkt auf `istiod` **und** auf den `pilot-agent` jedes neuen Sidecars, per `helm template` belegt), `global.proxy.logLevel`, `global.proxy.componentLogLevel` (nur neue Pods). Pro Pod `sidecar.istio.io/logLevel`, `componentLogLevel`, `agentLogLevel` (im Injektions-Template gesehen, **nicht auf einem Pod ausprobiert**). Zur Laufzeit `istioctl admin log` (nutzt ControlZ, Flag `--ctrlz_port`) und `istioctl proxy-config log`, beide am Lab gesetzt und zurückgesetzt.
- **ControlZ:** Seiten `argz`, `envz`, `memz`, `procz`, `scopez`, `signalz` (Inhalt nicht angesehen), `versionz`. JSON: `scopej`, `envj`, `memj`, `procj`. `istioctl dashboard controlz … --browser=false` druckt `http://localhost:9876`.
- **DNS capture** (`15053`) wird beim Anlegen des Pods gelesen. Pods, die davor gestartet sind, lauschen nicht.
- **Ambient (nur Theorie):** Weg mit Waypoint ist ztunnel → Waypoint → ztunnel, beide Strecken HBONE (mTLS, Port `15008`). Quelle: istio.io, "Ambient data plane". Waypoint ist ein Pod seines Namespace.
- **Quellenlage Log-Level:** Die Istio-Doku nennt Level und Wege (Seite *Component Logging*), gibt aber **keine Best-Practice-Empfehlung** zu Log-Leveln. *Observability Best Practices* behandeln nur Prometheus-Metriken. Für Access Logs empfiehlt die Doku die Telemetry-API (auch pro Namespace oder Workload). Praxistipps stammen aus **einer** Anbieter-Blogreihe (oneuptime.com), zweitrangig: Faustregeln auf den Seiten sind deshalb als unsere Erfahrung gekennzeichnet.

## Offen / nächste Schritte

- **`debugging/` weiter ausbauen**, jeweils nach Test am Lab: `istioctl proxy-config` (was sieht der Envoy), `istioctl analyze`, typische Fehlerbilder (`503`), Pod-Annotationen für das Log-Level, eine Helm-Änderung von `global.logging.level` auf dem Cluster.
- **Entschieden: keine Seite "How our lab is built"** (2026-11-06). Seine Fragen zum Aufbau des Clusters waren privates Interesse, kein Kursmaterial. Der Abschnitt "Wie das Cluster auf IPv6 only gebaut ist" oben ist nur Hintergrund für Claude.
- `fundamentals/01`: Tabelle unter der Vergleichsgrafik Sidecar/Ambient kürzen? Noch nicht entschieden.
- Optional für die Sicherheitsfrage: ob und wie sich `15010` (Klartext-xDS) abschalten lässt, nicht geprüft.
- Offene Telekom-Frage: Auto-Registrierung oder manuelle `WorkloadEntry`? Steht in keinem Transkript (Vorbereitungsrepo, `allgemeine-fragen-in-der-schulung.md`). Hat die Telekom-VM neben IPv6 auch IPv4 (F13/F14)?
- Gateway-API-CRDs im Lab für die Gateway-API-Beispiele von Tag 1: noch nicht geprüft.
- Lab abbauen oder behalten: Entscheidung steht aus.

## Arbeitsweise mit Jochen

- Duzen, Deutsch im Chat, Seiten auf Englisch.
- **Commit und Push nur, wenn er es sagt** ("commit und push"). Jede Änderung einzeln; Commit-Nachricht auf Deutsch; Zeile `Co-Authored-By` am Ende. Vor dem Push `git pull --rebase`; fremde Änderungen (PDF-Builds, Edits auf GitHub) nicht zurücknehmen.
- Erst Empfehlung mit kurzer Begründung nennen, dann fragen. Bleibt er unsicher, die Wahl offen lassen ("wir lassen das so").
- Bei "zeig mir …": im Browser öffnen (siehe Grafiken). Nachfragen, ob es angekommen ist.
- **Fragt er "was ist X?":** erst in Doku oder am Lab nachsehen, dann in einfachen Worten erklären (ein Vergleich hilft). Versteht er es nicht, **kürzer und an der Stelle neu erklären**, nicht dasselbe wiederholen. Bittet er um einen Satz, genau einen Satz.
- **Fragt er "Best Practice oder ausgedacht?":** ehrlich trennen, was belegt ist (mit Fundstelle), was eigene Entscheidung ist und was ungeprüft. Hat er fachlich recht, das sagen und die eigene Einschätzung anpassen, nicht verteidigen (Beispiel: Debugging ist für Betrieb und Tester ein Kernthema, deshalb ist ControlZ wichtig).
- Seine Antwort "ja bitte" gehört zur **letzten Ja/Nein-Frage**; bei Zweifel kurz sagen, wie ich es gelesen habe.
- **Nicht jede Frage ist ein Auftrag für eine Seite.** Fragt er nach dem Aufbau, den Einstellungen oder "warum", ist das oft Verständnis für sich selbst ("rein privates Interesse"). Erst beantworten, dann fragen, ob es auf eine Seite soll, und nicht ungefragt Seiten vorschlagen.
- Zwischenmeldungen von Hintergrundaufgaben (Monitor-Ereignisse) sind keine Nachrichten von ihm.
