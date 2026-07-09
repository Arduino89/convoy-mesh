# Changelog

## v0.5-gps-quality

- Aggiunto filtro GPS pedonale dedicato a gruppi a piedi/outdoor, senza logiche veicolari.
- Introdotto quality score GPS, barre qualità e motivo dell'ultimo fix accettato/scartato.
- Migliorato anti-jitter da fermo: il marker resta ancorato se i sensori indicano assenza di movimento reale.
- Aggiunto scarto di salti GPS implausibili per camminata quando l'accuracy è debole.
- Evitata la creazione di tracce false: il trail cresce solo con movimento reale, accuracy sufficiente e passo significativo.
- Aggiunti test automatici per fix iniziale, jitter da fermo, camminata reale, micro-movimenti, salti GPS e accuracy pessima.

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
