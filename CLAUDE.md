# Hinweise für Claude: Workshop Istio Hybrid

Diese Datei ist **kein Teilnehmer-Material** (Deutsch, nur für die Arbeit mit Claude). Alles andere im Repo ist Teilnehmer-Material und steht **auf Englisch**.
Die deutschen Vorbereitungsnotizen (Telekom-Gespräche, Messungen, Probleme, Agenda-Entwurf) liegen im Repo `~/projects/02-training/vorbereitung/training-istio-telekom`.
Format der Übungen: Skill `workshop-training`. Stand dieser Datei: 2026-11-06.

## Wiederaufnahme: Stand 2026-11-06 abends und nächste Schritte

**Stand:** Alles ist gepusht (Workshop-Repo, Vorbereitungsrepo, Skills-Repo). **Das Lab ist abgebaut** (2026-11-06 21:18, auf Jochens Wunsch: 0 Server, 0 Firewalls, 0 Primary-IPs, keine DNS-Einträge mehr). Das Arbeitsverzeichnis `~/ipv6-clusters/tk-test/` und der Hetzner-Schlüssel `training-tk-test` bleiben. **Neuaufbau nächste Woche** (siehe Abschnitt "Lab für Tests"). Heute fertig geworden: IPv6-only-Übung `virtual-machines/01` und optionale Dual-Stack-Übung `02`, `fundamentals` 01 bis 07 mit Grafiken, `debugging/` 01 und 02, `cleanup` entfernt das Sidecar-Paket, `_README.md` steht in `.gitignore`, `accept_ra` ist aus `prep.sh` gestrichen, Frage 5 (Namespaces der VMs) steht in der Fragenliste im Vorbereitungsrepo.

**Jochen macht erst nächste Woche weiter** (morgen eine andere Schulung).

**Nächster Schritt 1: Theorie und Übung auf getrennte Seiten** (Jochens Wunsch, Entscheidung 2026-11-06, noch nicht umgesetzt):
- Pro Thema **zwei Seiten**: (1) **Theorie**, ohne Befehle, steht zuerst. (2) **Übung**: erst eine kurze **Erklärung der Übung** ("What we do"), dann die Schritte.
- Namen: Die Theorie bekommt eine neue `00-…`-Seite (so ist es in `virtual-machines/` schon). Die Übungsseiten **behalten ihren Namen** (Links sind in Umlauf). In der Agenda steht die Theorie vor der Übung.
- Befehle und Ausgaben werden nur **verschoben, nicht geändert**. Dann ist kein neuer Labtest nötig. Danach prüfen: alle Links, Agenda, `Previous:`/`Next:`.
- **Erledigt als Muster (2026-11-06): `virtual-machines/01`.** Theorie neu in `virtual-machines/00-how-a-vm-joins-the-mesh.md` (ohne "Background", Befehle und Ausgaben unverändert verschoben, endet mit `Next:` auf die Übung), die Übung `01-add-a-vm-to-the-mesh.md` hat jetzt: Titel, Bild, Attention, Verweis auf die Theorie, **"What we do"** (Tabelle der Teile und eine Liste der Schritte), **"Before you start"**, "How to do this exercise", **"The steps"** (Schritt 8 "Check on the VM" ist nicht Teil des Skripts) und "Clean up". Agenda: Theorie steht vor der Übung. Alle 20 Befehlsblöcke der alten Seite sind erhalten (per Skript verglichen).
- **Noch zu trennen, nach demselben Muster** (heute vermischt: Abschnitt "Background" oder Erklärtext direkt vor den Schritten): `virtual-machines/02` (290 Zeilen, wiederholt viel von `01`: zuerst klären, ob es die neue Theorieseite mitbenutzt, statt alles zu kopieren), `virtual-machines/00-workloadgroup-workloadentry-endpointslice` (Theorie und Schritte), `multi-cluster/01` und `02`, `ingress-gateway/01`, `explore-the-lab/01`, `debugging/01` und `02` (Theorie und "Try it"), `fundamentals/06` und `07` (Theorie und "Look at it yourself").

**Nächster Schritt 2: `debugging/` ausbauen**, jeweils nach Test am Lab: `istioctl proxy-config` (was sieht der Envoy), `istioctl analyze`, typische Fehlerbilder (`503`), die Pod-Annotationen für das Log-Level auf einem Pod, eine Helm-Änderung von `global.logging.level` auf dem Cluster.

**Offen, Jochen entscheidet:**
- Lab ist abgebaut. Für weitere Labtests (Debugging-Ausbau, zwei echte VMs) zuerst neu aufbauen.
- Zwei echte VMs in einem Namespace im Lab verbinden (`add-vm.sh`, etwa 0,03 bis 0,09 EUR/h je Server), damit Frage 5 eine Messung bekommt.
- `fundamentals/01`: Tabelle unter der Vergleichsgrafik Sidecar/Ambient kürzen?
- Kein Muss: ob und wie sich `15010` (Klartext-xDS) abschalten lässt, nicht geprüft.
- Gateway-API-CRDs im Lab für die Gateway-API-Beispiele von Tag 1: noch nicht geprüft.

**Offene Telekom-Fragen** (Vorbereitungsrepo, `allgemeine-fragen-in-der-schulung.md`): Auto-Registrierung oder manuelle `WorkloadEntry` (Frage 1), Adressfamilien der VMs (Frage 2, F13/F14), Namespaces der VMs (Frage 5).

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
- **Neuaufbau** (Lab ist seit 2026-11-06 abgebaut): aus dem **Root des Vorbereitungsrepos** `LAB_TYPE=cpx22 LAB_LOCATION=fsn1 ~/.claude/skills/training-hetzner-ipv6-cluster/scripts/create-all.sh tk-test tln1`. Dauert etwa 15 bis 20 Minuten, am besten im Hintergrund laufen lassen (`setsid nohup … &`, Log mitlesen; ein im Vordergrund gestarteter Lauf wurde einmal beendet). Danach prüft `create-all.sh` selbst (`verify.sh`). Frisches Lab: `istiod` ohne `PILOT_ENABLE_WORKLOAD_ENTRY_AUTOREGISTRATION` und ohne `ISTIO_DUAL_STACK` (Schritt 2 der VM-Übung setzt die Autoregistrierung), VMs ohne IPv4, `current-context` der Kubeconfig von `tln1` zeigt nach dem Abbau ins Leere, der Neuaufbau setzt ihn neu. Auf dem Bastion liegt noch `/home/tln1/virtual-machines/` mit dem Skript und der Echo-Datei (Stand `60de44a`, vor Neuaufbau mit dem Repo abgleichen). Die Hetzner-Grenze ist 160 vCPUs (11 Teilnehmer möglich).
- **Kosten und Abbau:** 6 Server kosten etwa 0,2 EUR/h. Abbau nur nach Bestätigung des Users (`destroy.sh tk-test tln1`, vorher ohne `--yes` die Liste zeigen, danach bei Hetzner und DNS prüfen). Hängt ein Server: `hcloud server reset <name>`.
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
- **Git im geteilten Arbeitsverzeichnis:** Jochen und andere Claude-Sitzungen ändern dieselben Dateien parallel. **Vor jedem `git add` die Änderung der Datei ansehen** (`git diff <datei>`) und nur die eigenen Pfade stagen. Vorfall 2026-11-06: Commit `60de44a` enthielt eine fremde Änderung am Einleitungsabsatz von `virtual-machines/01`. Beim Aktualisieren `git pull --rebase --autostash` benutzen.
- **`_README.md` ist ein Zwischenprodukt** der PDF-Action (`jmetzger/github-md2pdf`, `app.js`: liest `README.md`, schreibt `_README.md` neu, erzeugt `README.pdf`, dann `git add .; git commit -am "newest pdf"; git push`). Die Datei steht in `.gitignore` (seit 2026-11-06, vorher wurde sie durch `git add .` zufällig mit committet). Nie von Hand ändern oder committen. PDF auslösen (nur auf Wunsch): `gh workflow run pdf-deployment.yml --repo jmetzger/github-md2pdf --field repository=workshop-istio-hybrid-kubernetes`.
