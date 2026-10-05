# 0008 XcodeGen und ein gemeinsamer Kern

Status: angenommen

## Entscheidung

Das Xcode-Projekt entsteht aus `project.yml`. iPad und Mac teilen `InkhashCore` und `App/Shared`.

## Warum

`project.pbxproj` ist für Agenten ein schlechter Diff. Logik, die nur in einer der beiden Apps liegt, läuft auseinander. Der Kern hat keine UI, damit `swift test` ohne Simulator läuft.

## Nicht

Die erzeugte `xcodeproj` nicht einchecken und nicht von Hand nachziehen.
