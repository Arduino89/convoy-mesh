# Changelog

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
