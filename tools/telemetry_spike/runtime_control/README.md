# Controllo minimo del runtime Android

**Preparato, non compilato né eseguito in questa sessione:** la toolchain Android/JDK
precedente non è presente. I test Python verificano soltanto le guardie del runner.
Questo controllo non usa Flutter, PostHog o Firebase e non prova revoca, consegna,
privacy del SDK, batteria, GPS o Bluetooth.

App Java nativa `com.cama.telemetry.runtime_control`, versione1.0/code1, minSDK24,
target36. Nessuna permission, incluso INTERNET. Mostra PID e contatore, aggiorna
una preferenza con `commit()` e scrive una sentinella soltanto in `onResume`.
Ogni lancio del runner passa un nuovo nonce; una vecchia sentinella non può
attestare il nuovo processo. Il contatore deve aumentare esattamente di uno.

## Build locale senza download

Servono SDK **platforms/android-36**, **build-tools/36.0.0**, platform-tools/adb e
JDK **17** già installati. I percorsi sono espliciti; niente Gradle, Maven,
SDK Manager o accesso di rete. Le revisioni sono controllate prima di compilare.

```sh
python3 tools/telemetry_spike/runtime_control/build.py \
  --sdk "$ANDROID_SDK_ROOT" --jdk "$JAVA_HOME" \
  --out /tmp/convoy-runtime-control-build
```

La directory di output deve essere nuova e fuori dalla directory sorgente.
Si usano javac, d8, aapt2, zipalign e apksigner. La chiave debug usa password
pubblica `android`, viene generata soltanto nell'output ed è indipendente da
Convoy. Non distribuirla come chiave di rilascio. La ricevuta registra hash APK,
identità, firma, hash delle sorgenti e stato `BUILT_VERIFIED_NOT_RUN`.
Una build fallita non produce una ricevuta PASS. Non è un APK di Convoy.

## Gate sul solo emulatore scelto

Il proprietario del runtime avvia l'emulatore separatamente. Questo script non
crea/avvia emulatori, non configura la rete, non usa `pm clear`, non disinstalla,
non arresta server ADB e non cancella dati. Riutilizzare la stessa APK verificata
per ripetere il test: una nuova chiave debug può impedire l'aggiornamento `-r` di
un controllo già installato; il runner fallisce senza aggirare la firma.

```sh
python3 tools/telemetry_spike/runtime_control/smoke.py \
  --sdk "$ANDROID_SDK_ROOT" --jdk "$JAVA_HOME" \
  --apk /tmp/convoy-runtime-control-build/runtime-control.apk \
  --build-receipt /tmp/convoy-runtime-control-build/build-receipt.json \
  --serial emulator-5554 --out /tmp/convoy-runtime-control-smoke \
  --timeout 60
```

Gate richiesto, in ordine:

1. Hash/firma/manifest dell'APK coerenti con la ricevuta e zero permission.
2. Serial `emulator-N` esatto, `ro.kernel.qemu=1`, boot completato e package manager pronto.
3. Installazione confermata; activity effettivamente RESUMED e sentinella con nonce/PID correnti.
4. Force-stop con assenza attestata del PID, secondo lancio con PID/nonce nuovi.
5. Contatore persistente incrementato, boot ID guest invariato, controllo infine arrestato.

Output `receipt.json`: `schema_version=1`, `serial`, `boot_id`, `apk_sha256`,
`stages`, `gate_pass`, orari UTC. Soltanto tutti i passi riusciti producono
`status=PASS_NATIVE_RUNTIME_CONTROL` e `gate_pass=true`; `telemetry_tested=false`
resta sempre falso. Assenza di eventi o avvio ADB riuscito non bastano.
Le attese sono limitate: timeout10..300s per attesa, comandiADB10s, lancio≤30s,
installazione≤300s. I dump vengono letti ma non salvati; la ricevuta contiene
soltanto identità del controllo, stati e categorie di errore.

Per usare questa ricevuta come prerequisito di un altro test, verificare tutti i
passi attesi, lo stato PASS, il serial, lo stesso `boot_id` letto nuovamente dal
guest e la freschezza. Un riavvio dell'emulatore invalida il gate precedente.
Il successo del controllo nativo consente di **tentare** il LAB SDK: non ne
anticipa l'esito e non dimostra stabilità prolungata del dispositivo.

```sh
python3 -m unittest discover -s tools/telemetry_spike -p test_runtime_control.py -v
```
