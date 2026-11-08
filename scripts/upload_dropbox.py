"""Upload build output using a renewable Dropbox OAuth credential."""
import json
import os
from pathlib import Path
import sys
import urllib.error
import urllib.parse
import urllib.request

def main():
    names = ("DROPBOX_APP_KEY", "DROPBOX_APP_SECRET", "DROPBOX_REFRESH_TOKEN")
    missing = [name for name in names if not os.environ.get(name)]
    if missing:
        print("::error::Dropbox noch nicht eingerichtet: " + ", ".join(missing))
        print("Die DMG ist bereits als GitHub-Artefakt gespeichert.")
        return 1
    files = sorted(Path("dist").glob("*.dmg"))
    if len(files) != 1:
        raise RuntimeError("Genau eine DMG erwartet.")
    file = files[0]
    if file.stat().st_size >= 150 * 1024 * 1024:
        raise RuntimeError("DMG überschreitet das Limit für einen Einzelupload.")
    body = urllib.parse.urlencode({
        "grant_type": "refresh_token",
        "refresh_token": os.environ["DROPBOX_REFRESH_TOKEN"],
        "client_id": os.environ["DROPBOX_APP_KEY"],
        "client_secret": os.environ["DROPBOX_APP_SECRET"],
    }).encode()
    request = urllib.request.Request("https://api.dropboxapi.com/oauth2/token", data=body)
    with urllib.request.urlopen(request, timeout=60) as response:
        token = json.load(response)["access_token"]
    print("::add-mask::" + token)
    destination = "/2 KI-Export/Bild-Atelier/" + file.name
    request = urllib.request.Request(
        "https://content.dropboxapi.com/2/files/upload",
        data=file.read_bytes(),
        headers={
            "Authorization": "Bearer " + token,
            "Content-Type": "application/octet-stream",
            "Dropbox-API-Arg": json.dumps({
                "path": destination, "mode": "overwrite",
                "autorename": False, "mute": True,
            }),
        },
    )
    with urllib.request.urlopen(request, timeout=180) as response:
        result = json.load(response)
    if result.get("size") != file.stat().st_size:
        raise RuntimeError("Dropbox meldet eine abweichende Dateigröße.")
    print("Gespeichert: " + destination)
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main())
    except urllib.error.HTTPError as error:
        # Never print response bodies or request headers containing credentials.
        print("::error::Dropbox-Anfrage fehlgeschlagen (HTTP %s)." % error.code)
        sys.exit(1)
