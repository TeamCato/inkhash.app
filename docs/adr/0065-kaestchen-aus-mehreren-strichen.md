# 0065 Kästchen aus mehreren Strichen

Status: angenommen

Ändert 0060 (Aufgaben in der Handschrift) an einer Stelle: Kästchen aus mehreren Strichen werden erkannt.

## Entscheidung

Ein gemaltes Kästchen darf aus bis zu vier Strichen bestehen, die direkt nacheinander gezogen wurden, etwa ein „∩“ und danach der Boden, oder links, oben und rechts, unten. Ein Kästchen aus einem Strich wird weiter wie in 0060 erkannt.

Mehrere Striche sind ein Kästchen, wenn sie zusammen eine Fläche von Kästchengröße einschließen (8 bis 60 Seitenpunkte, ungefähr quadratisch) und diese Fläche ihr Rechteck zu mindestens 70 % füllt. Jeder Strich läuft am Rand dieser Fläche entlang, und einer von ihnen ist eine gerade, waagrechte Linie oben oder unten. Gemessen wird die eingeschlossene Fläche, nicht der Umriss der Striche: Enden, die über eine Ecke hinausstehen, und kleine Lücken an den Stößen stören nicht (`EnclosedArea`). Von mehreren passenden Gruppen gewinnt die mit den wenigsten Strichen, damit ein Haken direkt nach dem Kästchen ein Haken bleibt.

## Warum

Auf dem iPad gezeichnete Kästchen bestehen oft aus zwei oder drei Strichen. Dominiks erste Aufgabenliste in Handschrift wurde deshalb gar nicht erkannt, und die Kästchen landeten als „I“ und „1“ in der Abschrift.

Die gerade, waagrechte Linie trennt ein Kästchen von einem O aus zwei Bögen und von einem D, dessen gerader Strich senkrecht steht. Eine runde Ecke allein trennt hier nicht: Ein schnell gezeichnetes Kästchen ist oben oft so rund wie ein O.

## Nicht

Keine Kästchen aus Strichen, zwischen denen anderes geschrieben wurde. Keine Kästchen aus mehr als vier Strichen.
