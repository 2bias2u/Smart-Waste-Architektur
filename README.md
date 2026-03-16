# Smart-Waste: ein generisches Architekturmodell

Dieses Repository enthält das generische Architekturmodell für Smart-Waste-Systeme sowie einen prototypischen Implementierungsansatz zur Erfassung, <br>Verarbeitung und Nutzung von Füllstandsdaten aus smarter Müllsensorik.<br>
<br>
*Einleitung*
In vielen institutionellen Kontexten (z.B. Bildungseinrichtungen, Gesundheitseinrichtungen, Wohnquartiere) erfolgt die Abfallentsorgung auf Basis statischer Entleerungszyklen ohne Transparenz über das tatsächliche Müllaufkommen. Das führt zu überfüllten Behältern, unnötigen Leerungen und vermeidbarem Ressourcenverbrauch.<br>
​Ziel dieses Projekts ist ein generisches, schichtenbasiertes Architekturmodell, das Füllstandsdaten sensorbasiert erfasst, strukturiert verarbeitet und für Monitoring, Auswertungen und Optimierung von Entsorgungsprozessen bereitstellt.<br>
Das Architekturmodell wurde nach der Design Science Research Methodology (DSRM) nach Peffers et al. iterativ entwickelt und in mehreren Verbesserungszyklen verfeinert.
​
<br>
<br>
<br>

# Architekturmodell (6-Schichten-Modell)
Das finale Modell besteht aus sechs logisch getrennten Schichten, die Sensorik, Datenverarbeitung und Nutzung klar voneinander trennen.
​
*Physische Schicht*
Inhalt: Füllstandsensoren (z.B. Ultraschall, Gewicht), optional Aktoren.
<br>​
Aufgabe: Erfassung des Ist-Zustandes (Füllstand, Ereignisse) im Behälter.
<br>
<br>
*Gateway-Schicht*
<br>
Inhalt: LoRaWAN-Gateways, bestehende WLAN-Infrastruktur.
<br>​
Aufgabe: Übergang von Funkprotokollen (z.B. LoRaWAN, Wi-Fi) in ein IP-basiertes Netzwerk.
<br>
<br>
*Kommunikationsschicht*
<br>
Inhalt: Nachrichtenbroker / Protokolle (z.B. MQTT, HTTP).
<br>​
Aufgabe: Transport der aufbereiteten Sensordaten zur Datenverarbeitung, typischerweise in JSON-Strukturen.
<br>​
<br>
*Datenverarbeitungsschicht*
<br>
Inhalt: Workflow- / Integrationsplattform (No-Code).​
<br>
Aufgaben: Vereinheitlichung unterschiedlicher Sensorformate, Berechnung abgeleiteter Kennzahlen (z.B. Füllraten, prognostizierter Leerungszeitpunkt), Export- und Integrationslogik (z.B. Berichte, Schnittstellen).
<br>
<br>​
*Datensicherungsschicht*
<br>
Inhalt: Zeitreihendatenbank auf Basis von PostgreSQL (z.B. TimescaleDB) plus Admin-Tool.
<br>​
Aufgabe: Persistente Speicherung der Messwerte und Kennzahlen, effiziente Zeitreihenabfragen und Wartung.
<br>​
<br>
*Anwendungs- & Visualisierungsschicht*
<br>
Inhalt: Webbasiertes Dashboard (z.B. Grafana).
<br>​
Aufgaben: Visualisierung von Füllständen, Abfallströmen und Kosten, Filter- und Drill-Down-Funktionen, Exporte (z.B. Excel) für Berichtswesen.
<br>
<br>
<br>
# Simulation Vorschau
<br>
*Dashboard zur Simulation*
<br>
<img width="1864" height="57" alt="image" src="https://github.com/user-attachments/assets/3fba30b7-a4d9-402b-bba2-95d4305ac98b" />
Auswahloptionen:<br>
Abholzyklus: Wie oft wird der Müll bei einer statischen Abholung entsorgt.<br>
Abholtag: An welchem Tag wird der Müll entsorgt (*1)<br>
Simulation: Hier besteht die Auswahl zwischen 3 Simulation mit unterschiedlich starken Müllaufkommen<br>
cost_per_empty: Hier werden die Kosten für die reine Abholung eingetragen (*2)<br>
Kosten pro Volumen: Hier werden die Kosten pro Volumen (hier pro Prozent eingetragen) (*2)<br>
Überfüllungskosten: Höhe der Kosten, die pro Tag anfallen, wenn das Behältnis das Limit erreicht<br>
Limit für die Überfüllung: Ab wann gilt ein Behältnis ab voll <br>
Max. für dynamische Entsorgung: Ab wie viel % Füllstand soll das Behältnis abgeholt werden<br>
Sensoren: Für einige Statistiken, wird ein Graph pro Sensor der jeweiligen Simulation angezeigt, dieser kann hier ausgewählt werden<br>

<img width="3406" height="788" alt="Bildschirmfoto 2025-11-22 um 12 51 18" src="https://github.com/user-attachments/assets/7a41543f-1b57-4683-94c0-a162ac0b8ea2" />
Vergleich der statischen und dynamischen Kosten als Graph

<img width="3403" height="491" alt="Bildschirmfoto 2025-11-22 um 12 52 29" src="https://github.com/user-attachments/assets/a49b59e2-6cd3-414e-96be-9367347b9acd" />
Entsorgungskosten je Sensor für je statische und dynamische Entsorgung

<img width="3396" height="338" alt="Bildschirmfoto 2025-11-22 um 12 53 16" src="https://github.com/user-attachments/assets/6df36b46-4214-4abb-b937-3f59dfbbbe7c" />
Vergleich der statischen und dynamischen Kosten

<img width="3402" height="644" alt="Bildschirmfoto 2025-11-22 um 13 05 28" src="https://github.com/user-attachments/assets/8c917531-a310-4043-92c8-203c4b91e4c1" />
Überblick dynamische Entsorgungskosten je ausgewählter Sensor

<img width="3403" height="614" alt="Bildschirmfoto 2025-11-22 um 13 06 06" src="https://github.com/user-attachments/assets/68b56c18-2c38-4cd7-a9eb-cb5d224a07e7" />
Überblick statische Entsorgungskosten je ausgewählter Sensor


# Anwednungsbeispiel
Im prototypischen Szenario wird ein Campus mit verschiedenen Gebäuden, Sammelstellen und Abfallfraktionen betrachtet
<br>
*Zielsetzungen im Szenario* <br>
- Kontinuierliche Erfassung von Füllständen für ausgewählte Behälter. <br>
​- Ableitung von Kennzahlen pro Campusbereich und Abfallart (z.B. entsorgte Menge, Auslastung der Behälter). <br>
​- Bereitstellung eines Exports (z.B. Excel) für Umweltberichte und interne Auswertungen. <br>
​- Visualisierung des durchschnittlichen Füllstands vor jeder Entleerung, um Über- bzw. Unterdimensionierung und statische Entleerungszyklen zu bewerten. <br>
<br>
*Eingesetzte Software und Zuordnung zu den Schichten*

## Software pro Schicht

| Schicht                         | Aufgabe                            | Beispiel-Software im Prototyp                        |
|---------------------------------|------------------------------------|------------------------------------------------------|
| 1 – Physische Schicht          | Füllstandmessung                   | LoRaWAN-Füllstandsensor, ESP32-Ultraschall.         |
| 2 – Gateway-Schicht            | Funk → IP-Netz                     | LoRaWAN-Gateway, bestehendes Wi-Fi.                 |
| 3 – Kommunikationsschicht      | Datenübertragung                   | Mosquitto MQTT-Broker, ChirpStack MQTT.             |
| 4 – Datenverarbeitungsschicht  | Vereinheitlichung, Logik, KPIs     | n8n (No-Code-Workflows).                            |
| 5 – Datensicherungsschicht     | Zeitreihenspeicherung, SQL-Zugriff | TimescaleDB (PostgreSQL), Adminer.                  |
| 6 – Anwendung & Visualisierung | Dashboards, Filter, Exporte        | Grafana inkl. Plugins, Excel-Export via n8n.        |




_____________________________<br>
(*1) Erfolgt die Abholung nicht nach einem Wochenschema, sondern bspw. nach 10 Tagen, handelt es sich hierbei um den Start Tag<br>
(*2) Wenn sich die Kosten ausschließlich anhand der Abholungsfäufigkeit oder des Volumens berechnen, kann hier einfach 0 eingetragen werden<br>
