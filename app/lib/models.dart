class Host {
  String id;
  String label;
  String host;
  int port;
  String username;
  String auth; // 'password' | 'key'
  int color;
  String startup; // command sent right after the shell opens
  int lastUsed;
  String via; // id of a jump host ('' = connect directly)

  Host({
    required this.id,
    required this.label,
    required this.host,
    this.port = 22,
    required this.username,
    this.auth = 'password',
    this.color = 0,
    this.startup = '',
    this.lastUsed = 0,
    this.via = '',
  });

  String get address => '$username@$host${port == 22 ? '' : ':$port'}';
  String get hostKeyId => '$host:$port';

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'host': host,
        'port': port,
        'username': username,
        'auth': auth,
        'color': color,
        'startup': startup,
        'lastUsed': lastUsed,
        if (via.isNotEmpty) 'via': via,
      };

  factory Host.fromJson(Map<String, dynamic> j) => Host(
        id: j['id'],
        label: j['label'] ?? '',
        host: j['host'],
        port: j['port'] ?? 22,
        username: j['username'] ?? 'root',
        auth: j['auth'] ?? 'password',
        color: j['color'] ?? 0,
        startup: j['startup'] ?? '',
        lastUsed: j['lastUsed'] ?? 0,
        via: j['via'] ?? '',
      );

  /// Parses "user@host:port" (user and port optional).
  static Host? parse(String input, String id) {
    final s = input.trim();
    if (s.isEmpty) return null;
    var user = 'root';
    var rest = s;
    final at = s.lastIndexOf('@');
    if (at > 0) {
      user = s.substring(0, at);
      rest = s.substring(at + 1);
    }
    var port = 22;
    final colon = rest.lastIndexOf(':');
    if (colon > 0 && !rest.contains(']')) {
      final p = int.tryParse(rest.substring(colon + 1));
      if (p != null) {
        port = p;
        rest = rest.substring(0, colon);
      }
    }
    if (rest.isEmpty) return null;
    return Host(id: id, label: rest, host: rest, port: port, username: user);
  }
}

class Snippet {
  String id;
  String name;
  String command;
  bool autoRun;

  Snippet({required this.id, required this.name, required this.command, this.autoRun = true});

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'command': command, 'autoRun': autoRun};

  factory Snippet.fromJson(Map<String, dynamic> j) => Snippet(
        id: j['id'],
        name: j['name'],
        command: j['command'],
        autoRun: j['autoRun'] ?? true,
      );
}

class Forward {
  String id;
  String label;
  String hostId;
  int localPort;
  String remoteHost;
  int remotePort;

  Forward({
    required this.id,
    required this.label,
    required this.hostId,
    required this.localPort,
    this.remoteHost = '127.0.0.1',
    required this.remotePort,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'hostId': hostId,
        'localPort': localPort,
        'remoteHost': remoteHost,
        'remotePort': remotePort,
      };

  factory Forward.fromJson(Map<String, dynamic> j) => Forward(
        id: j['id'],
        label: j['label'] ?? '',
        hostId: j['hostId'],
        localPort: j['localPort'],
        remoteHost: j['remoteHost'] ?? '127.0.0.1',
        remotePort: j['remotePort'],
      );
}
