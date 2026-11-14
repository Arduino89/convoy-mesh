# Run 41993361681 — prove locali PASS, cloud BLOCKED

Wrapper commit `655e545709f2a40c37fb663bb3b3a6c03a8ced66`, checkout eseguibile `2d76100fda1df0637e953f4ad90f26073028880c`, workflow numero 8/tentativo 1, job 127130616352.

`bundle/` contiene esattamente l’export sintetico dal job, manifest SHA-256 e inventario. `summary.json` riporta stato/blocco e la lettura diagnostica zero, senza promuoverla a PASS o rimborso. `independent-runtime-review.json`, `independent-local-reconciliation.json` e `privacy-review.json` sono ricevute del revisore indipendente; non una nuova esecuzione Android. Nessun log completo, APK o configurazione privata inclusi.

## Riproduzione della revisione

Dalla cartella di questa prova, con Python 3 e sola libreria standard:

```sh
python3 -B support/recompute_run8_local.py bundle --support support --out /tmp/run8-recomputed.json
```

L’output deve coincidere byte per byte con `independent-local-reconciliation.json`. La prova non effettua chiamate di rete e non avvia Android. I percorsi temporanei citati nelle ricevute immutabili corrispondono ai basename nella cartella `support/`: independent-source-review.json, original-control-receipt.json, original-build-receipt.json e source-hashes.json. Gli originali controllo/build sono ricostruiti dalla stampa ordinata del job secondo la serializzazione del produttore; il revisore verifica hash esatti dei riferimenti e uguaglianza semantica agli export normalizzati.

Il budget nativo del cloud è ignoto: l’intero residuo 500 è conteggiato in modo prudenziale per qualsiasi gate futuro, residuo 0; non è un conteggio di 500 invii reali. Nessun rimborso automatico dalla query zero. Il comando fallito non è identificato fra adb install, run-as mkdir e run-as stat. Nessun rerun identico, cancellazione o integrazione autorizzati da queste prove.
