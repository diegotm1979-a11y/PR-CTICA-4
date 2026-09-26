#!/usr/bin/env python3
"""Watches the source .numbers file for changes. When it changes (and settles
for a few seconds, to avoid catching a half-written autosave), it:
  1. Exports it to .xlsx using the Numbers app (via AppleScript). If the file
     is already open in Numbers (e.g. the user is editing it), it reuses that
     open document instead of opening a second copy, and leaves it open.
  2. Runs extract.py to regenerate webapp/data.json and webapp/images/.

Runs forever; stop with Ctrl+C.
"""
import subprocess
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_DIR = SCRIPT_DIR.parent
WEBAPP_DIR = PROJECT_DIR / "webapp"

SOURCE_NUMBERS = Path(
    "/Users/diegotueromadiedo/Desktop/BASE DATOS /Archivo Individualidades.numbers"
)
EXPORTED_XLSX = PROJECT_DIR / "scripts" / "_export_cache" / "Archivo Individualidades.xlsx"

POLL_SECONDS = 5
QUIET_SECONDS = 8  # wait for the file to stop changing before exporting

APPLESCRIPT_TEMPLATE = """
with timeout of 600 seconds
    tell application "Numbers"
        activate
        set isOpen to false
        set theDoc to missing value
        repeat with d in documents
            if name of d is "{doc_name}" then
                set isOpen to true
                set theDoc to d
                exit repeat
            end if
        end repeat
        if theDoc is missing value then
            set theDoc to open POSIX file "{src_path}"
            set weOpened to true
        else
            set weOpened to false
        end if
        delay 2
        export theDoc to POSIX file "{out_path}" as Microsoft Excel
        if weOpened then
            try
                close theDoc saving no
            end try
        end if
    end tell
end timeout
return "ok"
"""


def _applescript_escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def export_to_xlsx():
    EXPORTED_XLSX.parent.mkdir(parents=True, exist_ok=True)
    script_text = APPLESCRIPT_TEMPLATE.format(
        doc_name=_applescript_escape(SOURCE_NUMBERS.stem),
        src_path=_applescript_escape(str(SOURCE_NUMBERS)),
        out_path=_applescript_escape(str(EXPORTED_XLSX)),
    )
    script_file = EXPORTED_XLSX.parent / "_export.applescript"
    script_file.write_text(script_text, encoding="utf-8")
    result = subprocess.run(
        ["osascript", str(script_file)],
        capture_output=True,
        text=True,
        timeout=650,
    )
    if result.returncode != 0:
        raise RuntimeError(f"AppleScript export failed: {result.stderr.strip()}")


def run_extract():
    result = subprocess.run(
        [sys.executable, str(SCRIPT_DIR / "extract.py"), str(EXPORTED_XLSX), str(WEBAPP_DIR)],
        capture_output=True,
        text=True,
    )
    print(result.stdout.strip())
    if result.returncode != 0:
        print(result.stderr.strip(), file=sys.stderr)
        raise RuntimeError("extract.py failed")


def sync_once():
    print(f"[{time.strftime('%H:%M:%S')}] Cambio detectado, exportando y regenerando datos...")
    export_to_xlsx()
    run_extract()
    print(f"[{time.strftime('%H:%M:%S')}] Web app actualizada.")


def main():
    if not SOURCE_NUMBERS.exists():
        print(f"ERROR: no se encuentra el archivo fuente: {SOURCE_NUMBERS}", file=sys.stderr)
        sys.exit(1)

    print(f"Vigilando: {SOURCE_NUMBERS}")
    last_synced_mtime = None
    last_seen_mtime = None
    last_change_time = None

    # Initial sync on startup.
    try:
        sync_once()
        last_synced_mtime = SOURCE_NUMBERS.stat().st_mtime
    except Exception as e:
        print(f"Error en la sincronización inicial: {e}", file=sys.stderr)

    while True:
        time.sleep(POLL_SECONDS)
        try:
            mtime = SOURCE_NUMBERS.stat().st_mtime
        except FileNotFoundError:
            continue

        if mtime != last_seen_mtime:
            last_seen_mtime = mtime
            last_change_time = time.time()
            continue

        if (
            last_change_time is not None
            and mtime != last_synced_mtime
            and (time.time() - last_change_time) >= QUIET_SECONDS
        ):
            try:
                sync_once()
                last_synced_mtime = mtime
            except Exception as e:
                print(f"Error al sincronizar: {e}", file=sys.stderr)


if __name__ == "__main__":
    main()
