# Hinweise für Claude: Workshop Istio Hybrid

Diese Datei ist **kein Teilnehmer-Material** (Deutsch, nur für die Arbeit mit Claude). Alles andere im Repo ist Teilnehmer-Material und steht **auf Englisch**.
Die deutschen Vorbereitungsnotizen (Telekom-Gespräche, Messungen, Probleme, Agenda-Entwurf) liegen im Repo `~/projects/02-training/vorbereitung/training-istio-telekom`.
Format der Übungen: Skill `workshop-training`.

## Regeln für Seiten

- Englisch, **keine Umlaute**, Code-Blöcke **ohne Sprach-Annotation**, Manifeste `.yml`.
- Jede Seite in die Agenda der `README.md` eintragen. In `fundamentals/` gibt es eine Kette `Previous:` / `Next:` am Ende jeder Seite; beim Anfügen einer Seite beide Enden pflegen und alle Links prüfen.
- **Befehle nur nach Test am echten Lab.** Ausgaben auf den Seiten sind die echten Ausgaben vom Lab. Nie schätzen (Zeiten, `AGE`, Adressen).
- **Aussagen über Istio belegen:** Messung am Lab oder Istio-Doku (Zitat). Eigenes Wissen als solches kennzeichnen und **nicht auf eine Seite schreiben, solange es nicht geprüft ist.** Beispiele, die bewusst nicht drin stehen, weil nicht ausprobiert: `pilot-agent request POST logging?level=…`, `istioctl dashboard controlz`.
- Kein Abschnitt "Background". **Kurz halten und nichts wiederholen, was die Grafik schon zeigt** (Entscheidung 2026-11-06).
- Flüsse in **einer Richtung** beschreiben (Pod B ruft Pod C), den Rückweg nicht zeichnen.
- **Bestehende Seitennamen nicht umbenennen** (Links sind in Umlauf). Neue Seiten hinten anhängen. Entschieden: `fundamentals/06` (Ports) und `07` (Injection) bleiben so.
- Keine Telekom-Interna in Teilnehmer-Seiten. Aussagen über die Telekom nur mit Transkript-Zeilen, im Vorbereitungsrepo.
- Hinweis "Attention" für VMs: IPv6 only, IPv4-Adresse der VM abschalten, sonst Dual-Stack-Gefrickel.

## Grafiken (`images/*.svg`)

- Breite 1200, Schrift Segoe UI/Arial, Pfeile mit Markern, nummerierte Kreise, Legende unten. Farben: Cluster/`istiod` grün (`#3b8a3b`, `#f3faf3`), Pod/Proxy blau (`#4a6fa5`, `#1a5fb4`), Ambient/Waypoint violett (`#7a4fa5`), Verkehr orange (`#d9730d`).
- **Immer rendern und ansehen**: `rsvg-convert -w 1200 x.svg -o <png>`, dann mit Read ansehen. Prüfen: kein überlappender Text, Pfeile kreuzen sich nicht, Beschriftungen kleben nicht an Pfeilspitzen.
- Dem User zeigen: SVG nach `%TEMP%` kopieren (`cmd.exe /c "echo %TEMP%"`, `wslpath -u`) und mit `"/mnt/c/Program Files/Google/Chrome/Application/chrome.exe"` öffnen (Skill `show-user-content`). Danach die Kopie löschen. Nachfragen, ob es angekommen ist.
- Auf GitHub sieht man Änderungen an Bildern erst nach `Strg+F5`.

## Lab für Tests

- Training `tk-test`, Teilnehmer `tln1`, aufgebaut mit dem Skill `training-hetzner-ipv6-cluster` (Skripte **aus dem Root des Vorbereitungsrepos** starten, dort liegen die Tokens). Zwei Cluster `cluster-a`, `cluster-b`, je ein Worker und eine VM, Istio 1.29.9, alle IPv6 only.
- Bastion `client-istio-telekom.do.t3isp.de`. Tests laufen als `tln1` (`su - tln1`). Technik: `source …/scripts/lib.sh; init tk-test; B_write <ziel> tln1 755 < skript; bssh "su - tln1 -c 'bash skript'"`. **Testskripte danach vom Bastion löschen**, nichts in `/home/tln1` liegen lassen.
- **Kosten:** 6 Server, etwa 0,2 EUR/h. Abbau nur nach Bestätigung des Users (`destroy.sh tk-test tln1`, vorher ohne `--yes` die Liste zeigen). Hängt ein Server: `hcloud server reset <name>`.
- **VMs haben standardmäßig keine IPv4** (Skill: `vm-ipv4.sh <training> on|off|status`). Die Übung `virtual-machines/01` läuft so. `02` (Dual Stack) ist optional und schaltet IPv4 auf der VM an und wieder aus.

## Gemessen und belegt (Istio 1.29.9, IPv6 only)

- **Sidecar** ist ein Kubernetes *native sidecar*: `istio-proxy` unter `initContainers` mit `restartPolicy: Always`, Pod zeigt `2/2`. Details: `fundamentals/06`, `07`.
- **Injection:** Webhook `istio-sidecar-injector` ruft `istiod:443/inject` (Container-Port `15017`), `failurePolicy: Fail`. Gilt nur beim Anlegen des Pods.
- **Log-Level:** Standard `istiod` `info`, Envoy `warning`. Helm: `global.logging.level` (wirkt auf `istiod` **und** auf den `pilot-agent` jedes neuen Sidecars), `global.proxy.logLevel`, `global.proxy.componentLogLevel` (nur neue Pods). Pro Pod: `sidecar.istio.io/logLevel`, `componentLogLevel`, `agentLogLevel` (im Injektions-Template gesehen, noch nicht auf einem Pod ausprobiert). Zur Laufzeit: `istioctl admin log <istiod-pod> -n istio-system` (nutzt ControlZ, Port `9876`), `istioctl proxy-config log <pod>`.
- **DNS capture** (`15053`) wird beim Anlegen des Pods gelesen. Pods, die davor gestartet sind, lauschen nicht.
- **Ambient (nur Theorie):** Weg mit Waypoint ist ztunnel → Waypoint → ztunnel, beide Strecken HBONE (mTLS, Port `15008`). Quelle: istio.io, "Ambient data plane". Waypoint ist ein Pod seines Namespace.
- Auf Istio-Seiten **fehlen** Best-Practice-Aussagen zu Log-Leveln. Faustregeln dazu sind unsere Einschätzung und gehören als solche gekennzeichnet.

## Offen / nächste Schritte

- **Abschnitt `debugging/`** (Agenda-Zeile "Debugging Istio"): `01-logs-and-log-levels.md` und `02-controlz.md` sind geschrieben, alle Befehle am Lab getestet (Level setzen und zurücksetzen mit `ads:debug` bei `istiod` und `http:debug` bei Envoy, ControlZ per Port-Forward). Noch offen, jeweils nach Test am Lab: `istioctl proxy-config` (was sieht der Envoy), `istioctl analyze`, typische Fehlerbilder (`503`), die Annotationen `sidecar.istio.io/logLevel` auf einem Pod und eine Helm-Änderung von `global.logging.level` auf dem Cluster.
- **Zustand des Labs (2026-11-06):** `istiod` hat **kein** `ISTIO_DUAL_STACK` (Helm-Revision 8), nur `PILOT_ENABLE_WORKLOAD_ENTRY_AUTOREGISTRATION` sowie `ISTIO_META_DNS_CAPTURE` und `ISTIO_META_DNS_AUTO_ALLOCATE`: der Stand nach der IPv6-only-Übung. Die optionale Dual-Stack-Übung setzt `ISTIO_DUAL_STACK` zusätzlich.
- **Helm-Falle:** `helm upgrade --reuse-values --set key=null` entfernt einen Wert **nicht** (Revision 7 war wirkungslos). Funktioniert hat: `helm get values -o yaml > v.yaml`, die Zeilen streichen, `helm upgrade -f v.yaml` ohne `--reuse-values`. Danach prüfen: Deployment-Env, ConfigMap `istio`, ControlZ `/envj/`, `proxy-status`, ein Aufruf durch einen Sidecar.
- `fundamentals/01`: Tabelle unter der Vergleichsgrafik Sidecar/Ambient kürzen? Noch nicht entschieden.
- Offene Telekom-Frage: Auto-Registrierung oder manuelle `WorkloadEntry`? Steht in keinem Transkript (Vorbereitungsrepo, `allgemeine-fragen-in-der-schulung.md`).
- Gateway-API-CRDs im Lab für die Gateway-API-Beispiele von Tag 1: noch nicht geprüft.

## Arbeitsweise mit Jochen

- Duzen, Deutsch im Chat, Seiten auf Englisch.
- **Commit und Push nur, wenn er es sagt** ("commit und push"). Jede Änderung einzeln; Commit-Nachricht auf Deutsch; Zeile `Co-Authored-By` am Ende.
- Erst Empfehlung mit kurzer Begründung nennen, dann fragen. Bleibt er unsicher, die Wahl offen lassen ("wir lassen das so").
- Bei "zeig mir …": im Browser öffnen (siehe Grafiken). Fremde Änderungen im Repo (zum Beispiel PDF-Builds, Edits auf GitHub) nicht zurücknehmen; vor dem Push `git pull --rebase`.
