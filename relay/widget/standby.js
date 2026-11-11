/*
 * Committed's StandBy pair for other screens (relay/README.md, "Web widget"): the iPhone app's
 * hero card (BoardSummaryView, rank only) beside the board list.
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
  /** ContributionWindow.shortTitle, and the Window's place in the app's switch (the folio's number). */
  var WINDOW_TITLES = { daily: "Today", weekly: "7 days", monthly: "30 days", month: "This month" };
  var WINDOW_NUMBERS = { daily: "01", weekly: "02", monthly: "03", month: "04" };
  /** A row's height plus its margin, in rem (standby.css .row). */
  var ROW_PITCH_REM = 2.55;
  /** The rank's size before fitting, in rem: beside the board, and stacked over it. */
  var RANK_REM = 7;
  var RANK_STACKED_REM = 5;
  /** Below this the card gives up a line (identity, then the age, …) to keep the rank legible. */
  var RANK_MIN_REM = 2.6;
  /** Palette.squares up to the hero field's brightest level (FieldTone.hero.maxLevel = 3). */
  var SQUARES = [[0x14, 0x17, 0x0f], [0x1d, 0x2e, 0x0e], [0x35, 0x5c, 0x12], [0x6a, 0xa8, 0x1a]];

  var doc = document;
  var root = doc.documentElement;
  /** In another screen's frame the page is transparent, so the host's tile color shows through. */
  var embedded = window.self !== window.top;
  var rowsEl = byId("rows");
  var cardEl = byId("card");
  var rankEl = byId("rank");

  var config = readFragment(location.hash);
  var windowName = WINDOW_TITLES.hasOwnProperty(config.window) ? config.window : "daily";
  var board = null;
  var shownCount = null;
  var rowEls = {};
  var unit = 24;
  var stacked = false;
  var pollTimer = null;
  var countTimer = null;
  var inFlight = false;
  /** The card's mode ("", "unranked", "unranked waiting", "loading") and the lines it gave up. */
  var cardMode = "loading";
  var cardDegrade = "";
  /** The size the field was last drawn for. */
  var fieldKey = "";
  var whoLogin = null;

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

  function setText(el, text) {
    if (el.textContent !== text) el.textContent = text;
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
    byId("count").textContent = "–";
    rankEl.textContent = "–";
    rankEl.style.fontSize = "";
    byId("rank-of").textContent = "";
    byId("age").textContent = "";
    byId("list-head").textContent = "";
    setCardMode("loading");
    setState(state);
  }

  // MARK: - Rendering

  function render(animate) {
    var state = board;
    var title = WINDOW_TITLES[state.window] || WINDOW_TITLES[windowName];
    setText(byId("folio"), (WINDOW_NUMBERS[state.window] || WINDOW_NUMBERS[windowName]) + " · " + title);
    // FolioHeader on the Board: "12 people · Today", everyone ranked, you included.
    var people = state.competitorCount === 1 ? "1 person" : state.competitorCount + " people";
    setText(byId("list-head"), people + " · " + title);

    renderWho(state);

    // A rank with "of N"; without one, the trophy in its place (BoardSummaryView.rank). With
    // nobody else on the board your count stands beside it, as the app's numbers row does.
    if (state.rank !== null) {
      setCardMode("");
      setText(rankEl, "#" + state.rank);
      setText(byId("rank-of"), "of " + state.competitorCount);
    } else {
      setCardMode(state.competitorCount <= 1 ? "unranked" : "unranked waiting");
      setText(rankEl, "–");
      setText(byId("rank-of"), "");
    }
    // Rank only: with a rank, your count lives on your row, not on the card.
    setCount(state.rank === null ? state.contributions : null, animate);

    // Movement on Today and This month only, as the app's showsTodaysMovement.
    renderMovement(state.window === "daily" || state.window === "month" ? state.movementToday || 0 : 0);

    var status = byId("status");
    var line = emptyStateLine(state);
    if (line) {
      setText(status, line);
      status.className = "status quiet";
    } else {
      // LiveRankState.passLine: nothing in first place.
      setText(status, state.gapToPass !== null && state.above ? state.gapToPass + " to pass " + state.above.login : "");
      status.className = "status";
    }

    tick();
    renderRows(animate);
    fitCard();
  }

  /** Your avatar (lime ring), first name over @login, or @login alone (BoardSummaryView.identity). */
  function renderWho(state) {
    var first = firstName(state.displayName);
    setText(byId("who-name"), first || "@" + state.login);
    setText(byId("who-handle"), first ? "@" + state.login : "");
    if (whoLogin !== state.login) {
      whoLogin = state.login;
      var avatar = byId("who-avatar");
      var old = avatar.querySelector("img");
      if (old) avatar.removeChild(old);
      avatar.className = "who-avatar avatar";
      byId("who-initials").textContent = letterInitials(state.login);
      loadAvatar(avatar, state.login, "who-avatar avatar loaded");
    }
  }

  /** DisplayName.firstName: the first word of your GitHub name, or null without one. */
  function firstName(name) {
    if (typeof name !== "string") return null;
    var words = name.replace(/^\s+|\s+$/g, "").split(/\s+/);
    return words[0] ? words[0] : null;
  }

  /** "Up 2 today" in lime with a chevron, "Down 1 today" in soft; nothing when you held. */
  function renderMovement(delta) {
    var el = byId("movement-line");
    var key = String(delta);
    if (el.getAttribute("data-delta") === key) return;
    el.setAttribute("data-delta", key);
    if (delta === 0) {
      el.removeAttribute("data-direction");
      el.innerHTML = "";
      return;
    }
    el.setAttribute("data-direction", delta > 0 ? "up" : "down");
    var path = delta > 0 ? "M2 8.5 6 4.5 10 8.5" : "M2 3.5 6 7.5 10 3.5";
    el.innerHTML =
      '<svg viewBox="0 0 12 12" aria-hidden="true"><path d="' +
      path +
      '" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
    el.appendChild(doc.createTextNode(delta > 0 ? "Up " + delta + " today" : "Down " + -delta + " today"));
  }

  /** LiveRankState.emptyStateLine: said in place of a rank when there isn't one. */
  function emptyStateLine(state) {
    if (state.competitorCount <= 1) return "Just you so far";
    if (state.contributions === null) return "Waiting for your first count";
    return null;
  }

  function setCardMode(mode) {
    cardMode = mode;
    var name = "card" + (mode ? " " + mode : "") + (cardDegrade ? " " + cardDegrade : "");
    if (cardEl.className !== name) cardEl.className = name;
  }

  /** Your count beside the trophy when there's no rank, ticking up when it rises. */
  function setCount(target, animate) {
    clearTimeout(countTimer);
    var countEl = byId("count");
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
    countEl.className = "count bump";
    countTimer = tickUp(countEl, from, target, function () {
      countEl.className = "count";
    });
  }

  /** Counts up through the values in between over about 0.7 s. Returns the first timer. */
  function tickUp(el, from, target, done) {
    var steps = Math.min(target - from, 12);
    var step = 0;
    function next() {
      step += 1;
      el.textContent = String(Math.round(from + ((target - from) * step) / steps));
      if (step < steps) {
        el.tickTimer = setTimeout(next, Math.round(700 / steps));
      } else if (done) {
        done();
      }
    }
    el.tickTimer = setTimeout(next, 60);
    return el.tickTimer;
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
    loadAvatar(el.querySelector(".avatar"), login, "avatar loaded");
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
    setRowCount(el.querySelector(".row-count"), row.contributions, animate);
    var glyph = el.querySelector(".glyph");
    glyph.className = row.contributions === null ? "glyph empty" : "glyph";
    glyph.setAttribute("data-level", String(squareLevel(row.contributions || 0, busiest)));
    setMovement(el.querySelector(".move-slot"), row.movementToday || 0, animate);
  }

  /** A row's count, ticking up through the values in between when it rises. */
  function setRowCount(el, value, animate) {
    clearTimeout(el.tickTimer);
    var shown = el.getAttribute("data-value");
    var from = shown === null || shown === "" ? null : Number(shown);
    el.setAttribute("data-value", value === null ? "" : String(value));
    if (value === null) {
      el.textContent = "–";
    } else if (animate && from !== null && value > from) {
      el.textContent = String(from);
      tickUp(el, from, value, null);
    } else {
      el.textContent = String(value);
    }
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
  function loadAvatar(avatar, login, loadedClass) {
    var img = doc.createElement("img");
    img.alt = "";
    img.onload = function () {
      if (img.parentNode === avatar) avatar.className = loadedClass;
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

  // MARK: - Time: the age and the stale treatment

  function tick() {
    if (!board) return;
    var age = byId("age");
    if (board.updatedAt === null || board.updatedAt === undefined) {
      setText(age, "");
      setState("live");
      return;
    }
    var seconds = Math.max(0, Math.floor(nowSeconds() - board.updatedAt));
    setText(age, "Updated " + coarseAge(seconds));
    setState(seconds >= STALE_SECONDS ? "stale" : "live");
  }

  /** CoarseAge: "just now", "4 min ago", "2 hr ago", "3 days ago". It never counts seconds. */
  function coarseAge(seconds) {
    var minutes = Math.floor(seconds / 60);
    if (minutes < 1) return "just now";
    if (minutes < 60) return minutes + " min ago";
    var hours = Math.floor(minutes / 60);
    if (hours < 24) return hours + " hr ago";
    var days = Math.floor(hours / 24);
    return days === 1 ? "1 day ago" : days + " days ago";
  }

  // MARK: - Fitting the card

  /**
   * The rank as large as the card allows. When even the smallest legible rank doesn't fit, the
   * card gives up a line at a time: your identity, the age, the movement line, the folio's label.
   */
  function fitCard() {
    if (!board || !cardEl.clientWidth) return;
    var steps = ["", "no-who", "no-who no-age", "no-who no-age no-move", "no-who no-age no-move no-label"];
    var base = (stacked ? RANK_STACKED_REM : RANK_REM) * unit;
    var size = base;
    for (var i = 0; i < steps.length; i++) {
      cardDegrade = steps[i];
      setCardMode(cardMode);
      if (cardMode) {
        // No rank: the trophy (and your count) at their own size, so only room matters.
        rankEl.style.fontSize = base + "px";
        if (byId("solo").offsetHeight <= byId("hero").clientHeight + 1) break;
      } else {
        size = rankFit(base);
        if (size >= RANK_MIN_REM * unit) break;
      }
    }
    if (!cardMode) rankEl.style.fontSize = Math.floor(size) + "px";
    // The folio drops its label when the card is too narrow for both, as the app's FolioRow does.
    var folio = cardEl.querySelector(".folio");
    if (folio.scrollWidth > folio.clientWidth + 1 && cardDegrade.indexOf("no-label") < 0) {
      cardDegrade += (cardDegrade ? " " : "") + "no-label";
      setCardMode(cardMode);
    }
    drawField();
  }

  /** The largest rank size, up to `base`, that fits the hero's width and height. */
  function rankFit(base) {
    var hero = byId("hero");
    var line = byId("rank-line");
    rankEl.style.fontSize = base + "px";
    var size = base;
    // "of N" keeps its size; only the rank scales.
    var rest = line.scrollWidth - rankEl.offsetWidth;
    if (line.scrollWidth > hero.clientWidth && rankEl.offsetWidth) {
      size = (size * Math.max(0, hero.clientWidth - rest)) / rankEl.offsetWidth;
      rankEl.style.fontSize = size + "px";
    }
    // Squeezed by the box: the hero has less height than the rank needs.
    var room = hero.clientHeight;
    if (line.offsetHeight > room) size = (size * room) / line.offsetHeight;
    return Math.max(0, size * 0.98);
  }

  // MARK: - The hero's square field

  /**
   * SquareFieldCanvas, still (time 0), with FieldTone.hero (brightness 0.8, levels up to 3, at
   * most 0.45 opaque). The app's two gradient masks, away from your name and faded above and below
   * the numbers, are folded into each square's opacity; the TV draws no gradients.
   */
  function drawField() {
    var field = byId("field");
    var w = cardEl.clientWidth;
    var h = cardEl.clientHeight;
    var key = w + "x" + h + (stacked ? "s" : "");
    if (!w || !h || key === fieldKey) return;
    fieldKey = key;
    var wide = w > h;
    // Beside the board the card is tall: the light sits right of the rank. Stacked it's wide, as
    // on the phone.
    var light = wide ? [0.86, 0.4] : [0.8, 0.5];
    var reach = wide ? 0.7 : 0.75;
    var band = wide ? [0.1, 0.3, 0.55, 0.85] : [0.22, 0.36, 0.62, 0.8];
    // Never under the folio, whatever the card's shape.
    var folio = cardEl.querySelector(".folio");
    var clear = (folio.offsetTop + folio.offsetHeight) / h + 0.02;
    if (band[0] < clear) {
      band[1] += clear - band[0];
      band[0] = clear;
    }
    var cell = Math.max(4, Math.round(unit * 0.85));
    var gap = Math.max(1, Math.round(unit * 0.22));
    var step = cell + gap;
    var columns = Math.ceil(w / step) + 1;
    var span = Math.max(w, h);
    var cx = light[0] * w;
    var cy = light[1] * h;
    var html = "";
    for (var r = 0; r * step + cell <= h; r++) {
      for (var c = 0; c * step + cell <= w; c++) {
        var x = c * step;
        var y = r * step;
        var dx = (x + cell / 2 - cx) / (span * reach);
        var dy = (y + cell / 2 - cy) / (span * reach);
        var lit = Math.exp(-(dx * dx + dy * dy) * 2.6);
        if (lit <= 0.02) continue;
        var mask = leadIn(x / w) * fade(y / h, band);
        var opacity = Math.min(Math.min(1, lit * 1.4) * 0.8, 0.45) * mask;
        if (opacity < 0.02) continue;
        var u = c / columns;
        var wave = (Math.cos(3 * u) + Math.cos(u)) / 4 + 0.5;
        var value = Math.min(Math.max((0.62 * hash(c, r) + 0.38 * wave) * (0.35 + 0.9 * lit), 0), 0.999) * (SQUARES.length - 1);
        html +=
          '<i style="left:' + x + "px;top:" + y + "px;width:" + cell + "px;height:" + cell + "px;background:" +
          squareColor(value) + ";opacity:" + opacity.toFixed(2) + '"></i>';
      }
    }
    field.innerHTML = html;
  }

  /** Away from your name: clear at the left edge to full at the right (the app's leading mask). */
  function leadIn(x) {
    return Math.min(1, 0.2 + x * 1.1);
  }

  /** Faded out above and below the numbers: 0 → 1 between a and b, 1 → 0 between c and d. */
  function fade(y, band) {
    if (y < band[0] || y >= band[3]) return 0;
    if (y < band[1]) return (y - band[0]) / (band[1] - band[0]);
    if (y < band[2]) return 1;
    return 1 - (y - band[2]) / (band[3] - band[2]);
  }

  /** The square's level color, eased toward the next level near its top, as the app does. */
  function squareColor(value) {
    var level = Math.floor(value);
    var next = Math.min(level + 1, SQUARES.length - 1);
    var blend = Math.max(0, (value - level - 0.7) / 0.3);
    var a = SQUARES[level];
    var b = SQUARES[next];
    return (
      "rgb(" +
      Math.round(a[0] + (b[0] - a[0]) * blend) + "," +
      Math.round(a[1] + (b[1] - a[1]) * blend) + "," +
      Math.round(a[2] + (b[2] - a[2]) * blend) + ")"
    );
  }

  /** SquareFieldCanvas.hash: a fixed "calendar" value per square. */
  function hash(a, b) {
    var x = a * 123.34;
    var y = b * 456.21;
    x = x - Math.floor(x);
    y = y - Math.floor(y);
    var d = x * (x + 45.32) + y * (y + 45.32);
    x += d;
    y += d;
    var p = x * y;
    return p - Math.floor(p);
  }

  // MARK: - Fitting the box

  /** One rem scales with the box the page is given, so the pair fills it at any size. */
  function fit() {
    var width = root.clientWidth || window.innerWidth;
    var height = root.clientHeight || window.innerHeight;
    stacked = height > width * 1.2;
    unit = stacked ? Math.min(width / 20, height / 28) : Math.min(width / 36, height / 15);
    root.style.fontSize = unit + "px";
    root.className = (stacked ? "stacked" : "") + (embedded ? " embedded" : "");
    if (board) {
      renderRows(false);
      fitCard();
    }
  }

  // MARK: - Start

  setText(byId("folio"), WINDOW_NUMBERS[windowName] + " · " + WINDOW_TITLES[windowName]);
  fit();
  window.addEventListener("resize", fit);
  if (doc.fonts && doc.fonts.ready) {
    doc.fonts.ready.then(function () {
      if (board) {
        renderRows(false);
        fitCard();
      }
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
