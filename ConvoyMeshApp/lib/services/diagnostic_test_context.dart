/// Conditions reported by a human tester, never inferred from sensors.
/// No free-text fields are allowed in the cloud subset.
class DiagnosticTestContext {
  DiagnosticTestContext._();
  static const source = 'tester_declared';
  static const environments = <String, String>{
    'unknown': 'Non so', 'indoor': 'Al chiuso',
    'outdoor': 'All’aperto', 'mixed': 'Misto',
  };
  static const movements = <String, String>{
    'unknown': 'Non so', 'stationary': 'Fermo',
    'walking': 'In cammino', 'mixed': 'Movimento e soste',
  };
  static const peers = <String, String>{
    'unknown': 'Non so', 'stationary': 'Altri fermi',
    'walking': 'Altri in movimento', 'mixed': 'Situazione mista',
  };
  static const placements = <String, String>{
    'unknown': 'Non so', 'hand': 'In mano', 'pocket': 'In tasca',
    'backpack': 'Nello zaino', 'surface': 'Appoggiato',
  };
  static const screens = <String, String>{
    'unknown': 'Non so', 'on': 'Acceso',
    'off': 'Spento', 'mixed': 'Alternato',
  };
  static const outcomes = <String, String>{
    'not_checked': 'Non ho controllato',
    'no_obvious_issue': 'Nessun problema evidente',
    'observed_problem': 'Ho notato un problema',
  };
  static const markers = <String, String>{
    'movement_started': 'Inizio movimento',
    'movement_stopped': 'Fermo',
    'signal_lost': 'Segnale perso',
    'signal_recovered': 'Segnale ritrovato',
  };

  static Map<String, Object> context({
    required String environment, required String selfMovement,
    required String peersMovement, required String phonePlacement,
    required String screenReported,
  }) => {
    'source': source, 'environment': environment,
    'self_movement': selfMovement, 'peers_movement': peersMovement,
    'phone_placement': phonePlacement, 'screen_reported': screenReported,
  };

  static Map<String, Object> marker(String value) =>
      {'source': source, 'marker': value};

  static Map<String, Object> outcome(String value) =>
      {'source': source, 'outcome': value};

  static bool validate(String event, Map<dynamic, dynamic> data) {
    if (data['source'] != source || data.keys.any((key) => key is! String)) {
      return false;
    }
    if (event == 'context') {
      const keys = {'source', 'environment', 'self_movement',
          'peers_movement', 'phone_placement', 'screen_reported'};
      return data.length == keys.length && data.keys.toSet().containsAll(keys) &&
          environments.containsKey(data['environment']) &&
          movements.containsKey(data['self_movement']) &&
          peers.containsKey(data['peers_movement']) &&
          placements.containsKey(data['phone_placement']) &&
          screens.containsKey(data['screen_reported']);
    }
    if (event == 'marker') {
      return data.length == 2 && data.containsKey('marker') &&
          markers.containsKey(data['marker']);
    }
    if (event == 'outcome') {
      return data.length == 2 && data.containsKey('outcome') &&
          outcomes.containsKey(data['outcome']);
    }
    return false;
  }
}
