# Changelog

## v0.5-gps-quality

- Aggiunto filtro GPS pedonale dedicato a gruppi a piedi/outdoor, senza logiche veicolari.
- Introdotto quality score GPS, barre qualità e motivo dell'ultimo fix accettato/scartato.
- Migliorato anti-jitter da fermo: quando il motion sensor è affidabile e indica stato fermo, il marker resta ancorato all'ultima posizione accettata anche davanti a singoli outlier GPS con accuracy dichiarata buona.
- Separato l'ultimo fix realmente accettato dagli eventi GPS scartati/ancorati, evitando falsi calcoli di velocità.
- Aggiunto fallback GPS-only quando l'accelerometro non è disponibile o non è ancora affidabile.
- Aggiunto scarto dei teletrasporti GPS anche quando il telefono dichiara un'accuracy apparentemente buona.
- Allineato anche il filtro posizione dei peer allo scenario pedonale, con margine per l'incertezza GPS outdoor.
- Evitata la creazione di tracce false: il trail cresce solo con movimento coerente, accuracy sufficiente e passo significativo.
- Aggiunti test automatici per fix iniziale, jitter da fermo, camminata reale, micro-movimenti, salti GPS, fallback sensori, accuracy pessima e outlier da fermo con accuracy apparentemente buona.
- Rafforzata la CI con cache, artifact diagnostici e smoke test su emulatore Android con KVM.

## v0.4-stability

- Fix intent Android per aprire le impostazioni Posizione/GPS dall'app.
- Separato il concetto di peer "sentito" da peer "valido/online" per ridurre ghost peer.
- Online/offline e pulizia peer basati sull'ultimo pacchetto valido accettato.
- Aggiunto filtro anti-salto per fix peer palesemente implausibili con accuracy scarsa.
- Marker mappa dei peer con fix vecchio mostrati in modo attenuato invece che identici ai fix freschi.
- Generazione ID locale resa più robusta con `Random.secure()` quando disponibile.

## v0.3

- Stabilizzazione BLE dopo test su due telefoni.
- Advertising basato su manufacturer data.
- Scan senza filtro service UUID, parsing via magic `CM`.
- Supporto magic a offset 0 o 2 nel manufacturer data.
- Pacchetti POS e NAME separati.
- Debug BLE più leggibile.
- Protezione cambio ID con pressione lunga.
- Prime rifiniture UX GPS/peer.
