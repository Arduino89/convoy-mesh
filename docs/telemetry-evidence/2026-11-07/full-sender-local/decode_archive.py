#!/usr/bin/env python3
"""Unpack original synthetic CI evidence, checking exact bytes and file digests."""
import base64,hashlib,io,json,pathlib,sys,zipfile
source=pathlib.Path(sys.argv[1]); out=pathlib.Path(sys.argv[2]); meta=json.loads((source.parent/'export-integrity.json').read_text())['inherited_export']
raw=base64.b64decode(source.read_text().strip(),validate=True)
assert len(raw)==meta['bytes'] and hashlib.sha256(raw).hexdigest()==meta['sha256']
with zipfile.ZipFile(io.BytesIO(raw)) as z:
 assert set(z.namelist())==set(meta['files']) and sum(i.file_size for i in z.infolist())<5*1024*1024
 hashes={line[66:]:line[:64] for line in z.read('SHA256SUMS.txt').decode().splitlines()}
 for name in z.namelist():
  p=pathlib.PurePosixPath(name); assert not p.is_absolute() and '..' not in p.parts
  data=z.read(name)
  if name!='SHA256SUMS.txt': assert hashlib.sha256(data).hexdigest()==hashes[name]
  destination=out/name; destination.parent.mkdir(parents=True,exist_ok=True); destination.write_bytes(data)
print('PASS_ORIGINAL_SYNTHETIC_EXPORT',len(meta['files']))
