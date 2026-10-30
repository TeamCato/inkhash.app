# 0090 Neue Notizen aus dem Einbetten hängen im Baum unter ihrer Ausgangsnotiz

Status: angenommen. Dominik am 2026-10-30. Ändert die Ablage aus 0037.

## Kontext
Nach 0037 landete eine Notiz, die man beim Einbetten neu schreibt („Neue Handschrift“, „Neue Textnotiz“), in einem
Ordner, der wie die Ausgangsnotiz heißt. Im Baum standen dann die Notiz „doc“ und der Ordner „doc“ nebeneinander, und
beim Umbenennen der Ausgangsnotiz blieb der Ordner zurück. Dominik will die neue Notiz als Kind der Ausgangsnotiz sehen,
aufklappbar unter ihr.

## Entscheidung
- Eine Notiz trägt `parent`, die ID der Notiz, aus der heraus sie beim Einbetten angelegt wurde. Nur der Dialog zum
  Einbetten setzt es. Zwei vorhandene Notizen ineinander einbetten ändert an beiden nichts.
- Die neue Notiz liegt im selben Pfad wie die Ausgangsnotiz. Im Baum hängt sie unter ihr, solange beide im selben Pfad
  liegen und die Ausgangsnotiz nicht im Papierkorb ist; sonst steht sie wie jede Notiz in ihrem Pfad. Kinder können
  selbst Kinder haben.
- Eine Notiz mit Kindern hat im Baum einen Pfeil zum Auf- und Zuklappen. Zugeklappt wird nur auf dem Gerät, in
  `sidebar.json` wie die Ordner (0022), unter dem Schlüssel `/<id>`, den kein Pfad haben kann.
- Bekommt die Ausgangsnotiz einen anderen Pfad, ziehen ihre Kinder mit. Schreibt man einem Kind selbst einen anderen
  Pfad, löst es sich von der Ausgangsnotiz.
- Löschen nimmt die Kinder mit: Legt man die Ausgangsnotiz in den Papierkorb, gehen alle Notizen darunter mit.
  Wiederherstellen holt die zurück, die mit ihr gegangen sind (gleiches `deletedAt`); ein Kind, das schon vorher im
  Papierkorb lag, bleibt dort. Endgültig löschen nimmt die Kinder im Papierkorb ebenfalls mit (0089). Dominik am
  2026-10-30.
- Kennel braucht dafür nichts Neues: Er behält `parent` wie jedes andere Feld der Notiz, versiegelt oder nicht. Eine
  ältere App sieht das Kind als gewöhnliche Notiz im Pfad der Ausgangsnotiz.

## Nicht
Keine Umwandlung der Ordner, die nach 0037 entstanden sind; sie bleiben Ordner. Kein Ziehen einer Notiz unter eine
andere von Hand.
