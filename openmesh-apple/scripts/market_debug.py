import json
import os
import sqlite3
from pathlib import Path


def read_pref(cur, name: str):
    row = cur.execute("select data from preferences where name=?", (name,)).fetchone()
    if not row or row[0] is None:
        return None
    try:
        return json.loads(row[0].decode("utf-8"))
    except Exception:
        return None


def main():
    base = Path(os.path.expanduser("~/Library/Group Containers/group.com.meshnetprotocol.OpenMesh"))
    print("base:", base)

    db_path = base / "settings.db"
    if not db_path.exists():
        print("missing settings.db:", db_path)
        return

    con = sqlite3.connect(str(db_path))
    cur = con.cursor()

    selected = read_pref(cur, "selected_profile_id")
    print("\nselected_profile_id:", selected)

    installed_provider_id_by_profile = read_pref(cur, "installed_provider_id_by_profile") or {}
    installed_provider_package_hash = read_pref(cur, "installed_provider_package_hash") or {}
    print("\ninstalled_provider_id_by_profile:", installed_provider_id_by_profile)
    print("installed_provider_package_hash:", installed_provider_package_hash)

    profiles = cur.execute("select id,name,type,path from profiles order by id asc;").fetchall()
    print("\nprofiles:")
    for p in profiles:
        print(" ", p)

    selected_profile = None
    if selected is not None:
        for p in profiles:
            if int(p[0]) == int(selected):
                selected_profile = p
                break

    if selected_profile:
        pid, name, ptype, path = selected_profile
        print("\nselected_profile:", selected_profile)
        print("selected_profile exists on disk:", Path(path).exists())
        provider_id = installed_provider_id_by_profile.get(str(pid))
        print("mapped provider_id:", provider_id)
        if provider_id:
            provider_dir = base / "MeshFlux" / "providers" / provider_id
            print("\nprovider_dir:", provider_dir)
            if provider_dir.exists():
                for p in sorted(provider_dir.rglob("*")):
                    if p.is_file():
                        print(" ", p.relative_to(base))
            else:
                print("provider_dir missing")

            rule_set_dir = provider_dir / "rule-set"
            if rule_set_dir.exists():
                print("\nrule-set files:")
                for p in sorted(rule_set_dir.glob("*.srs")):
                    print(" ", p.name, p.stat().st_size, "bytes")

    con.close()

    stderr_old = base / "Library" / "Caches" / "stderr.log.old"
    stderr = base / "Library" / "Caches" / "stderr.log"
    print("\nlogs:")
    for f in [stderr_old, stderr]:
        if not f.exists():
            print(" ", f.relative_to(base), "(missing)")
            continue
        lines = f.read_text(errors="ignore").splitlines()
        interesting = [ln for ln in lines if any(k in ln for k in ["startTunnel", "failed", "completionHandler", "rule-set", "initialize rule-set", "using profile-driven config"])]
        tail = interesting[-80:]
        print(" ", f.relative_to(base), "interesting_tail_lines=", len(tail))
        for ln in tail:
            print("   ", ln)


if __name__ == "__main__":
    main()

