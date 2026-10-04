# Localizzazione pedonale — candidata sperimentale 1

Checkpoint verificato il 4 ottobre 2026. PR **#4**, branch `experiment/pedestrian-acquisition-v1`, base applicativa PR #1 `c3ef471754d7e1a4b3cf2558e5c2fadbb9d4f0a7`. La base conserva il codice applicativo della candidata precedente **0.7.6+8**, sorgente `3e056f88ab44a4fbb9989058a9191e2bebc3cba4`. Non usa main né il ledger della PR #3. Nessun merge autorizzato.

Versione **0.7.7-exp1+9**, nome Android **Convoy Mesh Exp**, package `com.example.convoy_mesh.pedestrianexp1`. Il [run #121](https://github.com/Arduino89/convoy-mesh/actions/runs/37198612027), tentativo 1, sorgente `9ca9107f229af91354116278c9970b39d0a4e81e`, ha superato **149 test, compilazione, firma/package/compatibilità e smoke API35**. L'APK esatto è verificato e pronto per la prova fisica richiesta; identità/checksum in README. Il precedente run #120 aveva fallito lo scenario lento a schermo spento; diagnosi e correzione sono riportate qui sotto. Non è una validazione GNSS/BLE sui telefoni reali.

Il fallimento del run #120 (`Local trail did not grow while screen was off (0 -> 0)`) è stato riprodotto da una revisione indipendente nello stimatore reale: tutti i **18 fix dell'uscita** coincidono con i diagnostici per decisione, candidato traccia, timestamp di supporto e latitudine mostrata, senza alcun lifecycle Android. Il GPS iniettato avanzava circa **2,2 m ogni 5 s / 0,44 m/s**: circa **8,9 m in 20 s**, sotto il gate di 10 m, mentre l'IMU dell'emulatore era affidabile e ferma. Nuovi fix e FGS continuavano; lo stesso percorso non produceva traccia anche a schermo acceso. La causa dell'interruzione della chat Work resta non verificabile dai log CI.

La correzione del 4 ottobre (`9ca9107`) riusa lo smoke esistente e conserva le soglie produttive: passo GPS normale di circa **6,7 m ogni 5 s / 1,33 m/s**, controllo positivo a schermo acceso, confine diagnostico dopo la verifica dello stato `Asleep/Dozing`, e almeno otto nuovi fix e tre punti freschi nella sola coda successiva. Richiede almeno 45 s di tempo sorgente e 45 m netti, velocità media 0,8–2 m/s e nessun salto oltre 4,2 m/s; ricontrolla lo schermo spento alla fine. Non trasforma il limite del cammino molto lento in una promessa di funzionamento.

## Correzione e limiti delle sue assunzioni

La baseline richiedeva un cluster statico anche partendo già in cammino. Fix esatti distanti 7 m, ogni 5 s, accuracy 3 m, non producevano un aggancio nei 120 s sintetici. Inoltre sette campioni a 1 Hz non coprivano mai gli 8 s richiesti e gli ultimi cinque a 1/2/2,5 s non raggiungevano la finestra di moto.

La candidata conserva la protezione statica e aggiunge acquisizione da un percorso plausibile: almeno tre osservazioni su almeno 8 s, maggioranza dei campioni temporali raggiungibile dall'endpoint entro il limite pedonale già usato di 4,2 m/s, predecessore immediato compatibile, progresso distribuito e velocità delle transizioni confrontate sul loro tempo reale. Accetta l'ultimo punto supportato. Acquisizione e riacquisizione non aggiungono un punto alla traccia. **Non esistono coordinate provvisorie pubblicate**: prima della conferma le coordinate restano assenti; in riacquisizione il precedente punto resta riconoscibile come non fresco.

Questi sono criteri di plausibilità sperimentali, non invarianti fisiche né prove di accuratezza. Tre fix possono condividere lo stesso bias. La parte di acquisizione non concede un bonus di accuracy al limite di velocità: rumore forte può quindi ritardarla. Il consenso statico resta disponibile.

La memoria conserva l'ultimo fix di ciascun secondo di tempo sorgente entro 25 s: **massimo 26 osservazioni**. La prova di moto seleziona cinque osservazioni distribuite nel tempo, includendo quella corrente. Preferisce 20 s, pari ai cinque fix nominali della baseline; se mancano cinque osservazioni usa la finestra già limitata a 25 s. Non cerca una finestra alternativa soltanto perché il moto è stato rifiutato. Non promette equivalenza esatta tra tutte le cadenze: quantizzazione, campioni disponibili e soglie restano discreti.

La sola IMU non può più autorizzare uno spostamento oltre il raggio di supporto già presente `max(12 m, accuracy dell'ancora + accuracy del fix)`. Per superarlo occorre evidenza GPS distribuita. Questo blocca il controesempio di manipolazione seguito dal salto di 20 m; non blocca ogni errore GPS né certifica che l'IMU distingua una persona che cammina da un telefono maneggiato.

Provider, `LocationAccuracy.best`, richiesta **5 s / 0 m**, classificatore IMU, BLE/HISTORY e renderer rimangono invariati. Nessun road snapping, ledger, GATT/CoC, nuova libreria di fusione o animazione. L'unica modifica al servizio di localizzazione è un orologio iniettabile nei test; il singleton di produzione usa ancora `DateTime.now`.

## Prove prima/dopo

`test/pedestrian_cadence_regression_test.dart` importa lo stimatore usato realmente da `LocationFusionService`. Il programma `tool/pedestrian_candidate_probe.dart` misura gli stessi ingressi; non contiene una copia dell'algoritmo. Tutte le coordinate sono sintetiche, attorno a zero.

Con Flutter **3.47.4**, stesso SDK del run #105, suite baseline più nuove regressioni: **122 passati / 19 falliti**. I 107 test originali passano; 19 dei 34 nuovi test falliscono. Candidata: **149/149 passati nel run #121** (107 originali, 34 regressioni condivise, 1 limite memoria, 7 contratti del servizio). I test del servizio verificano richiesta Android invariata, preview senza traccia, reset uscita, timestamp sorgente, riacquisizione in un segmento nuovo e indipendenza del Test log dall'arresto della localizzazione. I due nuovi contratti verificano che il cammino GPS a 1,2 m/s registri punti anche con IMU affidabile ferma e che un salto isolato di 20 m non rinnovi il supporto né scriva traccia. L'azione UI `Termina uscita` è verificata separatamente dallo smoke Android.

Il confronto usa copie isolate: nessuno scambio temporaneo dell'algoritmo mentre i test girano. La baseline mantiene intatti i file applicativi. Il lock originale era incompleto: è stato risolto e sono state ripristinate tutte le **76 versioni ricostruibili dai log del run #105**, incluse quattro transitive che altrimenti sarebbero avanzate. Entrambe le copie usano lo stesso lock; CI impone `--enforce-lockfile`. Non si afferma riproducibilità byte per byte della vecchia APK, non più disponibile.

| Ingresso sintetico | Baseline | Candidata |
|---|---|---|
| Partenza 1,4 m/s, accuracy 3 m, 5 s | Nessun aggancio in 120 s | Aggancio a 10 s, con o senza IMU |
| Da fermo, 1 Hz | Nessun aggancio in 30 s | 8 s |
| Partenza in movimento, cadenze 1/2/2,5/5 s e irregolare | Blocchi o mancata traccia | Aggancio 8–15 s; accuracy 3 e 5 m |
| Cammino 1,2 m/s dopo sosta, senza IMU | Nessun candidato traccia a 1/2/2,5 s | Primo candidato dopo 11/12/12,5 s; a 5 s resta 15 s |
| Outlier iniziale 300 m / accuracy 1 m | Aggancio fermo corretto a 15 s | Conservato; aggiunto caso di ripartenza in movimento |
| Riacquisizione già in cammino dopo lunga perdita | Non riacquisisce nel caso | Riconferma dopo tre fix, senza ponte di traccia |
| Telefono maneggiato + singolo salto GPS 20 m | 17 m di falso spostamento | 0 m nel caso; il salto non rinnova il supporto |
| Dropout di 10 / 20 s | Nuovo supporto dopo 0 / 20 s dalla ripresa | Stessi tempi; include misura di raffica a 1 Hz |

Una prima implementazione è stata falsificata prima della consegna: tre campioni selezionati ignoravano una maggioranza contraria; il rapporto fra distanze confondeva intervalli 1+9 s con un salto; una finestra rigida di 20 s peggiorava un dropout di 10 s. Sono stati corretti e sono presenti regressioni. Il test di recupero ora richiede **nuovo supporto dopo la ripresa**, non solo un'ancora vecchia ancora entro il TTL.

Limiti conservati e misurati, non validati dal verde:

- **0,3 m/s, accuracy 10 m, senza IMU:** zero candidati traccia nel caso di 130 s; massimo errore mentre dichiarato fresco 24 m. La successiva riacquisizione non ricostruisce il cammino perso.
- **Quattro curve a 90° / tornante:** massimo errore fresco circa 18,03 / 16,94 m, come baseline. Il requisito net/path è ancora un'ipotesi fragile per curve strette e ritorni.
- **Deriva coerente di 0,7 m/s:** circa 34,38 m di falso spostamento in 50 s dopo la sosta, come baseline. Gli stessi ingressi etichettati come cammino producono la stessa uscita: nessuna promessa simultanea di zero deriva e zero ritardo.
- Il gain resta per campione, non normalizzato sul tempo: a cadenze diverse il ritardo residuo differisce. Non è stato cambiato per isolare questa candidata.
- Accuracy dichiarata, errore rispetto alla verità sintetica e fluidità del marker sono tre cose diverse. Nessuna animazione è stata aggiunta e non è stata misurata accuratezza assoluta sui telefoni.

Risultati completi: [CSV sintetico](pedestrian-exp1-results.csv). Gli spazi vuoti indicano che l'evento non è avvenuto nella durata del caso. I candidati traccia del probe precedono i vincoli di distanza/segmento del servizio e non equivalgono a punti effettivamente salvati.

Riproduzione:

```sh
# Usare Flutter 3.47.4; dalla directory ConvoyMeshApp della candidata.
flutter pub get --enforce-lockfile
flutter test --no-pub --reporter expanded
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
dart run tool/pedestrian_candidate_probe.dart candidate
# In un worktree isolato di c3ef471, copiare soltanto il test condiviso,
# il probe e il lock della candidata; lasciare intatti lib/ e android/.
# pub get, flutter test e lo stesso probe espongono i 19 fallimenti.
```

Lo smoke API35 usa coordinate iniettate e verifica lo stesso APK prodotto dalla CI: installazione, versione/commit, preview senza FGS/traccia, reset uscita, crescita traccia a schermo spento, ripresa e Test log ancora attivo dopo `Termina uscita`. Nel run #121 il controllo a schermo acceso registra quattro punti; dopo il confine verificato di sleep arrivano **14 nuovi fix e 14 punti freschi**, su **69,01 s / 86,52 m netti / 1,25 m/s**. GPS 14 -> 28, traccia 4 -> 18; `Asleep` a entrambi i confini e stesso PID 2273 alla ripresa. Non dimostra GNSS reale, BLE fra due telefoni, deep Doze/OEM, consumi o sopravvivenza alla perdita di processo. Queste verifiche fisiche restano pendenti.

## QA indipendente e contratto di consegna

**4 ottobre 2026 — PASS_WITH_LIMITS per la prova sperimentale**, nessun blocco automatico aperto. Revisore distinto dall'autore delle modifiche: replay dei 18 ingressi del run #120, controllo dei due file contro l'archivio sorgente del run #121, verifica di tutti gli archivi/parti/hash dell'APK e verifica locale della firma v2 RSA/SHA-256 e del digest completo del contenuto. Entrambe le nuove regressioni sono presenti nel sorgente esatto, senza skip; il comando Flutter non filtrato conclude con 149 passati. Il reporter concorrente non stampa separatamente i loro nomi: inclusione provata da sorgente/comando/conteggio aggregato, senza inventare righe di log. Analisi: 21 info/warning esistenti, secondo la politica non fatale.

Il revisore ha verificato anche l'archivio `emulator-diagnostics` / `11302206225`, SHA-256 `ce83c509aabb9b391803a2147bd734d6c160a2f02496890dd85e8f5b36feedca`: APK/hash/build stamp coincidono, PID unico stabile, FGS presente soltanto durante l'uscita. Sleep 11:31:36,205–11:32:50,921 UTC; confine diagnostico 11:31:37,221415. Tutti i 14 fix/punti successivi hanno timestamp sorgente e ricezione dopo il confine e prima del risveglio; supporto vecchio soltanto 2,65–5,16 ms, velocità massima tra fix 1,423 m/s, accuracy dichiarata 5 m, `gps_motion` con IMU affidabile ferma. Preview e primo fix dell'uscita non scrivono traccia; stop uscita rimuove FGS, conserva 18 punti e lascia il Test log attivo. Nessuna eccezione intercettata. Queste coordinate sono sintetiche; i log fisici resteranno privati.

Preflight consultato sulla governance corrente di Cama-Enterprise: AGENTS/source-of-truth/operating model/Principles/CONTINUITY, routing, Pattern Registry e notebook. Applicati EP-001/003/004/005/007/009/010 e note JON-010/011/014/2026-09-08-001. Valutazione diretta dello scope noto: codice Android, integrazione fisica da provare, complessità alta, coordinate private; nessuna ricerca esterna richiesta. **Reuse-first livello 6**: correggere smoke e contratti esistenti, conservare stimatore applicativo, base PR #1, protocollo fisico e ruoli di README/CONTINUITY/questa nota. Recupero limitato a una correzione diagnosticata, un run completo e relativi artefatti; nessuna modifica a Cama-Enterprise. Output: esatta APK verificata e checkpoint esistente, PR #4 ancora draft; autorizzazione alla prova, nessun merge o rilascio di produzione. La catena di prova usa commit/evento/tentativo/step/hash, non il solo stato verde del job.

## Installazione e ritorno alla precedente

Installare soltanto l'APK identificato nel checkpoint finale su **entrambi** i telefoni. Android deve mostrare **Convoy Mesh Exp / 0.7.7-exp1**; il Test log deve mostrare **0.7.7-exp1+9** e lo stesso prefisso di commit indicato nel checkpoint.

È un'app separata, non un aggiornamento di `com.example.convoy_mesh`: la precedente resta installata con i suoi dati. La nuova ha permessi, identità BLE, nome e archivio propri; reimpostare i nomi Cama e Francesca. Terminare eventuali uscite nell'altra app e tenerne attiva una sola per telefono. Per tornare indietro, terminare l'uscita sperimentale e riaprire la precedente; non serve disinstallare.

La vecchia APK run #105 è scaduta (artifact `10300013706` non disponibile), quindi il suo certificato non è confrontabile. La CI verifica effettivamente firma/certificato della nuova APK e package, versionCode 9, minSDK compatibile con API29 e ABI arm64. La firma debug non è una politica di firma stabile: future ricompilazioni non sono automaticamente aggiornabili sopra questa candidata. Conservare **questo esatto APK**. Prima di qualunque futura disinstallazione esportare i log: la disinstallazione cancella i dati locali dell'app interessata.

## Protocollo Cama e Francesca — ogni registrazione sotto 4 minuti

Usare un tratto pedonale sicuro e ripetibile. Stessa APK su entrambi; annotare telefono, rete attiva/disattiva, posizione del telefono e orari dei cambi. I log restano privati: esportarli senza inserirli nel repository. `Segna qui un problema` serve per annotazioni brevi. Ripetere una sessione con la candidata precedente, se disponibile, alternando l'ordine; una prova sequenziale non garantisce identiche condizioni GNSS.

1. **Partenza già in cammino — 3 min.** Restare in Nearby senza preview, avviare Test log; cominciare a camminare a passo normale, poi avviare Uscita continuando. Camminare 90 s, fare una curva larga e continuare 45 s; fermarsi 20 s. Terminare Uscita e verificare che il log resti attivo; terminarlo/esportarlo esplicitamente entro 3 min. Annotare tempo al primo marker e freeze.
2. **Fermo/lento/curve — 3 min 30 s.** Avviare log e Uscita; 40 s fermi con telefono appoggiato, 20 s maneggiandolo senza spostarsi, 70 s a passo molto lento, 40 s con una curva e un'inversione ampia, 20 s fermi. Terminare Uscita, poi log. Questo può ancora esporre i limiti dichiarati: non ignorare tracce mancanti o deriva.
3. **Schermo spento e ritorno — 3 min 45 s.** Log e Uscita; 35 s camminando schermo acceso, 80 s spento continuando, 60 s separandosi quanto consentito dal luogo e poi ricongiungendosi, 30 s per osservare freschezza/ripresa. Terminare Uscita e poi il log. Se non si perde il contatto BLE, annotarlo: non chiamarlo test di recupero radio. Non simula perdita di processo o autonomia lunga.

Il limite automatico è quattro minuti: non unire le tre sessioni. Senza un riferimento indipendente non concludere che un marker più stabile sia più accurato. Annotare anomalie anche quando i due telefoni concordano.
