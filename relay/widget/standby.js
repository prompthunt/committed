/*
 * Committed's StandBy pair for other screens (relay/README.md, "Web widget").
 *
 * ES5 only: it runs on the Samsung Frame's Chromium 76, and test/widget-runtime.test.ts parses it
 * as ES5. The installation ID and board read token come from this page's fragment
 * (#installation=…&token=…), which browsers never send to a server; the token only ever goes out
 * in the board route's Authorization header, never in a URL.
 */
(function () {
  "use strict";

  /** About the relay's cycle: it recomputes the board every 5 minutes. */
  var POLL_MS = 5 * 60 * 1000;
  /** Before the first board arrives, a failed load retries sooner. */
  var RETRY_MS = 60 * 1000;
  /** Live rank's stale interval (LiveRankState.staleInterval): 20 minutes of data age. */
  var STALE_SECONDS = 20 * 60;
  var REQUEST_TIMEOUT_MS = 20 * 1000;
  var WINDOW_TITLES = { daily: "Today", weekly: "7 days", monthly: "30 days" };
  /** A row's height plus its margin, in rem (standby.css .row). */
  var ROW_PITCH_REM = 2.55;

  var doc = document;
  var root = doc.documentElement;
  /** In another screen's frame the page is transparent, so the host's tile color shows through. */
  var embedded = window.self !== window.top;
  var rowsEl = byId("rows");
  var countEl = byId("count");

  var config = readFragment(location.hash);
  var windowName = WINDOW_TITLES.hasOwnProperty(config.window) ? config.window : "daily";
  var board = null;
  var shownCount = null;
  var rowEls = {};
  var unit = 24;
  var pollTimer = null;
  var countTimer = null;
  var inFlight = false;

  function byId(id) {
    return doc.getElementById(id);
  }

  function readFragment(hash) {
    var out = {};
    var parts = (hash || "").replace(/^#/, "").split("&");
    for (var i = 0; i < parts.length; i++) {
      var pair = parts[i].split("=");
      try {
        out[decodeURIComponent(pair[0])] = decodeURIComponent(pair.slice(1).join("="));
      } catch (e) {
        // A malformed escape: leave that key out.
      }
    }
    return out;
  }

  function setState(state) {
    if (root.getAttribute("data-state") !== state) root.setAttribute("data-state", state);
  }

  function nowSeconds() {
    return Date.now() / 1000;
  }

  // MARK: - Loading

  function load() {
    clearTimeout(pollTimer);
    if (inFlight) return;
    inFlight = true;
    var xhr = new XMLHttpRequest();
    var url = "/v1/installations/" + encodeURIComponent(config.installation) + "/board?window=" + windowName;
    xhr.open("GET", url, true);
    xhr.setRequestHeader("Authorization", "Bearer " + config.token);
    xhr.timeout = REQUEST_TIMEOUT_MS;
    xhr.onload = function () {
      finish(xhr.status, xhr.responseText);
    };
    xhr.onerror = xhr.ontimeout = function () {
      finish(0, "");
    };
    xhr.send();
  }

  function finish(status, text) {
    inFlight = false;
    var next = POLL_MS;
    if (status === 200) {
      var data = null;
      try {
        data = JSON.parse(text);
      } catch (e) {
        data = null;
      }
      if (data && data.rows) {
        board = data;
        render(true);
      } else if (!board) {
        next = RETRY_MS;
      }
    } else if (status === 401 || status === 403) {
      showMessage(
        "revoked",
        "This screen's access was revoked",
        "Mint a new board read token for this screen, then update its address."
      );
    } else if (status === 404) {
      showMessage("gone", "Live rank is off on your iPhone", "Turn on Live rank in Committed to show your board here.");
    } else if (!board) {
      // A network blip or a relay error: keep the last board (or the placeholders) and try again.
      next = RETRY_MS;
    }
    pollTimer = setTimeout(load, next);
  }

  function showMessage(state, title, detail) {
    board = null;
    shownCount = null;
    clearTimeout(countTimer);
    for (var login in rowEls) {
      if (rowEls.hasOwnProperty(login)) rowsEl.removeChild(rowEls[login]);
    }
    rowEls = {};
    byId("message-title").textContent = title;
    byId("message-detail").textContent = detail;
    countEl.textContent = "–";
    byId("rank").textContent = "–";
    byId("age").textContent = "";
    setState(state);
  }

  // MARK: - Rendering

  function render(animate) {
    var state = board;
    var titles = doc.querySelectorAll("[data-window-title]");
    for (var i = 0; i < titles.length; i++) titles[i].textContent = WINDOW_TITLES[state.window] || "Today";

    // With nobody else on the board there's no rank: your count takes its place (CommittedWidgetSmall).
    var ranked = state.rank !== null || state.competitorCount > 1;
    byId("panes-card").className = ranked ? "card" : "card unranked";
    byId("rank").textContent = state.rank !== null ? "#" + state.rank : "–";
    setCount(state.contributions, animate);
    byId("square").setAttribute("data-level", state.contributions > 0 ? "4" : "0");

    var status = byId("status");
    var line = emptyStateLine(state);
    if (state.contributions === null || state.competitorCount <= 1) {
      status.textContent = line || "";
      status.className = "status quiet";
    } else {
      status.textContent = state.gapToPass !== null && state.above ? state.gapToPass + " to pass " + state.above.login : "";
      status.className = "status";
    }

    tick();
    renderRows(animate);
  }

  /** LiveRankState.emptyStateLine: said in place of a rank when there isn't one. */
  function emptyStateLine(state) {
    if (state.competitorCount <= 1) return "Just you so far";
    if (state.contributions === null) return "Waiting for your first count";
    return null;
  }

  /** Your count, ticking up through the values in between when it rises. */
  function setCount(target, animate) {
    clearTimeout(countTimer);
    if (target === null || target === undefined) {
      shownCount = null;
      countEl.textContent = "–";
      return;
    }
    var from = shownCount;
    shownCount = target;
    if (!animate || from === null || target <= from) {
      countEl.textContent = String(target);
      return;
    }
    var steps = Math.min(target - from, 12);
    var step = 0;
    var line = byId("count-line");
    line.className = "count-line bump";
    function next() {
      step += 1;
      countEl.textContent = String(Math.round(from + ((target - from) * step) / steps));
      if (step < steps) {
        countTimer = setTimeout(next, Math.round(700 / steps));
      } else {
        line.className = "count-line";
      }
    }
    countTimer = setTimeout(next, 60);
  }

  /**
   * WidgetSnapshot.boardRows: the leaders when you're among them, otherwise the first few, the
   * person just ahead of you, and you, so your race is always on screen.
   */
  function pickRows(rows, count, state) {
    var leaders = rows.slice(0, count);
    var meIndex = -1;
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].isSelf) meIndex = i;
    }
    var me = meIndex >= 0 ? rows[meIndex] : null;
    if (!me || state.rank === null || me.contributions === null || meIndex < count) return leaders;
    var picked = rows.slice(0, Math.max(count - 2, 0));
    var lastRank = picked.length ? picked[picked.length - 1].rank : 0;
    var above = rows[meIndex - 1];
    if (above && me.rank - 1 > lastRank && picked.length < meIndex) {
      picked.push(above);
    } else if (picked.length < count - 1 && rows[picked.length]) {
      picked.push(rows[picked.length]);
    }
    picked.push(me);
    return picked;
  }

  /** How many rows fit the board's box. */
  function rowCapacity() {
    var pitch = unit * ROW_PITCH_REM;
    return Math.max(2, Math.floor((rowsEl.clientHeight + unit * 0.25) / pitch));
  }

  function renderRows(animate) {
    if (!board) return;
    // FLIP: where each row was, then where it lands, then a transform from the one to the other.
    var before = {};
    var login;
    for (login in rowEls) {
      if (rowEls.hasOwnProperty(login)) before[login] = rowEls[login].getBoundingClientRect().top;
    }

    // Measure the room with the board stretched to fill the box, then settle it.
    var widget = byId("widget");
    widget.className = "widget";
    var capacity = rowCapacity();
    var picked = pickRows(board.rows, capacity, board);
    if (picked.length < capacity) widget.className = "widget compact";
    var busiest = 0;
    for (var i = 0; i < picked.length; i++) {
      if (picked[i].contributions > busiest) busiest = picked[i].contributions;
    }

    var next = {};
    for (i = 0; i < picked.length; i++) {
      var row = picked[i];
      var el = rowEls[row.login];
      var isNew = !el;
      if (isNew) el = createRow(row.login, animate);
      updateRow(el, row, busiest, animate && !isNew);
      rowsEl.appendChild(el);
      next[row.login] = el;
    }
    for (login in rowEls) {
      if (rowEls.hasOwnProperty(login) && !next[login]) rowsEl.removeChild(rowEls[login]);
    }
    rowEls = next;

    for (login in rowEls) {
      if (!rowEls.hasOwnProperty(login)) continue;
      truncateName(rowEls[login]);
      if (!animate || before[login] === undefined) continue;
      var moved = before[login] - rowEls[login].getBoundingClientRect().top;
      if (Math.abs(moved) < 1) continue;
      slide(rowEls[login], moved);
    }

    // New rows fade in.
    var entering = rowsEl.querySelectorAll(".row.entering");
    if (entering.length) {
      rowsEl.getBoundingClientRect();
      for (i = 0; i < entering.length; i++) entering[i].className = "row";
    }
  }

  function slide(el, offset) {
    el.style.transition = "none";
    el.style.transform = "translateY(" + offset + "px)";
    el.getBoundingClientRect();
    el.style.transition = "";
    el.style.transform = "";
  }

  function createRow(login, animate) {
    var el = doc.createElement("li");
    el.className = animate ? "row entering" : "row";
    el.setAttribute("data-testid", "row");
    el.setAttribute("data-login", login);
    el.innerHTML =
      '<span class="row-rank"></span>' +
      '<span class="avatar"><span class="initials"></span></span>' +
      '<span class="name-wrap"><span class="name"></span></span>' +
      '<span class="move-slot"></span>' +
      '<span class="row-count"></span>' +
      '<span class="glyph"><i></i><i></i><i></i><i></i></span>';
    el.querySelector(".initials").textContent = letterInitials(login);
    loadAvatar(el.querySelector(".avatar"), login);
    return el;
  }

  function updateRow(el, row, busiest, animate) {
    el.setAttribute("data-self", row.isSelf ? "true" : "false");
    el.querySelector(".row-rank").textContent = "#" + row.rank;
    var name = el.querySelector(".name");
    name.textContent = row.login;
    name.setAttribute("data-full", row.login);
    var wrap = el.querySelector(".name-wrap");
    var badge = wrap.querySelector(".badge");
    if (row.isSelf && !badge) {
      badge = doc.createElement("span");
      badge.className = "badge";
      badge.textContent = "you";
      wrap.appendChild(badge);
    } else if (!row.isSelf && badge) {
      wrap.removeChild(badge);
    }
    el.querySelector(".row-count").textContent = row.contributions === null ? "–" : String(row.contributions);
    var glyph = el.querySelector(".glyph");
    glyph.className = row.contributions === null ? "glyph empty" : "glyph";
    glyph.setAttribute("data-level", String(squareLevel(row.contributions || 0, busiest)));
    setMovement(el.querySelector(".move-slot"), row.movementToday || 0, animate);
  }

  /** SquareRamp.level: the leader's quartile, 0 for no contributions. */
  function squareLevel(value, max) {
    if (value <= 0 || max <= 0) return 0;
    var fraction = value / max;
    if (fraction <= 0.25) return 1;
    if (fraction <= 0.5) return 2;
    if (fraction <= 0.75) return 3;
    return 4;
  }

  /** Today's movement: one chevron for a one-place move, two for more. Nothing when it held. */
  function setMovement(slot, delta, animate) {
    var current = slot.firstChild;
    var direction = delta > 0 ? "up" : "down";
    var twice = Math.abs(delta) >= 2 ? "true" : "false";
    if (delta === 0) {
      if (current) slot.removeChild(current);
      return;
    }
    if (current && current.getAttribute("data-direction") === direction && current.getAttribute("data-double") === twice) {
      return;
    }
    if (current) slot.removeChild(current);
    var mark = doc.createElement("span");
    mark.className = "movement";
    mark.setAttribute("data-testid", "movement");
    mark.setAttribute("data-direction", direction);
    mark.setAttribute("data-double", twice);
    mark.setAttribute("aria-label", (delta > 0 ? "up " : "down ") + Math.abs(delta) + " today");
    mark.innerHTML =
      twice === "true"
        ? '<svg viewBox="0 0 12 12" aria-hidden="true"><path d="M2 6.5 6 2.5 10 6.5M2 10.5 6 6.5 10 10.5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>'
        : '<svg viewBox="0 0 12 12" aria-hidden="true"><path d="M2 8.5 6 4.5 10 8.5" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
    if (animate) mark.className = "movement appearing";
    slot.appendChild(mark);
    if (animate) {
      mark.getBoundingClientRect();
      setTimeout(function () {
        mark.className = "movement";
      }, 30);
    }
  }

  /** AvatarColor.letterInitials: "sam-rivera" is "SR", "guest-08" is "GU". */
  function letterInitials(login) {
    var parts = login.split("-");
    var letters = [];
    for (var i = 0; i < parts.length; i++) {
      var only = parts[i].replace(/[^A-Za-z]/g, "");
      if (only) letters.push(only);
    }
    if (letters.length >= 2) return (letters[0].charAt(0) + letters[1].charAt(0)).toUpperCase();
    if (letters.length === 1) return letters[0].slice(0, 2).toUpperCase();
    return login.charAt(0).toUpperCase();
  }

  /** The GitHub avatar fades in over the initials once it loads; on failure the initials stay. */
  function loadAvatar(avatar, login) {
    var img = doc.createElement("img");
    img.alt = "";
    img.onload = function () {
      avatar.className = "avatar loaded";
    };
    img.onerror = function () {
      if (img.parentNode) img.parentNode.removeChild(img);
    };
    img.src = "https://github.com/" + encodeURIComponent(login) + ".png?size=96";
    avatar.appendChild(img);
  }

  /** Long logins lose their middle ("sa…vera"), as the app's rows truncate them. */
  function truncateName(row) {
    var name = row.querySelector(".name");
    var full = name.getAttribute("data-full") || name.textContent;
    name.textContent = full;
    if (name.scrollWidth <= name.clientWidth + 1) return;
    var low = 1;
    var high = full.length - 1;
    var best = 1;
    while (low <= high) {
      var mid = Math.floor((low + high) / 2);
      name.textContent = middle(full, mid);
      if (name.scrollWidth <= name.clientWidth + 1) {
        best = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    name.textContent = middle(full, best);
  }

  function middle(text, keep) {
    var head = Math.ceil(keep / 2);
    return text.slice(0, head) + "…" + text.slice(text.length - (keep - head));
  }

  // MARK: - Time: the counting-up age and the stale treatment

  function tick() {
    if (!board) return;
    var age = byId("age");
    if (board.updatedAt === null || board.updatedAt === undefined) {
      age.textContent = "";
      setState("live");
      return;
    }
    var seconds = Math.max(0, Math.floor(nowSeconds() - board.updatedAt));
    age.textContent = ageText(seconds);
    setState(seconds >= STALE_SECONDS ? "stale" : "live");
  }

  /** "36 sec", "13 min, 36 sec", "3 hr, 0 min": the widgets' relative age. */
  function ageText(seconds) {
    if (seconds < 60) return seconds + " sec";
    if (seconds < 3600) return Math.floor(seconds / 60) + " min, " + (seconds % 60) + " sec";
    return Math.floor(seconds / 3600) + " hr, " + Math.floor((seconds % 3600) / 60) + " min";
  }

  // MARK: - Fitting the box

  /** One rem scales with the box the page is given, so the pair fills it at any size. */
  function fit() {
    var width = root.clientWidth || window.innerWidth;
    var height = root.clientHeight || window.innerHeight;
    var stacked = height > width * 1.2;
    unit = stacked ? Math.min(width / 20, height / 28) : Math.min(width / 36, height / 15);
    root.style.fontSize = unit + "px";
    root.className = (stacked ? "stacked" : "") + (embedded ? " embedded" : "");
    if (board) renderRows(false);
  }

  // MARK: - Start

  fit();
  window.addEventListener("resize", fit);
  if (doc.fonts && doc.fonts.ready) {
    doc.fonts.ready.then(function () {
      if (board) renderRows(false);
    });
  }

  if (!config.installation || !config.token) {
    showMessage(
      "setup",
      "Add this screen's board token",
      "Open this page as /v1/widget#installation=…&token=… with your installation ID and a board read token."
    );
    return;
  }

  setInterval(tick, 1000);
  window.addEventListener("online", load);
  load();
})();
