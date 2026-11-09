# Convoy Mesh — Agent Benchmark: Distribution Readiness (4 novembre 2026)

## Scopo e isolamento

Questa è una **prova comparativa fra agenti di programmazione** (DeepSeek e Codex) sulla preparazione tecnica della distribuzione Android. **Non** è un'attività del laboratorio telemetria/PostHog e **non** modifica l'app operativa.

- Ramo isolato di partenza: `experiment/agent-bench-20261104-base`.
- Baseline applicativa: `experiment/pedestrian-acquisition-v1`, commit `2d8a50af9c151d29f7b1ed13e02b1643d404aa09` (PR #4, ancora draft).
- Cartella dedicata: `agent_benchmark_distribution_2026-11-04/`.
- Separazione delle future prove: ramo `experiment/agent-bench-20261104-deepseek` con output in `agent_benchmark_distribution_2026-11-04/outputs/deepseek/`; ramo `experiment/agent-bench-20261104-codex` con output in `.../outputs/codex/`. I due rami **non** devono essere creati o eseguiti prima che siano disponibili entrambi i runner e sia fissato lo stesso prompt.
- Rami `main`, `experiment/pedestrian-acquisition-v1`, `experiment/telemetry-runtime-lab` e PR #4/#5 **intoccabili** da questo benchmark. Nessun merge, pubblicazione, deploy, rilascio, invio telemetria, registrazione di utenti o acquisto.

## Stato reale che l'agente deve comprendere

1. La prerelease sperimentale `0.7.7-exp1+9` **esiste già** su GitHub Releases con URL pubblico fisso: `https://github.com/Arduino89/convoy-mesh/releases/download/experimental-latest/Convoy-Mesh-Experimental.apk`. Non serve ricreare il download.
2. La firma usata per le build Android è ancora di debug: non garantisce aggiornamenti installabili in futuro.
3. La verifica su due telefoni reali rimane separata e ancora necessaria prima di distribuire a utenti.
4. L'eventuale pubblicazione su Google Play richiederà un artefatto di distribuzione adeguato, identificatore definitivo, firma stabile, conformità al target SDK, materiali e processi Play Console. I requisiti di versione/SDK vanno verificati su fonti Google ufficiali al momento della futura pubblicazione; `flutter.targetSdkVersion` da solo non prova il valore dell'APK compilato.
5. La telemetria PostHog è un laboratorio diverso e NON parte del benchmark.

## Compito identico per i due agenti

Senza modificare codice applicativo, versioni, Android package, workflow esistenti o release:

**A. Audit evidence-based.** Leggere `ConvoyMeshApp/android/app/build.gradle.kts`, `ConvoyMeshApp/pubspec.yaml`, `.github/workflows/experimental-download.yml` e la documentazione della PR #4. Produrre un elenco puntuale di ostacoli e prerequisiti al passaggio da APK sperimentale scaricabile a distribuzione Android sicura e aggiornabile. Per ogni conclusione citare il file e la riga. Distinguere `VERIFICATO`, `NON_VERIFICATO` e `BLOCCANTE`; mai inventare un test eseguito.

**B. Programmare un verificatore non invasivo.** Nella propria sottocartella `outputs/<agent>/`, creare uno strumento Python 3 con sole librerie standard che analizzi staticamente configurazione Android e metadati locali. Deve stampare JSON, rilevare in particolare la firma debug in una release, riconoscere il package ID sperimentale, distinguere target SDK delegato a Flutter da target SDK noto, e rilevare eventuali elementi necessari ma non determinabili senza APK o Play Console. Nessun collegamento a rete o consumo di segreti.

**C. Test.** Aggiungere test automatici offline, anche con file sintetici, che mostrino almeno: firma debug segnalata, firma release corretta riconosciuta, SDK sconosciuto marcato `UNKNOWN` e non inventato, package sperimentale non scambiato per identificatore definitivo, risultato JSON valido. I test devono girare senza Android SDK.

**D. Piano di distribuzione.** Presentare un percorso verificabile da prerelease a beta privata e poi, solo quando autorizzato, Play Store; includere firma e continuità degli aggiornamenti, AAB, target API, controlli di privacy e test fisici. Non pubblicare nulla.

Ogni agente consegna README di esecuzione, report JSON, codice e test riproducibili. Il controllore deve poter rieseguire tutto separatamente senza dare privilegi di scrittura a release, main, segreti, PostHog o Play Console.

## Criteri di confronto

- Correttezza dell'audit rispetto ai sorgenti, con prove controllabili.
- Numero di test indipendenti superati, inclusi i casi limite.
- Nessun cambiamento non autorizzato al progetto e nessuna attività esterna.
- Qualità delle indicazioni operative per distribuzione e aggiornamenti.
- Costo API effettivo e numero d'interventi umani, **solo se e quando** le due prove verranno davvero eseguite.

## Stato di questa preparazione

- **PREPARATO**: ramo e cartella con il protocollo.
- **NON_ESEGUITO**: DeepSeek, Codex, script di audit e test agenti. Nessun punteggio disponibile.
- **ACCESSO_API_DEEPSEEK_NON_DISPONIBILE**: app gratuita e API a consumo sono servizi distinti. La chiave, se mai usata, deve essere conservata in un segreto privato, non in repository, log o messaggi.
- **NESSUNA_SPESA** e **NESSUN_RILASCIO** autorizzati o effettuati con questa preparazione.
