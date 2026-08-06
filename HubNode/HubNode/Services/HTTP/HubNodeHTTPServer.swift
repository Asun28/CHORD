import Foundation
import Network
import Darwin

// MARK: - Embedded local HTTP server
/// Serves Companion WebUI + /api/v1 from inside the HubNode process.
/// Default bind: 127.0.0.1. Optional LAN bind via NodeConfig.
/// No third-party dependency: Network.framework only.

final class HubNodeHTTPServer: @unchecked Sendable {
 private let queue = DispatchQueue(label: "nz.hubnode.http", qos: .userInitiated)
 private var listener: NWListener?
 private let api: HubNodeAPIService
 private let port: UInt16
 private let lanEnabled: Bool

 private(set) var isRunning = false
 private(set) var lastError: String?

 var baseURLString: String {
  let host = lanEnabled ? lanAddress() ?? "127.0.0.1" : "127.0.0.1"
  return "http://\(host):\(port)"
 }

 init(api: HubNodeAPIService, port: UInt16, lanEnabled: Bool) {
  self.api = api
  self.port = port
  self.lanEnabled = lanEnabled
 }

 func start() throws {
  stop()
  let params = NWParameters.tcp
  params.allowLocalEndpointReuse = true
  if !lanEnabled {
   // Prefer loopback when LAN is off
   params.requiredInterfaceType = .loopback
  }
  let nwPort = NWEndpoint.Port(rawValue: port)!
  let listener = try NWListener(using: params, on: nwPort)
  self.listener = listener

  listener.stateUpdateHandler = { [weak self] state in
   guard let self else { return }
   switch state {
   case .ready:
    self.isRunning = true
    self.lastError = nil
    print("HubNode HTTP: listening on \(self.baseURLString)")
   case .failed(let err):
    self.isRunning = false
    self.lastError = err.localizedDescription
    print("HubNode HTTP failed: \(err)")
   case .cancelled:
    self.isRunning = false
   default:
    break
   }
  }

  listener.newConnectionHandler = { [weak self] conn in
   self?.handle(connection: conn)
  }

  listener.start(queue: queue)
 }

 func stop() {
  listener?.cancel()
  listener = nil
  isRunning = false
 }

 // MARK: - Connection

 private func handle(connection: NWConnection) {
  connection.start(queue: queue)
  receive(on: connection, buffer: Data())
 }

 private func receive(on connection: NWConnection, buffer: Data) {
  connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
   guard let self else {
    connection.cancel()
    return
   }
   if let error {
    print("HubNode HTTP receive error: \(error)")
    connection.cancel()
    return
   }
   var buf = buffer
   if let data, !data.isEmpty {
    buf.append(data)
   }
   if let req = HTTPRequest.parse(buf) {
    Task {
     let response = await self.route(req)
     self.send(response, on: connection)
    }
    return
   }
   if isComplete {
    connection.cancel()
    return
   }
   // Need more data (headers not complete)
   if buf.count > 1_000_000 {
    self.send(HTTPResponse(status: 413, contentType: "text/plain", body: Data("Request too large".utf8)), on: connection)
    return
   }
   self.receive(on: connection, buffer: buf)
  }
 }

 private func send(_ response: HTTPResponse, on connection: NWConnection) {
  let data = response.serialize()
  connection.send(content: data, completion: .contentProcessed { _ in
   connection.cancel()
  })
 }

 // MARK: - Routing

 private func route(_ req: HTTPRequest) async -> HTTPResponse {
  let path = req.pathOnly
  let method = req.method.uppercased()

  do {
   switch (method, path) {
   case ("GET", "/health"), ("GET", "/api/v1/health"):
    return try await json { await MainActor.run { self.api.health() } }

   case ("GET", "/api/v1/bootstrap"):
    return try await json { await MainActor.run { self.api.bootstrap() } }

   case ("GET", "/api/v1/hub/status"):
    return try await json { try await MainActor.run { try self.api.status() } }

   case ("GET", "/api/v1/hub/situation"):
    return try await json { try await MainActor.run { try self.api.situation() } }

   case ("GET", "/api/v1/hub/roster"):
    return try await json { try await MainActor.run { try self.api.roster() } }

   case ("GET", "/api/v1/hub/tasks"):
    return try await json { try await MainActor.run { try self.api.tasks() } }

   case ("GET", "/api/v1/hub/my-shift"):
    let role = req.queryValue("role")
    return try await json {
     try await MainActor.run { try self.api.myShift(roleQuery: role) }
    }

   case ("GET", "/api/v1/hub/monitor"):
    return try await json { try await MainActor.run { try self.api.monitor() } }

   case ("GET", "/api/v1/hub/needs-offers"):
    let contacts = (req.queryValue("contacts") ?? "").lowercased()
    let include = contacts == "1" || contacts == "true" || contacts == "yes"
    return try await json {
     await MainActor.run { self.api.needsOffers(includeContacts: include) }
    }

   case ("GET", "/api/v1/hub/public-info"):
    return try await json { await MainActor.run { self.api.publicInfo() } }

   case ("GET", "/api/v1/hub/runbooks"):
    return try await json { await MainActor.run { self.api.runbooks() } }

   case ("GET", "/api/v1/hub/kea"):
    return try await json { await MainActor.run { self.api.keaAgent() } }

   case ("GET", "/api/v1/seed"):
    let data = try await MainActor.run { try self.api.seedRaw() }
    return HTTPResponse(status: 200, contentType: "application/json", body: data)

   case ("POST", "/api/v1/hub/ask"), ("POST", "/api/v1/hub/kea/ask"):
    // Same pathway as Mac Ask panel. Model config is NodeConfig (SwiftUI Settings) only.
    let body = req.body
    let value = try await self.api.ask(body: body)
    let data = try CompanionJSON.encode(value)
    return HTTPResponse(status: 200, contentType: "application/json", body: data)

   case ("OPTIONS", _):
    return HTTPResponse(status: 204, contentType: "text/plain", body: Data())

   case ("GET", "/"), ("GET", "/index.html"):
    return staticFile(named: "index", ext: "html", subdirectory: "WebUI")
     ?? HTTPResponse(status: 200, contentType: "text/html; charset=utf-8", body: Data(Self.fallbackIndexHTML.utf8))

   case ("GET", "/console"), ("GET", "/console.html"):
    if let resp = staticFile(named: "companion-console", ext: "html", subdirectory: "WebUI") {
     return injectBootstrap(into: resp)
    }
    return HTTPResponse(status: 404, contentType: "text/plain", body: Data("Companion console not bundled".utf8))

   case ("GET", "/demo-seed-data-v0.3.json"), ("GET", "/seed.json"):
    return staticFile(named: "demo-seed-data-v0.3", ext: "json", subdirectory: "WebUI")
     ?? HTTPResponse(status: 404, contentType: "text/plain", body: Data("Seed not found".utf8))

   default:
    // Static WebUI assets by name
    if method == "GET", path.hasPrefix("/"), !path.hasPrefix("/api/") {
     let name = String(path.dropFirst())
     if let url = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "WebUI")
      ?? Bundle.main.url(forResource: (name as NSString).deletingPathExtension,
               withExtension: (name as NSString).pathExtension,
               subdirectory: "WebUI"),
      let data = try? Data(contentsOf: url) {
      return HTTPResponse(status: 200, contentType: mime(for: name), body: data)
     }
    }
    return HTTPResponse(status: 404, contentType: "application/json", body: Data(#"{"error":"not found"}"#.utf8))
   }
  } catch let err as HubNodeAPIService.APIError {
   return errorJSON(status: err.statusCode, message: err.localizedDescription)
  } catch {
   return errorJSON(status: 500, message: error.localizedDescription)
  }
 }

 private func json<T: Encodable>(_ build: () async throws -> T) async throws -> HTTPResponse {
  let value = try await build()
  let data = try CompanionJSON.encode(value)
  return HTTPResponse(status: 200, contentType: "application/json", body: data)
 }

 private func errorJSON(status: Int, message: String) -> HTTPResponse {
  let payload = #"{"error":\#(jsonString(message))}"#
  return HTTPResponse(status: status, contentType: "application/json", body: Data(payload.utf8))
 }

 private func jsonString(_ s: String) -> String {
  let data = try? JSONSerialization.data(withJSONObject: s)
  return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
 }

 private func staticFile(named: String, ext: String, subdirectory: String) -> HTTPResponse? {
  let candidates: [URL?] = [
   Bundle.main.url(forResource: named, withExtension: ext, subdirectory: subdirectory),
   Bundle.main.url(forResource: named, withExtension: ext, subdirectory: "Resources/\(subdirectory)"),
   Bundle.main.url(forResource: named, withExtension: ext),
  ]
  for url in candidates {
   if let url, let data = try? Data(contentsOf: url) {
    return HTTPResponse(status: 200, contentType: mime(for: "\(named).\(ext)"), body: data)
   }
  }
  // Last resort: scan bundle for filename
  if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) {
   let want = "\(named).\(ext)"
   if let url = urls.first(where: { $0.lastPathComponent == want }),
    let data = try? Data(contentsOf: url) {
    return HTTPResponse(status: 200, contentType: mime(for: want), body: data)
   }
  }
  return nil
 }

 /// Inject HubNode Ask bridge into the Companion console.
 /// Kea answers must use AskService + NodeConfig (Mac Settings), never the
 /// offline CORPUS keyword table or the HTML model endpoint fields.
 private func injectBootstrap(into response: HTTPResponse) -> HTTPResponse {
  guard var html = String(data: response.body, encoding: .utf8) else { return response }
  let snippet = """
  <style id="hubnode-kea-host">
  /* Hide console-local model settings. Configure only in HubNode Settings. */
  button[aria-label="Model settings"],
  [data-screen-label="Settings"] details.kea-model,
  .kea-model-config { display: none !important; }
  /* Kea popup: readable markdown answers */
  .hubnode-md { word-break: break-word; overflow-wrap: anywhere; }
  .hubnode-md p { margin: 0 0 0.55em; }
  .hubnode-md p:last-child { margin-bottom: 0; }
  .hubnode-md strong { font-weight: 700; }
  .hubnode-md em { font-style: italic; }
  .hubnode-md h2, .hubnode-md h3 {
    margin: 0.55em 0 0.3em; font-size: 1.02em; font-weight: 800; line-height: 1.3;
  }
  .hubnode-md h2:first-child, .hubnode-md h3:first-child { margin-top: 0; }
  .hubnode-md .md-li {
    display: grid; grid-template-columns: 1.4em 1fr; gap: 0.25em 0.35em;
    margin: 0.2em 0; align-items: start;
  }
  .hubnode-md .md-li .n { font-weight: 700; text-align: right; font-variant-numeric: tabular-nums; }
  .hubnode-md code {
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 0.92em; background: rgba(0,0,0,0.06); padding: 0.05em 0.3em; border-radius: 3px;
  }
  .hubnode-md ul, .hubnode-md ol { margin: 0.35em 0 0.55em 1.1em; padding: 0; }
  .hubnode-md li { margin: 0.2em 0; }
  </style>
  <script>
  window.HUBNODE = window.HUBNODE || {};
  window.HUBNODE.apiBase = '/api/v1';
  window.HUBNODE.mode = 'hosted';
  window.HUBNODE.liveBoard = '/';
  window.HUBNODE.escapeHtml = function(s) {
    return String(s ?? '').replace(/[&<>"']/g, function(c) {
      return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]);
    });
  };
  /** Lightweight markdown for Kea chat bubbles (bold, lists, headings, breaks). */
  window.HUBNODE.renderMarkdown = function(src) {
    var raw = String(src ?? '').replace(/\\r\\n/g, '\\n');
    var lines = raw.split('\\n');
    var out = [];
    var i, line, m, buf = [];
    function flushPara() {
      if (!buf.length) return;
      out.push('<p>' + buf.join('<br>') + '</p>');
      buf = [];
    }
    for (i = 0; i < lines.length; i++) {
      line = lines[i];
      if (/^\\s*$/.test(line)) { flushPara(); continue; }
      m = /^(#{1,3})\\s+(.*)$/.exec(line);
      if (m) {
        flushPara();
        var tag = m[1].length === 1 ? 'h2' : 'h3';
        out.push('<' + tag + '>' + window.HUBNODE.inlineMd(m[2]) + '</' + tag + '>');
        continue;
      }
      m = /^(\\d+)[\\.)]\\s+(.*)$/.exec(line);
      if (m) {
        flushPara();
        out.push('<div class="md-li"><span class="n">' + window.HUBNODE.escapeHtml(m[1]) + '.</span><span>' + window.HUBNODE.inlineMd(m[2]) + '</span></div>');
        continue;
      }
      m = /^[-*•]\\s+(.*)$/.exec(line);
      if (m) {
        flushPara();
        out.push('<div class="md-li"><span class="n">•</span><span>' + window.HUBNODE.inlineMd(m[1]) + '</span></div>');
        continue;
      }
      buf.push(window.HUBNODE.inlineMd(line));
    }
    flushPara();
    return out.join('') || '<p></p>';
  };
  window.HUBNODE.inlineMd = function(s) {
    var t = window.HUBNODE.escapeHtml(s);
    t = t.replace(/`([^`]+)`/g, '<code>$1</code>');
    t = t.replace(/\\*\\*([^*]+)\\*\\*/g, '<strong>$1</strong>');
    t = t.replace(/__([^_]+)__/g, '<strong>$1</strong>');
    t = t.replace(/(^|[^*])\\*([^*]+)\\*(?!\\*)/g, '$1<em>$2</em>');
    return t;
  };
  window.HUBNODE.hydrateMarkdown = function(root) {
    var scope = root || document;
    var nodes = scope.querySelectorAll('.hubnode-md');
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      // Framework often re-paints bubbles as a single text node with raw markdown.
      var onlyText = el.childNodes.length === 1 && el.childNodes[0].nodeType === 3;
      var empty = el.childNodes.length === 0;
      var raw;
      if (onlyText || empty || el.getAttribute('data-md-done') !== '1') {
        raw = onlyText || empty ? (el.textContent || '') : (el.getAttribute('data-md-source') || el.textContent || '');
        if (!raw) continue;
        if (el.getAttribute('data-md-done') === '1' && el.getAttribute('data-md-source') === raw && !onlyText) continue;
      } else {
        continue;
      }
      el.setAttribute('data-md-source', raw);
      el.innerHTML = window.HUBNODE.renderMarkdown(raw);
      el.setAttribute('data-md-done', '1');
    }
  };
  /** Single Kea entrypoint: HubNode AskService (same as Mac Ask panel). */
  window.HUBNODE.ask = async function(q) {
    const question = String(q || '').trim();
    if (!question) throw new Error('Empty question');
    const r = await fetch('/api/v1/hub/ask', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ q: question })
    });
    let data = null;
    try { data = await r.json(); } catch (_) { data = null; }
    if (!r.ok) {
      const msg = (data && data.error) ? data.error : (r.statusText || 'Ask failed');
      throw new Error(msg);
    }
    // Allow UI to re-hydrate after framework paints the bubble
    setTimeout(function() { window.HUBNODE.hydrateMarkdown(); }, 30);
    setTimeout(function() { window.HUBNODE.hydrateMarkdown(); }, 120);
    setTimeout(function() { window.HUBNODE.hydrateMarkdown(); }, 400);
    return data;
  };
  // Keep markdown hydrated when the console re-renders bubbles as text
  if (!window.__hubnodeMdObs) {
    window.__hubnodeMdObs = new MutationObserver(function() {
      window.HUBNODE.hydrateMarkdown();
    });
    document.addEventListener('DOMContentLoaded', function() {
      window.__hubnodeMdObs.observe(document.documentElement, { childList: true, subtree: true, characterData: true });
      window.HUBNODE.hydrateMarkdown();
    });
    // Bundler may replace body after DOMContentLoaded
    setTimeout(function() {
      try {
        window.__hubnodeMdObs.observe(document.documentElement, { childList: true, subtree: true, characterData: true });
        window.HUBNODE.hydrateMarkdown();
      } catch (e) {}
    }, 500);
  }
  console.info('[HubNode] Kea uses HubNode AskService. Model endpoint is set only in the Mac app Settings.');
  </script>
  """
  if let range = html.range(of: "<head>", options: .caseInsensitive) {
   html.replaceSubrange(range, with: "<head>\n" + snippet)
  } else {
   html = snippet + html
  }
  return HTTPResponse(status: 200, contentType: "text/html; charset=utf-8", body: Data(html.utf8))
 }

 private func mime(for name: String) -> String {
  let lower = name.lowercased()
  if lower.hasSuffix(".html") || lower.hasSuffix(".htm") { return "text/html; charset=utf-8" }
  if lower.hasSuffix(".json") { return "application/json" }
  if lower.hasSuffix(".js") { return "application/javascript" }
  if lower.hasSuffix(".css") { return "text/css" }
  if lower.hasSuffix(".svg") { return "image/svg+xml" }
  if lower.hasSuffix(".png") { return "image/png" }
  if lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { return "image/jpeg" }
  return "application/octet-stream"
 }

 private func lanAddress() -> String? {
  var address: String?
  var ifaddr: UnsafeMutablePointer<ifaddrs>?
  guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
  defer { freeifaddrs(ifaddr) }
  for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
   let iface = ptr.pointee
   let family = iface.ifa_addr.pointee.sa_family
   guard family == UInt8(AF_INET) else { continue }
   let name = String(cString: iface.ifa_name)
   guard name.hasPrefix("en") || name.hasPrefix("bridge") || name == "wlan0" else { continue }
   var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
   getnameinfo(
    iface.ifa_addr,
    socklen_t(iface.ifa_addr.pointee.sa_len),
    &hostname,
    socklen_t(hostname.count),
    nil,
    0,
    NI_NUMERICHOST
   )
   let ip = String(cString: hostname)
   if ip.hasPrefix("127.") { continue }
   address = ip
   break
  }
  return address
 }

 private static let fallbackIndexHTML = """
 <!DOCTYPE html>
 <html lang="en"><head><meta charset="utf-8"><title>HubNode board</title>
 <style>body{font-family:system-ui;background:#faf9f5;padding:2rem}a{color:#0078A8}</style>
 </head><body>
 <h1>HubNode</h1>
 <p>Live board asset missing from bundle. API is still available.</p>
 <ul>
 <li><a href="/health">/health</a></li>
 <li><a href="/api/v1/hub/status">/api/v1/hub/status</a></li>
 <li><a href="/console">/console</a> (Companion demo)</li>
 </ul>
 </body></html>
 """
}

// MARK: - Minimal HTTP parse / respond

private struct HTTPRequest {
 var method: String
 var path: String
 var headers: [String: String]
 var body: Data

 var pathOnly: String {
  if let q = path.firstIndex(of: "?") {
   return String(path[..<q])
  }
  return path
 }

 var query: [String: String] {
  guard let q = path.firstIndex(of: "?") else { return [:] }
  let qs = path[path.index(after: q)...]
  var out: [String: String] = [:]
  for pair in qs.split(separator: "&") {
   let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
   guard let k = parts.first, !k.isEmpty else { continue }
   let v = parts.count > 1 ? parts[1] : ""
   out[k.removingPercentEncoding ?? k] = v.removingPercentEncoding ?? v
  }
  return out
 }

 func queryValue(_ key: String) -> String? {
  query[key]
 }

 static func parse(_ data: Data) -> HTTPRequest? {
  guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
  let headerData = data.subdata(in: data.startIndex..<headerEnd.lowerBound)
  guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
  let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
  guard let requestLine = lines.first else { return nil }
  let parts = requestLine.split(separator: " ")
  guard parts.count >= 2 else { return nil }
  let method = String(parts[0])
  let path = String(parts[1])
  var headers: [String: String] = [:]
  for line in lines.dropFirst() {
   guard let colon = line.firstIndex(of: ":") else { continue }
   let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
   let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
   headers[key] = value
  }
  let bodyStart = headerEnd.upperBound
  let contentLength = Int(headers["content-length"] ?? "0") ?? 0
  let available = data.count - bodyStart
  if contentLength > available {
   return nil // wait for rest of body
  }
  let body: Data
  if contentLength > 0 {
   body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
  } else {
   body = Data()
  }
  return HTTPRequest(method: method, path: path, headers: headers, body: body)
 }
}

private struct HTTPResponse {
 var status: Int
 var contentType: String
 var body: Data
 var extraHeaders: [String: String] = [:]

 func serialize() -> Data {
  let reason: String
  switch status {
  case 200: reason = "OK"
  case 400: reason = "Bad Request"
  case 404: reason = "Not Found"
  case 405: reason = "Method Not Allowed"
  case 409: reason = "Conflict"
  case 413: reason = "Payload Too Large"
  case 500: reason = "Internal Server Error"
  case 503: reason = "Service Unavailable"
  default: reason = "OK"
  }
  var header = "HTTP/1.1 \(status) \(reason)\r\n"
  header += "Content-Type: \(contentType)\r\n"
  header += "Content-Length: \(body.count)\r\n"
  header += "Connection: close\r\n"
  header += "Access-Control-Allow-Origin: *\r\n"
  header += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
  header += "Access-Control-Allow-Headers: Content-Type\r\n"
  header += "Cache-Control: no-store\r\n"
  for (k, v) in extraHeaders {
   header += "\(k): \(v)\r\n"
  }
  header += "\r\n"
  var data = Data(header.utf8)
  data.append(body)
  return data
 }
}
