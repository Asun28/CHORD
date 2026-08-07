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

   case ("GET", "/hubnode-bridge.js"):
    return staticFile(named: "hubnode-bridge", ext: "js", subdirectory: "WebUI")
     ?? HTTPResponse(status: 404, contentType: "text/plain", body: Data("bridge missing".utf8))

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

 /// Inject HubNode Ask bridge + markdown styles into the Companion console.
 /// Logic lives in `hubnode-bridge.js` (no Swift string-escaping of regex).
 private func injectBootstrap(into response: HTTPResponse) -> HTTPResponse {
  guard var html = String(data: response.body, encoding: .utf8) else { return response }
  let snippet = """
  <style id="hubnode-kea-host">
  button[aria-label="Model settings"],
  [data-screen-label="Settings"] details.kea-model,
  .kea-model-config { display: none !important; }
  .hubnode-md {
    word-break: break-word;
    overflow-wrap: anywhere;
    /* pre-wrap keeps model newlines if DC wipes our HTML back to plain text */
    white-space: pre-wrap !important;
  }
  .hubnode-md p { margin: 0 0 0.55em; white-space: normal; }
  .hubnode-md p:last-child { margin-bottom: 0; }
  .hubnode-md strong { font-weight: 700; color: inherit; }
  .hubnode-md em { font-style: italic; }
  .hubnode-md h2, .hubnode-md h3 {
    margin: 0.55em 0 0.3em; font-size: 1.02em; font-weight: 800; line-height: 1.3;
    white-space: normal;
  }
  .hubnode-md h2:first-child, .hubnode-md h3:first-child { margin-top: 0; }
  /* Block + hanging indent: works even when display:grid is overridden */
  .hubnode-md .md-li {
    display: block !important;
    margin: 0.55em 0 !important;
    padding-left: 1.75em !important;
    text-indent: -1.75em !important;
    white-space: normal !important;
    line-height: 1.45;
  }
  .hubnode-md .md-li .n {
    display: inline !important;
    font-weight: 700 !important;
    font-variant-numeric: tabular-nums;
    margin-right: 0.35em !important;
    text-indent: 0 !important;
  }
  .hubnode-md .md-li .md-li-body,
  .hubnode-md .md-li > span:last-child {
    display: inline !important;
    min-width: 0;
    text-indent: 0 !important;
    white-space: normal !important;
  }
  .hubnode-md code {
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 0.92em; background: rgba(0,0,0,0.06); padding: 0.05em 0.3em; border-radius: 3px;
  }
  /* Waiting bubble: fixed 3ch so . / .. / ... never resizes the bubble. */
  .kea-dots {
    display: inline-block;
    box-sizing: border-box;
    width: 3ch;
    min-width: 3ch;
    max-width: 3ch;
    overflow: hidden;
    text-align: left;
    font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    font-size: 18px;
    font-weight: 700;
    letter-spacing: 0;
    color: #5c5c5c;
    line-height: 1.2;
  }
  </style>
  <script src="/hubnode-bridge.js"></script>
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
