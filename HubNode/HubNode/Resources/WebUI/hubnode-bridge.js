/* HubNode bridge for hosted Companion console.
 *
 * Research notes (why client-only markdown failed before):
 * 1. DC template binds {{ m.text }} via textContent - any innerHTML we set is wiped on re-render.
 * 2. data-md="{{ m.text }}" breaks when answers contain newlines or quotes.
 * 3. Server now sends answer_html; we paint the last assistant bubble after setState.
 * 4. List jam "2.text": number+body are adjacent spans. Always emit a real space after
 *    "2." and use hanging-indent CSS so spacing survives even if grid styles are lost.
 * 5. Literal \\n from double-encoded model JSON must be unescaped before line split.
 */
(function () {
  "use strict";

  var H = (window.HUBNODE = window.HUBNODE || {});
  H.apiBase = H.apiBase || "/api/v1";
  H.mode = "hosted";
  H.liveBoard = "/";

  // Remember last painted HTML so MutationObserver can re-apply after DC wipes it.
  H._lastPaint = H._lastPaint || { html: "", text: "", at: 0 };

  H.escapeHtml = function (s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  };

  H.inlineMd = function (s) {
    var t = H.escapeHtml(s);
    t = t.replace(/`([^`]+)`/g, "<code>$1</code>");
    // Non-greedy so "**A** and **B**" both bold
    t = t.replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>");
    t = t.replace(/__(.+?)__/g, "<strong>$1</strong>");
    t = t.replace(/(^|[^*])\*([^*\n]+?)\*(?!\*)/g, "$1<em>$2</em>");
    return t;
  };

  H.normalizeLineBreaks = function (src) {
    var raw = String(src == null ? "" : src);
    raw = raw.replace(/\r\n/g, "\n").replace(/\r/g, "\n");
    // Literal \n from double-encoded model JSON (two chars: backslash + n)
    for (var i = 0; i < 3; i++) {
      raw = raw.replace(/\\n/g, "\n").replace(/\\t/g, "\t");
    }
    // If whole payload is still a JSON object, pull out "answer"
    var t = raw.replace(/^\s+|\s+$/g, "");
    if (t.charAt(0) === "{" && t.indexOf('"answer"') !== -1) {
      try {
        var obj = JSON.parse(t);
        if (obj && typeof obj.answer === "string" && obj.answer) {
          raw = obj.answer;
          for (var j = 0; j < 3; j++) {
            raw = raw.replace(/\\n/g, "\n").replace(/\\t/g, "\t");
          }
        }
      } catch (e) {}
    }
    // Repair bold broken by older force-break that split closing "**" into "*\n*"
    for (var r = 0; r < 3; r++) {
      raw = raw.replace(/\*\s*\n\s*\*(?!\*)/g, "**");
    }
    raw = H.repairUnbalancedBoldLines(raw);

    // Numbered steps jammed onto previous text (not times/decimals mid-number)
    raw = raw.replace(/([^\n\d])(?=\d{1,2}[\.)]\s)/g, "$1\n");

    // Real bullets only. NEVER use bare "*" against "[-*•]" — that splits "**bold**"
    // whenever bold is followed by whitespace/content (the "Heavy Rain Warning / *" bug).
    raw = raw.replace(/([^\n])(?=[•]\s+\S)/g, "$1\n");
    raw = raw.replace(/([^\n\w])(?=-\s+\S)/g, "$1\n");
    // Asterisk list marker: single "*" not part of "**"
    raw = raw.replace(/([^\n*])(?=\*\s+\S)/g, "$1\n");
    return raw;
  };

  /** Close unclosed ** when the next line is only residual * / ** markers. */
  H.repairUnbalancedBoldLines = function (raw) {
    var lines = String(raw).split("\n");
    var out = [];
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (i + 1 < lines.length) {
        var next = lines[i + 1].replace(/^\s+|\s+$/g, "");
        var marks = line.split("**").length - 1;
        var orphan = next === "*" || next === "**" || /^\*+$/.test(next);
        if (marks % 2 === 1 && orphan) {
          out.push(line.replace(/\s+$/g, "") + "**");
          i++; // skip orphan line
          continue;
        }
      }
      out.push(line);
    }
    return out.join("\n");
  };

  H.renderMarkdown = function (src) {
    var raw = H.normalizeLineBreaks(src);
    var lines = raw.split("\n");
    var out = [];
    var buf = [];
    function flush() {
      if (!buf.length) return;
      out.push("<p>" + buf.join("<br>") + "</p>");
      buf = [];
    }
    for (var i = 0; i < lines.length; i++) {
      var trimmed = lines[i].replace(/^\s+/, "").replace(/\s+$/, "");
      if (!trimmed) {
        flush();
        continue;
      }
      var m = /^(#{1,3})\s+(.*)$/.exec(trimmed);
      if (m) {
        flush();
        out.push(
          "<" +
            (m[1].length === 1 ? "h2" : "h3") +
            ">" +
            H.inlineMd(m[2]) +
            "</" +
            (m[1].length === 1 ? "h2" : "h3") +
            ">"
        );
        continue;
      }
      // Whole-line bold section title: **Note:** / **Immediate Actions**
      m = /^\*\*(.+?)\*\*:?\s*$/.exec(trimmed);
      if (m) {
        flush();
        out.push("<h3>" + H.inlineMd(m[1]) + "</h3>");
        continue;
      }
      m = /^(\d+)[\.)]\s+(.*)$/.exec(trimmed);
      if (m) {
        flush();
        // Real space after "2." so we never render "2.text" if CSS fails
        out.push(
          '<div class="md-li"><span class="n">' +
            H.escapeHtml(m[1]) +
            '.</span> <span class="md-li-body">' +
            H.inlineMd(m[2]) +
            "</span></div>"
        );
        continue;
      }
      m = /^[-*•]\s+(.*)$/.exec(trimmed);
      if (m) {
        flush();
        out.push(
          '<div class="md-li"><span class="n">•</span> <span class="md-li-body">' +
            H.inlineMd(m[1]) +
            "</span></div>"
        );
        continue;
      }
      buf.push(H.inlineMd(trimmed));
    }
    flush();
    return out.join("") || "<p></p>";
  };

  function keaAside() {
    return (
      document.querySelector('aside[aria-label*="Kea"]') ||
      document.querySelector('aside[aria-label*="kea"]') ||
      document.querySelector("aside[data-noprint]")
    );
  }

  function messageBodies(root) {
    var scope = root || keaAside() || document;
    return scope.querySelectorAll(".hubnode-md");
  }

  function looksLikeAssistantBubble(el) {
    if (!el || !el.parentElement) return false;
    var parent = el.parentElement;
    var bg = (parent.style.background || parent.style.backgroundColor || "").toLowerCase();
    // User bubbles are yellow
    if (bg.indexOf("ffdd00") !== -1) return false;
    return true;
  }

  function needsMarkdownPaint(el) {
    if (!el) return false;
    if (el.getAttribute("data-thinking") === "true") return false;
    if (el.querySelector(".kea-dots")) return false;
    // Already painted with structure
    if (el.querySelector(".md-li, p, strong, h2, h3, em, code, br")) return false;
    var t = (el.textContent || "").trim();
    if (!t || t === "." || t === ".." || t === "..." || t === "…") return false;
    // Looks like checklist / markdown that collapsed to one line
    if (/\d+[\.)]\s/.test(t) || /\*\*/.test(t) || /\\n/.test(t) || t.indexOf("\n") !== -1) {
      return true;
    }
    return false;
  }

  function paintElement(el, html) {
    if (!el || !html) return;
    if (el._keaDotTimer) {
      clearInterval(el._keaDotTimer);
      el._keaDotTimer = null;
    }
    el.classList.add("hubnode-md");
    el.innerHTML = html;
    el.setAttribute("data-md-done", "1");
    // pre-wrap fallback if something strips tags again
    if (el.style) {
      el.style.whiteSpace = "pre-wrap";
    }
  }

  /** Paint HTML into the last assistant message body in the Kea drawer. */
  H.paintLastAssistant = function (opts) {
    opts = opts || {};
    var html = opts.html;
    var text = opts.text || "";
    if (!html && text) html = H.renderMarkdown(text);
    if (!html) return false;

    H._lastPaint = { html: html, text: text, at: Date.now() };

    var attempts = 0;
    function tryPaint() {
      attempts++;
      var nodes = messageBodies();
      if (!nodes.length) {
        if (attempts < 40) setTimeout(tryPaint, 50);
        return;
      }
      // Last bubble is the newest message (assistant after thinking removed)
      var el = nodes[nodes.length - 1];
      if (!looksLikeAssistantBubble(el) && nodes.length > 1) {
        el = nodes[nodes.length - 2];
      }
      paintElement(el, html);
      // Keep re-applying: DC framework rebinds textContent after setState
      var n = 0;
      var id = setInterval(function () {
        n++;
        if (!el.isConnected) {
          clearInterval(id);
          return;
        }
        var hasMarkup = el.querySelector("p, strong, .md-li, h2, h3, em, code, br");
        var plain = el.childNodes.length === 1 && el.childNodes[0].nodeType === 3;
        if (!hasMarkup || plain) {
          paintElement(el, html);
        }
        if (n > 60) clearInterval(id);
      }, 80);
    }
    tryPaint();
    return true;
  };

  /** Re-paint assistant bubbles that lost HTML or never got it (plain checklist text). */
  H.repairAssistantMarkdown = function () {
    var nodes = messageBodies();
    var last = H._lastPaint || {};
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      if (!looksLikeAssistantBubble(el)) continue;
      if (el.querySelector(".kea-dots")) continue;

      var hasMarkup = !!el.querySelector(".md-li, p, strong, h2, h3");
      var plain = el.childNodes.length === 1 && el.childNodes[0].nodeType === 3;
      var text = (el.textContent || "").trim();

      // Prefer last server HTML when this bubble matches the last answer
      if (
        last.html &&
        last.text &&
        text &&
        (text === last.text ||
          text.indexOf(last.text.slice(0, 40)) === 0 ||
          last.text.indexOf(text.slice(0, 40)) === 0) &&
        (!hasMarkup || plain)
      ) {
        paintElement(el, last.html);
        continue;
      }

      if (needsMarkdownPaint(el)) {
        paintElement(el, H.renderMarkdown(text));
      }
    }
  };

  // One global phase so framework re-renders cannot orphan per-node timers.
  H._dotPhase = 1;
  if (!H._globalDotTimer && typeof setInterval !== "undefined") {
    H._globalDotTimer = setInterval(function () {
      H._dotPhase = H._dotPhase >= 3 ? 1 : H._dotPhase + 1;
      var dots =
        H._dotPhase === 1 ? "." : H._dotPhase === 2 ? ".." : "...";
      if (typeof document === "undefined") return;
      var spans = document.querySelectorAll(".kea-dots");
      for (var s = 0; s < spans.length; s++) {
        spans[s].textContent = dots;
      }
    }, 450);
  }

  var DOTS_HTML =
    '<span class="kea-dots" aria-label="Kea is thinking" style="' +
    "display:inline-block;box-sizing:border-box;" +
    "width:3ch;min-width:3ch;max-width:3ch;overflow:hidden;" +
    "text-align:left;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;" +
    "font-size:18px;font-weight:700;letter-spacing:0;color:#5c5c5c;line-height:1.2;" +
    '">.</span>';

  /** Ensure thinking bubbles show a fixed-width . / .. / ... indicator. */
  H.paintThinkingBubbles = function () {
    var nodes = messageBodies();
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      var t = (el.textContent || "").trim();
      var parent = el.parentElement;
      var style = (parent && parent.getAttribute("style")) || "";
      var hasDots = !!el.querySelector(".kea-dots");
      // Thinking: grey border from chrome map, or placeholder / animated dots
      var isThinking =
        el.getAttribute("data-thinking") === "true" ||
        hasDots ||
        t === "" ||
        t === "." ||
        t === ".." ||
        t === "..." ||
        t === "…" ||
        (parent && /c5c5c0/i.test(style));
      if (!isThinking) continue;
      // Already has the fixed-width control; global timer updates text
      if (hasDots) continue;
      var phase =
        H._dotPhase === 1 ? "." : H._dotPhase === 2 ? ".." : "...";
      el.innerHTML = DOTS_HTML.replace(">.<", ">" + phase + "<");
    }
  };

  H.ask = async function (q) {
    var question = String(q || "").trim();
    if (!question) throw new Error("Empty question");
    var r = await fetch((H.apiBase || "/api/v1") + "/hub/ask", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ q: question }),
    });
    var data = null;
    try {
      data = await r.json();
    } catch (_) {
      data = null;
    }
    if (!r.ok) {
      throw new Error((data && data.error) || r.statusText || "Ask failed");
    }
    // Client-side safety: if server forgot answer_html, build it
    if (data && data.answer && !data.answer_html) {
      data.answer_html = H.renderMarkdown(data.answer);
    } else if (data && data.answer) {
      // Re-normalize answer text so any leftover \\n becomes real newlines in state
      data.answer = H.normalizeLineBreaks(data.answer);
      if (!data.answer_html || data.answer_html.indexOf("md-li") === -1) {
        data.answer_html = H.renderMarkdown(data.answer);
      }
    }
    return data;
  };

  // Watch for thinking bubbles + keep typing animation alive + repair markdown
  if (typeof document !== "undefined") {
    setInterval(function () {
      H.paintThinkingBubbles();
      H.repairAssistantMarkdown();
    }, 200);

    if (typeof MutationObserver !== "undefined") {
      var obs = new MutationObserver(function () {
        H.paintThinkingBubbles();
        H.repairAssistantMarkdown();
      });
      var start = function () {
        try {
          obs.observe(document.documentElement, {
            childList: true,
            subtree: true,
            characterData: true,
          });
        } catch (e) {}
        H.paintThinkingBubbles();
      };
      if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", start);
      } else {
        start();
      }
      setTimeout(start, 400);
    }
  }

  console.info(
    "[HubNode] bridge ready (server HTML + paintLastAssistant + list spacing + typing)."
  );
})();
