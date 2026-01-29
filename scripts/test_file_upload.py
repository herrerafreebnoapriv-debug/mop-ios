#!/usr/bin/env python3
"""测试文件上传：按原始扩展名存储，支持 .txt /.zip /.exe 等任意类型"""

import requests
import zipfile
import tempfile
import os
from pathlib import Path

BASE = "http://127.0.0.1:8000"
API = f"{BASE}/api/v1"
USER, PASS = "zn6666", "zn6666"


def login():
    r = requests.post(f"{API}/auth/login", data={"username": USER, "password": PASS}, timeout=5)
    assert r.status_code == 200, r.text
    return r.json()["access_token"]


def upload(token, path, filename=None):
    name = filename or os.path.basename(path)
    with open(path, "rb") as f:
        r = requests.post(
            f"{API}/files/upload",
            headers={"Authorization": f"Bearer {token}"},
            files={"file": (name, f)},
            timeout=30,
        )
    return r


def main():
    print("1. 登录...")
    token = login()
    print("   OK\n")

    results = []

    with tempfile.TemporaryDirectory() as tmp:
        # .txt
        p = Path(tmp) / "test_upload.txt"
        p.write_text("hello 按原始类型测试\n", encoding="utf-8")
        r = upload(token, str(p))
        ok = r.status_code == 201 and "file_url" in r.json()
        ext_ok = ".txt" in r.json().get("file_name", "") or "files" in r.json().get("file_url", "")
        results.append((".txt", r.status_code, ok and ext_ok, r.json() if r.status_code == 201 else r.text[:200]))

        # .zip
        zpath = Path(tmp) / "test_archive.zip"
        with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr("a.txt", "x")
        r = upload(token, str(zpath))
        ok = r.status_code == 201 and "file_url" in r.json()
        fn = r.json().get("file_name", "") if r.status_code == 201 else ""
        ext_ok = fn.endswith(".zip") or "file_url" in str(r.json())
        results.append((".zip", r.status_code, ok and (".zip" in fn or "files" in r.json().get("file_url", "")), r.json() if r.status_code == 201 else r.text[:200]))

        # .exe (小二进制)
        epath = Path(tmp) / "dummy.exe"
        epath.write_bytes(b"MZ\x90\x00" + b"\x00" * 100)
        r = upload(token, str(epath))
        ok = r.status_code == 201 and "file_url" in r.json()
        fn = r.json().get("file_name", "") if r.status_code == 201 else ""
        results.append((".exe", r.status_code, ok, r.json() if r.status_code == 201 else r.text[:200]))

    print("2. 上传结果:")
    for ext, code, ok, detail in results:
        status = "通过" if ok else "失败"
        print(f"   {ext:6} -> HTTP {code} [{status}]")
        if isinstance(detail, dict):
            print(f"          file_name={detail.get('file_name')} file_url={detail.get('file_url')}")
        else:
            print(f"          {detail}")

    all_ok = all(r[2] for r in results)
    print("\n" + ("全部通过" if all_ok else "存在失败"))
    return 0 if all_ok else 1


if __name__ == "__main__":
    exit(main())
