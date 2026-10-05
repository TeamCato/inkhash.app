# 0007 Server ist Python ohne Abhängigkeiten

Status: ersetzt durch 0014

## Entscheidung

Der Server ist die Python-Standardbibliothek in einem einzelnen Container.

## Warum

Go ist auf dieser Maschine nicht installiert. Ein Swift-Server im Linux-Container ist die schwerere Laufzeit. Eine Abhängigkeit wie FastAPI würde der Agent pflegen, ohne dass die API sie braucht.

## Nicht

Kein zweites Framework, kein ORM, keine Suche auf dem Server.
