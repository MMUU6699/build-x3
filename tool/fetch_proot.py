import io
import os
import sys
import hashlib
import tarfile
import urllib.request
from pathlib import Path

TERMUX_POOL = os.environ.get("TERMUX_POOL", "https://packages.termux.dev/apt/termux-main/pool/main")
PROOT_VERSION = os.environ.get("PROOT_VERSION", "5.1.107.92")
TALLOC_VERSION = os.environ.get("TALLOC_VERSION", "2.4.3")
SHMEM_VERSION = os.environ.get("SHMEM_VERSION", "0.7")

ABIS = [
    ("arm", "armeabi-v7a"),
    ("aarch64", "arm64-v8a"),
    ("x86_64", "x86_64"),
]

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
JNI_LIBS = REPO_ROOT / "android" / "app" / "src" / "main" / "jniLibs"
CHECKSUMS_FILE = SCRIPT_DIR / "proot_checksums.txt"

def extract_ar(deb_bytes):
    if deb_bytes[:8] != b"!<arch>\n":
        raise ValueError("Not an ar archive")
    offset = 8
    members = {}
    while offset + 60 <= len(deb_bytes):
        header = deb_bytes[offset : offset + 60]
        offset += 60
        raw_name = header[0:16].decode("ascii", "replace").strip()
        size = int(header[48:58].decode("ascii").strip())
        payload = deb_bytes[offset : offset + size]
        offset += size + (size % 2)
        if raw_name.startswith("#1/"):
            name_len = int(raw_name[3:])
            raw_name = payload[:name_len].decode("ascii", "replace").rstrip("\x00")
            payload = payload[name_len:]
        name = raw_name.rstrip("/").split("/")[-1]
        if name:
            members[name] = payload
    return members

def download_and_extract_deb(url):
    print(f"Downloading {url} ...")
    req = urllib.request.Request(url, headers={"User-Agent": "curl/7.88.1"})
    with urllib.request.urlopen(req) as resp:
        deb_bytes = resp.read()
    ar_members = extract_ar(deb_bytes)
    data_tar_key = None
    for k in ["data.tar.xz", "data.tar.gz", "data.tar"]:
        if k in ar_members:
            data_tar_key = k
            break
    if not data_tar_key:
        raise RuntimeError(f"No data.tar* found in {url}. Found: {list(ar_members.keys())}")
    tar_bytes = ar_members[data_tar_key]
    tar = tarfile.open(fileobj=io.BytesIO(tar_bytes))
    return tar

def find_file_in_tar(tar, possible_names):
    for member in tar.getmembers():
        base = Path(member.name).name
        for target in possible_names:
            if target.endswith("*"):
                prefix = target[:-1]
                if base.startswith(prefix) and not base.endswith("32"):
                    return tar.extractfile(member).read()
            elif base == target:
                return tar.extractfile(member).read()
    raise RuntimeError(f"Could not find any of {possible_names} in tar archive")

def main():
    print(f"Fetching Termux proot {PROOT_VERSION} (+ talloc {TALLOC_VERSION}, shmem {SHMEM_VERSION})")
    for termux_arch, android_abi in ABIS:
        dest_dir = JNI_LIBS / android_abi
        dest_dir.mkdir(parents=True, exist_ok=True)
        print(f"\n== {termux_arch} -> {android_abi} ==")

        proot_url = f"{TERMUX_POOL}/p/proot/proot_{PROOT_VERSION}_{termux_arch}.deb"
        talloc_url = f"{TERMUX_POOL}/libt/libtalloc/libtalloc_{TALLOC_VERSION}_{termux_arch}.deb"
        shmem_url = f"{TERMUX_POOL}/liba/libandroid-shmem/libandroid-shmem_{SHMEM_VERSION}_{termux_arch}.deb"

        proot_tar = download_and_extract_deb(proot_url)
        talloc_tar = download_and_extract_deb(talloc_url)
        shmem_tar = download_and_extract_deb(shmem_url)

        proot_data = find_file_in_tar(proot_tar, ["proot"])
        loader_data = find_file_in_tar(proot_tar, ["loader"])
        talloc_data = find_file_in_tar(talloc_tar, ["libtalloc.so.2.*", "libtalloc.so.2", "libtalloc.so"])
        shmem_data = find_file_in_tar(shmem_tar, ["libandroid-shmem.so"])

        files = {
            "libproot_exec.so": proot_data,
            "libproot_loader.so": loader_data,
            "libtalloc.so": talloc_data,
            "libandroid-shmem.so": shmem_data,
        }

        for fname, data in files.items():
            out_file = dest_dir / fname
            out_file.write_bytes(data)
            sha = hashlib.sha256(data).hexdigest()
            print(f"  sha256 {sha} {android_abi}/{fname} ({len(data)} bytes)")

    print("\nVerifying checksums against proot_checksums.txt...")
    expected_checksums = {}
    with open(CHECKSUMS_FILE, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) >= 2:
                expected_checksums[parts[1].replace("\\", "/")] = parts[0]

    all_matched = True
    for rel_path, expected_hash in expected_checksums.items():
        full_path = REPO_ROOT / rel_path
        if not full_path.is_file():
            print(f"ERROR: Missing file {rel_path}")
            all_matched = False
            continue
        actual_hash = hashlib.sha256(full_path.read_bytes()).hexdigest()
        if actual_hash != expected_hash:
            print(f"ERROR: Checksum mismatch for {rel_path}: expected {expected_hash}, got {actual_hash}")
            all_matched = False
        else:
            print(f"OK: {rel_path}")

    if not all_matched:
        sys.exit(1)
    print("\nAll 12 libraries successfully downloaded and verified!")

if __name__ == "__main__":
    main()
