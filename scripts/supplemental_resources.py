"""Fetch optional platform resources authenticated by the locked product manifest."""
import shutil
import tempfile
from pathlib import Path

import dictionary_product
import product_lock
import product_lock_shared

ASSETS = ("others.db", "dict_japanese.dat", "mozc_dictionary_oss_README.txt")


def verify(directory: Path, lock: dict) -> None:
    # Authenticate the manifest itself before trusting any supplemental digest.
    product_lock.verify_assets(directory, lock)
    dictionary_product.verify_product(directory, required_files=ASSETS)


def prepare(directory: Path, lock: dict) -> None:
    product_lock.verify_assets(directory, lock)
    try:
        verify(directory, lock)
        return
    except (OSError, ValueError):
        pass
    release = lock["dictionary"]
    with tempfile.TemporaryDirectory(dir=directory) as temporary:
        incoming = Path(temporary)
        shutil.copyfile(directory / product_lock.PRODUCT_MANIFEST, incoming / product_lock.PRODUCT_MANIFEST)
        for name in ASSETS:
            url = f"https://github.com/{release['repository']}/releases/download/{release['tag']}/{name}"
            product_lock_shared.download_with_retries(url, incoming / name)
        dictionary_product.verify_product(incoming, required_files=ASSETS)
        # No destination is replaced until the entire supplemental set is verified.
        for name in ASSETS:
            (incoming / name).replace(directory / name)
