# 0086 Listenpunkte einrücken mit Tab

Status: angenommen. Dominik am 2026-10-27 („bullet lists must be indented by TAB“). Ändert ADR 0025 („Keine
verschachtelten Listen und kein Einrücken mit Tab“) und ADR 0062 („Keine verschachtelten Listen“).

## Entscheidung

1. **Ebene je Listenpunkt.** Aufzählung, Nummerierung und Aufgabe haben eine Einrückung 0 bis 4 (`Block.indent`,
   im Editor `BlockStyle.indent`). Andere Absätze haben keine.
2. **Tasten.** Tab rückt die Listenpunkte der Auswahl eine Ebene ein, höchstens eine tiefer als der Punkt darüber.
   Shift+Tab rückt aus. Return übernimmt die Ebene; Return und Rückschritt in einem leeren eingerückten Punkt rücken
   ihn erst aus, bevor er zum Absatz wird. Auf dem Mac über `insertTab`/`insertBacktab`, auf iPad und iPhone mit
   Hardware-Tastatur über Tastenbefehle, die nur in Listen gelten. In Tabellen springt Tab weiter in die nächste Zelle.
3. **Markdown.** Ein eingerückter Punkt steht unter dem Text seines Elternpunkts (`- ` zwei, `1. ` drei Zeichen), wie
   CommonMark es will; Nummern zählen je Ebene. Beim Lesen gilt dasselbe, Tabs zählen als vier Leerzeichen. Ein
   anderer Absatz beendet die Verschachtelung.
4. **Darstellung.** Je Ebene rückt Marker und Text um einen Schritt (24 pt bei Standardgröße) nach rechts.

## Nicht

- Keine eingerückten Absätze ohne Marker und keine Tab-Zeichen im Text.
