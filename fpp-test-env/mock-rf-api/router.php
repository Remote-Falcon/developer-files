<?php
// Mock Remote Falcon plugins API for the virtual-FPP test harness.
// Invoked by `php -S` from spin-up.sh.
//
// Routes are configured by writing JSON to the file at $RF_MOCK_CONFIG.
// Every incoming request is appended to $RF_MOCK_RECORDINGS so smoke
// scripts can assert on what the plugin called.
//
// This is intentionally a sibling to remote-falcon-plugin's
// tests/integration/router.php — same shape, same env-var contract,
// reused so contributors only have to learn the pattern once.

$configPath = getenv('RF_MOCK_CONFIG') ?: '/tmp/rf-mock.config.json';
$recordingsPath = getenv('RF_MOCK_RECORDINGS') ?: '/tmp/rf-mock.recordings.json';

$config = [];
if (is_file($configPath)) {
    $raw = file_get_contents($configPath);
    if ($raw !== false) {
        $decoded = json_decode($raw, true);
        if (is_array($decoded)) {
            $config = $decoded;
        }
    }
}

$method = $_SERVER['REQUEST_METHOD'];
$rawPath = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$path = rawurldecode($rawPath);
$query = $_SERVER['QUERY_STRING'] ?? '';

$headers = [];
foreach ($_SERVER as $k => $v) {
    if (strpos($k, 'HTTP_') === 0) {
        $name = strtolower(str_replace('_', '-', substr($k, 5)));
        $headers[$name] = $v;
    }
}

$requestBody = file_get_contents('php://input');

$recordings = [];
if (is_file($recordingsPath)) {
    $raw = file_get_contents($recordingsPath);
    if ($raw !== false) {
        $decoded = json_decode($raw, true);
        if (is_array($decoded)) {
            $recordings = $decoded;
        }
    }
}
$recordings[] = [
    'method' => $method,
    'path' => $path,
    'query' => $query,
    'headers' => $headers,
    'body' => $requestBody,
    'timestamp' => microtime(true),
];
file_put_contents($recordingsPath, json_encode($recordings));

// Default routes for endpoints commonly hit during a smoke. Tests can
// override these via setRoute in the config file.
$defaults = [
    '/q/health' => ['body' => ['status' => 'UP']],
    '/remotePreferences' => ['body' => ['viewerControlMode' => 'jukebox']],
    '/highestVotedPlaylist' => ['body' => ['winningPlaylist' => null, 'playlistIndex' => null]],
    '/nextPlaylistInQueue' => ['body' => ['nextPlaylist' => null, 'playlistIndex' => null]],
    '/updateWhatsPlaying' => ['body' => ['ok' => true]],
    '/updateNextScheduledSequence' => ['body' => ['ok' => true]],
    '/fppHeartbeat' => ['body' => ['ok' => true]],
    '/pluginVersion' => ['body' => ['ok' => true]],
    '/syncPlaylists' => ['body' => ['ok' => true]],
    '/purgeQueue' => ['body' => ['ok' => true]],
    '/updateViewerControl' => ['body' => ['ok' => true]],
    '/updateManagedPsa' => ['body' => ['ok' => true]],
];

$route = null;
if (isset($config[$path])) {
    $route = $config[$path];
} else {
    foreach ($config as $pattern => $cfg) {
        if (substr($pattern, -1) === '*') {
            $prefix = substr($pattern, 0, -1);
            if (strpos($path, $prefix) === 0) {
                $route = $cfg;
                break;
            }
        }
    }
}
if ($route === null && isset($defaults[$path])) {
    $route = $defaults[$path];
}

if ($route === null) {
    http_response_code(404);
    header('Content-Type: application/json');
    echo json_encode(['error' => 'no route configured', 'path' => $path]);
    return;
}

$delayMs = $route['delayMs'] ?? 0;
if ($delayMs > 0) {
    usleep((int) ($delayMs * 1000));
}

http_response_code($route['status'] ?? 200);
header('Content-Type: ' . ($route['contentType'] ?? 'application/json'));

$body = $route['body'] ?? '';
if (is_array($body) || is_object($body)) {
    echo json_encode($body);
} else {
    echo $body;
}
