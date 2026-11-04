# Harness — preparazione del 4 novembre 2026

**HOLD_ENVIRONMENT: preparazione verificata in parte, agente non operativo.**
Il [protocollo originale](README.md) è immutato. Nessun incarico A–D eseguito,
nessun risultato competitivo, chiamata API pagante o spesa.

| Area | Stato | Evidenza / limite |
|---|---|---|
| GitHub | VERDE per Jarvis | Clone e letture riusciti; ramo base riusato e consegna in draft PR. Nessuna credenziale GitHub trasferita a Harness. |
| Harness | GIALLO | Installazione, avvio headless, patch e chiamata MCP locale provati; shell confinata bloccata. |
| API DeepSeek | GIALLO | Configurazione pronta, rifiuto senza chiave provato. Autenticazione, rete al provider e inferenza non provate. |
| Confronto | GIALLO | Entrambi NOT_RUN; rami concorrenti non creati, nessun punteggio. |

## Isolamento e prove

Ramo `experiment/agent-bench-20261104-base`, HEAD iniziale
`dee2039a653ca20f46d93dd8a9f577a9d051eb58`; baseline app
`2d8a50af9c151d29f7b1ed13e02b1643d404aa09`. Il diff iniziale aggiungeva solo
il README benchmark. Protocollo: blob `dcebbd10a0623225b6a3f469015442159e9dbd9a`,
SHA-256 `ca2876092636aee65ae23d3ed4e5e05f2f225258d8a96e1e93d2d9ec8d65c108`.
Pin e rami protetti sono in [preparation/isolation.json](preparation/isolation.json).

PR #4/#5 lette, mai modificate. Cambi proposti soltanto in questa cartella e
nel puntatore `CONTINUITY.md` di questo ramo. App, versioni, package, workflow,
release, APK, PostHog e servizi utenti invariati. I due workflow esistenti
filtrano rami e percorsi: questi cambi documentali non attivano build/publisher.
Nessun job lanciato e nessun esito CI rivendicato.

Creata una snapshot locale degli 85 file tracciati di `dee2039…`, senza `.git`,
remote o credenziali. Non commessa una copia del codice. È una directory
separata, **non un mount immutabile**: il confinamento OS rimane da risolvere.

[preparation/evidence.json](preparation/evidence.json) conserva timestamp, hash
degli script, exit code e risultati di cinque verifiche: versione, help,
composizione patch, rifiuto senza chiave, servizi locali. Il successo del probe
diagnostico non significa successo del benchmark.

La prova MCP carica i servizi Harness reali `dsh-mcp-client` e `dsh-tools`,
negozia stdio con una fixture Python e chiama
`mcp__preparation__read_sentinel`, ottenendo `CONVOY_PREPARATION_MCP_OK`.
Nessun modello invocato: prova il collegamento strumento, non l'abilità di
DeepSeek o l'autenticazione GitHub MCP.

Il provider sandbox reale trova bubblewrap inutilizzabile (namespace negato,
`Operation not permitted`) e Landlock `unusable`; restituisce
`SANDBOX_UNAVAILABLE`, senza eseguire `true` fuori sandbox. Nessun ripiego su
`danger-full-access`. Docker assente. `/etc/codex/network-policy.json` e la
capability `environment_status` non sono disponibili: nessuna readiness di
rete/credenziali viene dedotta. Clone Git e download npm sono invece eseguiti.

## Runtime riproducibile senza chiavi

Installato `@deepseek-ai/dsh@0.2.1-rc.5`, tag ufficiale `dsh-v0.2.1-rc.5`,
sorgente `b830ec950faba0a46dda564be3e2d854afed94f1`. Master, già
`0.2.2-alpha.3`, è stato distinto dal pacchetto npm: help e configurazione
verificati appartengono alla release fissata. Requisito Node del tag:
`^22.19.0 || >=24.0.0`; eseguito con Node **24.22.1**, npm **11.9.0**,
Python **3.12.14**, Linux x64. Installati 618 pacchetti con script disabilitati;
bootstrap effettivo riuscito usando i componenti precompilati. Lock e integrity
conservati, nessuna dichiarazione di audit delle dipendenze. Harness è in anteprima.

Dalla root del checkout, con una directory vuota esterna al repository:

```bash
mkdir -p /tmp/convoy-dsh-runtime
cp agent_benchmark_distribution_2026-11-04/preparation/runtime/package*.json /tmp/convoy-dsh-runtime/
npm ci --prefix /tmp/convoy-dsh-runtime --ignore-scripts --no-audit --no-fund
python3 agent_benchmark_distribution_2026-11-04/preparation/probe.py \
  --runtime /tmp/convoy-dsh-runtime \
  --evidence /tmp/convoy-dsh-preparation-evidence.json
```

Il probe usa stato temporaneo e ambiente ridotto, senza segreti ambientali o
profili personali. Una chiave DeepSeek esplicitamente vuota impedisce fallback
`.env`. Il controllo senza chiave deve terminare con **1 / MISSING_CREDENTIAL**.
La patch spegne telemetria Harness, invio session log/inventario plugin, titoli
LLM, strumenti web, subagenti e strumenti di scrittura. Il preset `read-only`
con `approval: never` rifiuta escalation. `maxTokens: 8192` limita una risposta,
**non la spesa totale**. I probe non avviano il compito comparativo.
Il runtime Work è temporaneo: su nuova istanza reinstallare dal lock e riprovare.

## Collegamento GitHub minimo e credenziali

Prima scelta sufficiente: il controller Jarvis fornisce una snapshot dell'esatto
commit e le informazioni della PR #4 richieste dal protocollo. Harness non riceve
il collegamento GitHub di Jarvis, `.git`, PostHog, chiavi Android o privilegi di
pubblicazione. **Nessun token GitHub serve per analizzare questa copia locale.**

Per letture live future Harness supporta MCP stdio e Streamable HTTP. Riutilizzare
il server ufficiale `github/github-mcp-server`, con soli tool read-only e token
fine-grained per il solo `Arduino89/convoy-mesh`: Contents e Pull requests read,
Metadata implicito; Actions read solo se necessario. Niente write, secrets,
administration o workflows. Il server locale offre `--read-only`; quello remoto
endpoint come `https://api.githubcopilot.com/mcp/x/repos/readonly`. Il toolset PR
è distinto. Scope della credenziale e selezione tool sono controlli separati.
**Questa connessione live non è configurata né collaudata.** Nessun webhook,
tunnel, scheduler o nuovo server è necessario; i plugin ChatGPT non sono
automaticamente strumenti DeepSeek.

Solo dopo il gate ambiente: usare il gestore segreti del runner per
`DEEPSEEK_API_KEY`, senza chiave nel comando/history, chat, repo, log o commenti.
Per un test locale un input nascosto può alimentare il solo processo; rimuovere
la variabile dopo l'uso. Nella GUI ufficiale Settings → Models conserva la chiave
in `$DSH_HOME/.credentials.yaml` esterno al repo; il profilo headless fissato
ignora quel deposito per default e richiede secret di processo o abilitazione
esplicita del deposito. Nessuna chiave configurata/validata qui; nessuna chiamata
di saldo, lista modelli o inferenza al provider.

## Costi e tetto proposto

[Listino ufficiale](https://api-docs.deepseek.com/quick_start/pricing/), consultato
il 4 novembre 2026. USD per milione di token:

| Modello | Input cache hit off/peak | Input cache miss off/peak | Output off/peak |
|---|---:|---:|---:|
| `deepseek-flash` | 0,003 / 0,006 | 0,15 / 0,30 | 0,60 / 1,20 |
| `deepseek-v4-pro` | 0,022 / 0,044 | 0,66 / 1,32 | 1,98 / 3,96 |

Peak lun–ven 01–04 e 06–10 UTC, escluse festività cinesi: usare il prezzo peak
per una previsione prudente. Search e Fetch: ciascuno 0,75 USD/1.000 richieste
riuscite, qui disabilitati. Cronologia reinviata e ragionamento contano nel consumo.

Proposta **2 USD complessivi per la prima prova**, ancora da autorizzare.
Esempio prudente: 1M input senza cache + 100k output in fascia peak = 0,42 USD
Flash o 1,716 USD Pro, esclusi altri servizi. Prima un piccolo controllo di
collegamento Flash; modello/ragionamento della prova valutata fissati prima
di avviare entrambi i concorrenti.

**Tetto economico non ancora applicato né verificato.** Prima dell'uso reale
serve prenotare il costo massimo di ciascuna richiesta prima dell'inoltro,
includendo retry e chiamate ausiliarie, con arresto al limite e ricevuta usage.
Un allarme o `maxTokens` non sostituisce un limite globale. Nessun launcher
pagante consegnato. Spesa API effettiva di preparazione **0 USD**.

## Collaborazione e prossimo gate

1. Conservare il ramo preparazione; risolvere isolamento e tetto economico.
   Predisporre anche il runner Codex: Work/Codex disponibile in questa sessione
   non dimostra una prova comparativa separata già configurata.
2. Fissare commit comune, hash del prompt identico, versioni runner/modelli e
   stesse fonti/tool. Protocollo A–D invariato; nessun risultato dell'altro agente.
3. Soltanto allora creare i rami `…-deepseek` e `…-codex` del README. Copie dello
   stesso input, soltanto il proprio `outputs/<agent>/` scrivibile, niente token.
4. Il controller verifica diff e segreti, riesegue separatamente i test offline,
   conserva comandi/exit code/hash e importa i risultati in due draft PR.
   Nei commenti: agente/modello, source/prompt/output SHA, test, usage, costo,
   interventi umani. Nessuna correzione silenziosa dell'output valutato.
5. Review indipendente e punteggio successivi; nessun merge, release o autoapprovazione.

**Prossimo gate unico: runner usa e getta con sandbox funzionante**, verificando
comando consentito e tentativo di scrittura esterna negato. Alternativa sicura:
VM Linux dedicata o container non privilegiato su host che consenta il backend;
nessuna VM/spesa/servizio attivata. Dopo il gate restano secret privato, consenso
al budget e entrambi i runner con prompt comune. La chiave da sola non sblocca
questo Work. Non avviare agenti o build Android per aggirare il limite.

## Contesto consultato e decisione di riuso

Governance corrente Cama-Enterprise su main, HEAD osservato
`73cf1fb07bb7c1ca5b972638b6b873b04dd6a847`: AGENTS, Source of Truth Index,
Principles, Operating Model, Continuity Protocol, Pattern Registry, routing memory,
Quick Index e note pertinenti. Preflight diretto: nessun checkout eseguibile
Enterprise, nessuna ricevuta resolver/execution-engine contract rivendicata.

Primo livello sufficiente: **2** per ramo/protocollo/stato; **4–5** per npm
ufficiale, patch, Git/GitHub/MCP; **6** per piccoli probe indispensabili senza
modello. Nessun nuovo orchestratore, agente, servizio o registro aziendale.
Fonti: script/patch/lock; prove derivate: evidence/isolation JSON; writer unico:
Jarvis sul ramo benchmark. Pattern pertinenti: EP-001/002/003/004/005/006/007/009/010;
sentinelle già fornite da Cama: zero spesa, repo protetti e protocollo immutato.
EP-008: nessuna promozione globale. Riutilizzate note JON-2026-08-25-006/010/011/014
e JON-2026-09-08-001. La sandbox indisponibile è un limite locale documentato,
non una lezione generale dedotta da questo caso; nessuna governance modificata.

## Fonti ufficiali

- [Harness e avvio](https://github.com/deepseek-ai/deepseek-harness)
- [Release sorgente esatta](https://github.com/deepseek-ai/deepseek-harness/tree/b830ec950faba0a46dda564be3e2d854afed94f1)
- [Sicurezza](https://github.com/deepseek-ai/deepseek-harness/blob/b830ec950faba0a46dda564be3e2d854afed94f1/SAFETY.md)
- [Headless](https://github.com/deepseek-ai/deepseek-harness/blob/b830ec950faba0a46dda564be3e2d854afed94f1/packages/bundle/headless/README.md)
- [API key](https://github.com/deepseek-ai/deepseek-harness/blob/b830ec950faba0a46dda564be3e2d854afed94f1/packages/llm/llm-deepseek-api-key/README.md)
- [Trasporto API](https://github.com/deepseek-ai/deepseek-harness/blob/b830ec950faba0a46dda564be3e2d854afed94f1/packages/llm/llm-deepseek/README.md)
- [MCP](https://github.com/deepseek-ai/deepseek-harness/blob/b830ec950faba0a46dda564be3e2d854afed94f1/packages/mcp/mcp-client/README.md)
- [Sandbox](https://github.com/deepseek-ai/deepseek-harness/blob/b830ec950faba0a46dda564be3e2d854afed94f1/packages/sandbox/sandbox-local/README.md)
- [GitHub MCP](https://github.com/github/github-mcp-server) e [remoto](https://github.com/github/github-mcp-server/blob/main/docs/remote-server.md)
- [Prezzi DeepSeek](https://api-docs.deepseek.com/quick_start/pricing/)
