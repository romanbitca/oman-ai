// OmanAI's page. No libraries and no tracking: everything here runs in the reader's browser.
(() => {
  "use strict";

  const root = document.documentElement;
  root.classList.add("js");
  const still = window.matchMedia("(prefers-reduced-motion: reduce)");
  const clamp = (value, low, high) => Math.min(high, Math.max(low, value));
  const all = (selector, scope = document) => [...scope.querySelectorAll(selector)];

  // The paragraph that lights up as it is read: one span for each word.
  const statement = document.querySelector("[data-words]");
  let words = [];
  if (statement) {
    const text = statement.textContent.trim().split(/\s+/);
    statement.textContent = "";
    statement.setAttribute("aria-label", text.join(" "));
    words = text.map((word, index) => {
      const span = document.createElement("span");
      span.className = "w";
      span.setAttribute("aria-hidden", "true");
      span.textContent = word + (index < text.length - 1 ? " " : "");
      statement.append(span);
      return span;
    });
    if (still.matches) words.forEach((span) => span.classList.add("on"));
  }

  // One handler for everything that follows the scroll position.
  const nav = document.querySelector("[data-nav]");
  let queued = false;
  function follow() {
    queued = false;
    nav?.classList.toggle("is-scrolled", window.scrollY > 24);
    if (words.length && !still.matches) {
      const box = statement.getBoundingClientRect();
      // Read from when its top passes four fifths of the way down the window until its end passes the middle.
      const read = clamp((window.innerHeight * 0.8 - box.top) / (box.height + window.innerHeight * 0.3), 0, 1);
      const lit = Math.round(read * words.length);
      words.forEach((span, index) => span.classList.toggle("on", index < lit));
    }
  }
  window.addEventListener("scroll", () => { if (!queued) { queued = true; requestAnimationFrame(follow); } }, { passive: true });
  window.addEventListener("resize", follow);
  follow();

  // Things come into focus as they are scrolled to, and numbers count up when they do.
  function countUp(el) {
    const target = Number(el.dataset.count);
    const decimals = Number(el.dataset.decimals || 0);
    if (still.matches || !Number.isFinite(target) || target === 0) return;
    const began = performance.now();
    const tick = (now) => {
      const t = clamp((now - began) / 1400, 0, 1);
      el.textContent = (target * (1 - Math.pow(1 - t, 3))).toFixed(decimals);
      if (t < 1) requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  }
  if ("IntersectionObserver" in window) {
    const arrivals = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        entry.target.classList.add("is-in");
        all("[data-count]", entry.target).forEach(countUp);
        arrivals.unobserve(entry.target);
      }
    }, { threshold: 0.12, rootMargin: "0px 0px -6% 0px" });
    all("[data-rise]").forEach((el) => arrivals.observe(el));
  } else {
    all("[data-rise]").forEach((el) => el.classList.add("is-in"));
  }

  // Recordings play while they are on screen, and each one can be paused.
  const onScreen = new Set();
  const stopped = new WeakSet();
  // A recording is wanted while it is the one being shown: the chosen one in the header, or the open tab below.
  function wanted(video) {
    const clip = video.closest(".reel-clip");
    if (clip) return clip.classList.contains("is-on");
    return video.hasAttribute("data-autoplay") || !video.closest("[role=tabpanel]")?.hidden;
  }
  function settle(video) {
    const play = onScreen.has(video) && wanted(video) && !stopped.has(video) && !still.matches;
    if (play && video.paused) video.play().catch(() => { /* The browser may refuse until the reader presses play. */ });
    if (!play && !video.paused) video.pause();
  }
  const watcher = "IntersectionObserver" in window
    ? new IntersectionObserver((entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) onScreen.add(entry.target); else onScreen.delete(entry.target);
          settle(entry.target);
        }
      }, { threshold: 0.4 })
    : null;
  for (const clip of all("[data-clip]")) {
    const video = clip.querySelector("video");
    const toggle = clip.querySelector("[data-clip-toggle]");
    if (!video || !toggle) continue;
    const show = () => {
      clip.classList.toggle("is-paused", video.paused);
      toggle.setAttribute("aria-label", video.paused ? "Play the recording" : "Pause the recording");
      toggle.querySelector("use")?.setAttribute("href", video.paused ? "#i-play" : "#i-pause");
    };
    video.addEventListener("play", show);
    video.addEventListener("pause", show);
    toggle.addEventListener("click", () => {
      if (video.paused) { stopped.delete(video); video.play().catch(() => {}); } else { stopped.add(video); video.pause(); }
    });
    show();
    watcher?.observe(video);
  }

  // The header: recordings of the panel, one after another, with the chat they act on drawn under them.
  const reel = document.querySelector("[data-reel]");
  if (reel) {
    const tabs = all("[role=tab]", reel);
    const clips = tabs.map((tab) => document.getElementById(tab.getAttribute("aria-controls")));
    const videos = clips.map((clip) => clip.querySelector("video"));
    const sender = reel.querySelector("[data-reel-from]");
    const message = reel.querySelector("[data-reel-message]");
    const field = reel.querySelector("[data-reel-field]");
    const typed = field.querySelector("mark");
    const pause = reel.querySelector("[data-reel-pause]");
    let active = 0;
    let handsOff = true;
    let pasted = null;

    // The text in the chat is selected while the panel works on it, and changes at the moment the recording pastes.
    function write(isPasted) {
      if (pasted === isPasted) return;
      pasted = isPasted;
      const text = isPasted ? clips[active].dataset.after : clips[active].dataset.before;
      typed.textContent = text || field.dataset.placeholder;
      field.classList.toggle("is-empty", !text);
      field.classList.toggle("is-pasted", isPasted);
    }

    function showPause() {
      const paused = videos[active].paused;
      pause.setAttribute("aria-label", paused ? "Play the recording" : "Pause the recording");
      pause.querySelector("use")?.setAttribute("href", paused ? "#i-play" : "#i-pause");
    }

    function choose(index, byReader) {
      if (byReader) handsOff = false;
      active = (index + tabs.length) % tabs.length;
      tabs.forEach((tab, i) => {
        const on = i === active;
        tab.setAttribute("aria-selected", String(on));
        tab.tabIndex = on ? 0 : -1;
        tab.style.setProperty("--played", "0");
        clips[i].classList.toggle("is-on", on);
        clips[i].setAttribute("aria-hidden", String(!on));
        const video = videos[i];
        video.loop = !handsOff;
        if (on) {
          stopped.delete(video);
          try { video.currentTime = 0; } catch (error) { /* Not loaded yet, so it starts at the beginning anyway. */ }
        }
        settle(video);
      });
      sender.textContent = clips[active].dataset.from;
      message.textContent = clips[active].dataset.message;
      pasted = null;
      write(false);
      showPause();
    }

    tabs.forEach((tab, index) => {
      const video = videos[index];
      const clip = clips[index];
      const pasteAt = clip.dataset.at ? Number(clip.dataset.at) : null;
      tab.addEventListener("click", () => choose(index, true));
      tab.addEventListener("keydown", (event) => {
        const move = { ArrowRight: index + 1, ArrowDown: index + 1, ArrowLeft: index - 1, ArrowUp: index - 1, Home: 0, End: tabs.length - 1 }[event.key];
        if (move === undefined) return;
        event.preventDefault();
        choose(move, true);
        tabs[active].focus();
      });
      video.addEventListener("timeupdate", () => {
        if (video.duration) tab.style.setProperty("--played", (video.currentTime / video.duration).toFixed(3));
        if (index === active && pasteAt !== null) write(video.currentTime >= pasteAt);
      });
      // Where the browser reports each frame, the text changes on the very frame the panel closes.
      if (pasteAt !== null && "requestVideoFrameCallback" in video) {
        const onFrame = (now, frame) => {
          if (index === active) write(frame.mediaTime >= pasteAt);
          video.requestVideoFrameCallback(onFrame);
        };
        video.requestVideoFrameCallback(onFrame);
      }
      video.addEventListener("ended", () => { if (handsOff && index === active) choose(index + 1, false); });
      // The next recording is fetched while this one plays, so the change between them has no gap.
      video.addEventListener("playing", () => {
        const next = videos[(index + 1) % videos.length];
        if (index === active && next !== video && next.preload === "none") { next.preload = "auto"; next.load(); }
      });
      video.addEventListener("play", showPause);
      video.addEventListener("pause", showPause);
      watcher?.observe(video);
    });
    // The button pauses the recording that is showing, and so does a click or a tap on the recording itself.
    function togglePause() {
      const video = videos[active];
      if (video.paused) { stopped.delete(video); video.play().catch(() => {}); } else { stopped.add(video); video.pause(); }
    }
    pause.addEventListener("click", togglePause);
    videos.forEach((video) => video.addEventListener("click", togglePause));
    // The slab's own motion rests while it is off screen.
    if ("IntersectionObserver" in window) {
      new IntersectionObserver((entries) => {
        for (const entry of entries) reel.classList.toggle("is-away", !entry.isIntersecting);
      }).observe(reel);
    }
    choose(0, false);
  }

  // Use cases: four tabs. Left alone, each recording plays once and hands over to the next.
  const tablist = document.querySelector("[data-tabs]");
  if (tablist) {
    const tabs = all("[role=tab]", tablist);
    const panels = tabs.map((tab) => document.getElementById(tab.getAttribute("aria-controls")));
    const videos = panels.map((panel) => panel?.querySelector("video"));
    let active = 0;
    let handsOff = true;

    function choose(index, byReader) {
      if (byReader) handsOff = false;
      active = (index + tabs.length) % tabs.length;
      tabs.forEach((tab, i) => {
        const on = i === active;
        tab.setAttribute("aria-selected", String(on));
        tab.tabIndex = on ? 0 : -1;
        tab.style.setProperty("--played", "0");
        if (panels[i]) panels[i].hidden = !on;
        const video = videos[i];
        if (!video) return;
        video.loop = !handsOff;
        if (on) {
          stopped.delete(video);
          try { video.currentTime = 0; } catch (error) { /* Not loaded yet, so it starts at the beginning anyway. */ }
        }
        settle(video);
      });
    }

    tabs.forEach((tab, index) => {
      tab.addEventListener("click", () => choose(index, true));
      tab.addEventListener("keydown", (event) => {
        const move = { ArrowRight: index + 1, ArrowDown: index + 1, ArrowLeft: index - 1, ArrowUp: index - 1, Home: 0, End: tabs.length - 1 }[event.key];
        if (move === undefined) return;
        event.preventDefault();
        choose(move, true);
        tabs[active].focus();
      });
      const video = videos[index];
      video?.addEventListener("timeupdate", () => {
        if (video.duration) tab.style.setProperty("--played", (video.currentTime / video.duration).toFixed(3));
      });
      video?.addEventListener("ended", () => { if (handsOff && index === active) choose(index + 1, false); });
    });
  }

  // The demo of the panel.
  const scene = document.querySelector("[data-demo]");
  if (scene) {
    const original = "hey yes, ill send u the q3 numbers in a sec, just need to double check the churn figure first";
    const explanation = "Dana will understand that the Q3 numbers are coming very soon and that you are checking one figure first. "
      + "It sounds relaxed and friendly.\n\nCould be misread: \"in a sec\" promises minutes. Say a time if the check may take longer.";
    const answers = {
      proofread: {
        written: ["hey yes, i'll send u the q3 numbers in a sec, just need to double check the churn figure first"],
        work: ["Hey, yes, I'll send you the Q3 numbers in a sec. I just need to double-check the churn figure first."],
        friends: ["hey yes, i'll send u the q3 numbers in a sec, just need to double check the churn figure first"],
      },
      rewrite: {
        written: [
          "yes! sending you the Q3 numbers in a sec, just double-checking the churn figure first",
          "yep, Q3 numbers coming in a sec. just want to double-check the churn figure first",
        ],
        work: [
          "Hi Dana, yes. I'll send the Q3 numbers over shortly, I just want to double-check the churn figure first.",
          "Hi Dana, will do. I'm double-checking the churn figure and will send the Q3 numbers right after.",
        ],
        friends: [
          "yep! sending the q3 numbers in a sec, just double checking the churn figure 👀",
          "on it! q3 numbers coming in a sec, just checking the churn figure first 👀",
        ],
      },
      explain: { written: [explanation], work: [explanation], friends: [explanation] },
    };

    const views = Object.fromEntries(all("[data-view]", scene).map((el) => [el.dataset.view, el]));
    const panel = scene.querySelector("[data-panel]");
    const composer = scene.querySelector("[data-composer]");
    const stream = scene.querySelector("[data-stream]");
    const out = scene.querySelector("[data-out]");
    const originalButton = scene.querySelector("[data-original]");
    const copyButton = scene.querySelector("[data-copy]");
    const replaceButton = scene.querySelector("[data-replace]");
    const styleChips = all("[data-style]", scene);

    let style = "written";
    let kind = null;
    let turn = 0;
    let text = "";
    let timers = [];
    let touched = false;

    const later = (fn, ms) => timers.push(setTimeout(fn, ms));
    const clearTimers = () => { timers.forEach(clearTimeout); timers = []; };
    const show = (name) => { for (const [key, el] of Object.entries(views)) el.hidden = key !== name; };

    function pick(next) {
      style = next;
      for (const chip of styleChips) {
        const on = chip.dataset.style === style;
        chip.classList.toggle("on", on);
        chip.setAttribute("aria-pressed", String(on));
      }
    }

    function showOriginal(on) {
      originalButton.setAttribute("aria-pressed", String(on));
      originalButton.textContent = on ? "Show result" : "Show original";
      out.textContent = on ? original : text;
      out.style.color = on ? "var(--glass-muted)" : "";
    }

    function write(next) {
      clearTimers();
      text = next;
      showOriginal(false);
      // An explanation is only for reading, so there is nothing to put back.
      replaceButton.hidden = kind === "explain";
      if (still.matches) {
        out.textContent = text;
        show("result");
        return;
      }
      stream.textContent = "";
      show("working");
      const words = text.split(" ");
      words.forEach((word, index) => {
        later(() => { stream.textContent += (index ? " " : "") + word; }, 300 + index * 46);
      });
      later(() => { out.textContent = text; show("result"); }, 300 + words.length * 46 + 260);
    }

    function run(next) {
      kind = next;
      turn = 0;
      write(answers[kind][style][0]);
    }

    function reset() {
      clearTimers();
      kind = null;
      pick("written");
      all("[data-context]", scene).forEach((chip) => chip.setAttribute("aria-pressed", "false"));
      composer.classList.remove("done");
      composer.textContent = "";
      const mark = document.createElement("mark");
      mark.textContent = original;
      composer.append(mark);
      copyButton.textContent = "Copy";
      panel.hidden = false;
      show("home");
    }

    scene.addEventListener("click", (event) => {
      const target = event.target.closest("button");
      if (!target || !scene.contains(target)) return;
      touched = true;
      const data = target.dataset;
      if (data.style) pick(data.style);
      else if ("context" in data) target.setAttribute("aria-pressed", String(target.getAttribute("aria-pressed") !== "true"));
      else if (data.run) run(data.run);
      else if ("stop" in data || "back" in data) { clearTimers(); show("home"); }
      else if ("again" in data) {
        const options = answers[kind][style];
        turn = (turn + 1) % options.length;
        write(options[turn]);
      } else if ("original" in data) showOriginal(target.getAttribute("aria-pressed") !== "true");
      else if ("copy" in data) {
        const done = () => { copyButton.textContent = "Copied"; later(() => { copyButton.textContent = "Copy"; }, 1400); };
        if (navigator.clipboard) navigator.clipboard.writeText(text).then(done, done); else done();
      } else if ("replace" in data) {
        composer.textContent = "";
        const mark = document.createElement("mark");
        mark.textContent = text;
        composer.append(mark);
        panel.hidden = true;
        later(() => composer.classList.add("done"), still.matches ? 0 : 900);
      }
    });
    document.querySelector("[data-reset]")?.addEventListener("click", () => { touched = true; reset(); });

    // Plays once by itself, when it is on screen and nobody has touched it.
    function demonstrate() {
      if (touched || still.matches) return;
      const chip = scene.querySelector('[data-style="work"]');
      const action = scene.querySelector('[data-run="rewrite"]');
      chip.classList.add("pressed");
      later(() => { chip.classList.remove("pressed"); if (!touched) pick("work"); }, 380);
      later(() => { if (!touched) action.classList.add("pressed"); }, 1100);
      later(() => { action.classList.remove("pressed"); if (!touched) run("rewrite"); }, 1480);
    }
    if ("IntersectionObserver" in window) {
      const once = new IntersectionObserver((entries) => {
        if (entries.some((entry) => entry.isIntersecting)) {
          once.disconnect();
          later(demonstrate, 1200);
        }
      }, { threshold: 0.45 });
      once.observe(scene);
    }
  }

  // How it works: the step in the middle of the window drives the picture.
  const mini = document.querySelector("[data-mini]");
  const steps = all(".walk li");
  if (mini && steps.length && "IntersectionObserver" in window) {
    const wide = window.matchMedia("(min-width: 900px)");
    let stepWatcher = null;
    const watch = () => {
      stepWatcher?.disconnect();
      stepWatcher = new IntersectionObserver((entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          mini.dataset.step = entry.target.dataset.step;
          steps.forEach((step) => step.classList.toggle("is-active", step === entry.target));
        }
      }, { rootMargin: wide.matches ? "-45% 0px -45% 0px" : "-62% 0px -28% 0px" });
      steps.forEach((step) => stepWatcher.observe(step));
    };
    watch();
    wide.addEventListener("change", watch);
    steps[0].classList.add("is-active");
  }

  // Styles: the same rough note in each voice.
  const voiceBox = document.querySelector("[data-voices]");
  if (voiceBox) {
    const voices = {
      written: ["Your own voice, tidied up", "yes! sending you the Q3 numbers in a sec, just double-checking the churn figure first"],
      work: ["From six emails you sent", "Hi Dana, yes. I'll send the Q3 numbers over shortly, I just want to double-check the churn figure first."],
      friends: ["From your group chat", "yep! sending the q3 numbers in a sec, just double checking the churn figure 👀"],
      linkedin: ["From your posts", "Happy to share the Q3 numbers. I'm double-checking the churn figure first, so you'll have them shortly."],
    };
    // A few of the made-up messages each style was taught with.
    const learned = {
      written: ["Nothing to learn. As written keeps the voice of the text itself."],
      work: ["Hi Anna, thanks for the update. The proposal works for us.", "Hi Mark, just confirming the invoice was paid this morning.", "Thanks, Laura. Could you do 15% off for a yearly plan?"],
      friends: ["yep! on my way, 10 min", "haha no way, send pics", "ok cool, see you there 👀"],
      linkedin: ["Proud of what the team shipped this quarter.", "Three things I learned from our last launch.", "We're hiring. Come build with us."],
    };
    const samples = voiceBox.querySelector("[data-voice-samples]");
    const output = voiceBox.querySelector("[data-voice-out]");
    const source = voiceBox.querySelector("[data-voice-source]");
    const chips = all("[data-voice]", voiceBox);
    let typing = null;
    function say(name) {
      const [from, text] = voices[name];
      chips.forEach((chip) => chip.setAttribute("aria-pressed", String(chip.dataset.voice === name)));
      source.textContent = from;
      if (samples) {
        samples.textContent = "";
        for (const line of learned[name]) samples.appendChild(document.createElement("li")).textContent = line;
      }
      clearInterval(typing);
      if (still.matches) { output.textContent = text; return; }
      const letters = [...text];
      let count = 0;
      output.textContent = "";
      output.classList.add("caret");
      typing = setInterval(() => {
        count += 2;
        output.textContent = letters.slice(0, count).join("");
        if (count >= letters.length) { clearInterval(typing); output.classList.remove("caret"); }
      }, 16);
    }
    chips.forEach((chip) => chip.addEventListener("click", () => say(chip.dataset.voice)));
  }

  // Context: what is switched on is what is sent.
  const sendBox = document.querySelector("[data-send]");
  if (sendBox) {
    const count = sendBox.querySelector("[data-send-count]");
    all("[data-send-toggle]", sendBox).forEach((chip) => chip.addEventListener("click", () => {
      const on = chip.getAttribute("aria-pressed") !== "true";
      chip.setAttribute("aria-pressed", String(on));
      sendBox.querySelector(`[data-send-item="${chip.dataset.sendToggle}"]`)?.classList.toggle("on", on);
      count.textContent = `${all(".send-list .on", sendBox).length} things will be sent`;
    }));
  }

  // Shortcuts: the keys press themselves, one action after another.
  const keys = document.querySelector("[data-keys]");
  if (keys && !still.matches) {
    const letter = keys.querySelector("[data-key]");
    const name = keys.querySelector("[data-key-name]");
    const actions = [["R", "Rewrite selection"], ["P", "Proofread selection"], ["E", "Explain selection"], ["C", "Compose"], ["W", "Rewrite as Work"]];
    let turn = 0;
    setInterval(() => {
      if (document.hidden) return;
      turn = (turn + 1) % actions.length;
      [letter.textContent, name.textContent] = actions[turn];
      keys.classList.add("press");
      setTimeout(() => keys.classList.remove("press"), 260);
    }, 2100);
  }

  // A soft light follows the pointer across the tiles.
  for (const card of all("[data-glow]")) {
    card.addEventListener("pointermove", (event) => {
      const box = card.getBoundingClientRect();
      card.style.setProperty("--mx", `${event.clientX - box.left}px`);
      card.style.setProperty("--my", `${event.clientY - box.top}px`);
    });
  }

  // The gallery of Settings.
  const gallery = document.querySelector("[data-gallery]");
  if (gallery) {
    const rail = gallery.querySelector(".rail");
    const shots = all(".shot", rail);
    const dots = gallery.querySelector("[data-gallery-dots]");
    const marks = shots.map(() => dots.appendChild(document.createElement("i")));
    const step = (direction) => {
      const width = shots[0].getBoundingClientRect().width + parseFloat(getComputedStyle(rail).columnGap || "24");
      rail.scrollBy({ left: direction * width, behavior: still.matches ? "auto" : "smooth" });
    };
    gallery.querySelector("[data-gallery-prev]")?.addEventListener("click", () => step(-1));
    gallery.querySelector("[data-gallery-next]")?.addEventListener("click", () => step(1));
    rail.addEventListener("keydown", (event) => {
      if (event.key === "ArrowRight") { event.preventDefault(); step(1); }
      if (event.key === "ArrowLeft") { event.preventDefault(); step(-1); }
    });
    if ("IntersectionObserver" in window) {
      const seen = new IntersectionObserver((entries) => {
        for (const entry of entries) marks[shots.indexOf(entry.target)]?.classList.toggle("on", entry.isIntersecting);
      }, { root: rail, threshold: 0.6 });
      shots.forEach((shot) => seen.observe(shot));
    } else {
      marks[0]?.classList.add("on");
    }
  }

  // Donations: one address, set on <body data-donate-url>, turns every Donate button on.
  const donateUrl = (document.body.dataset.donateUrl || "").trim();
  if (/^https:\/\//.test(donateUrl)) {
    for (const link of all("[data-donate]")) {
      link.href = donateUrl;
      link.target = "_blank";
      link.rel = "noopener";
      link.hidden = false;
    }
    const note = document.querySelector("[data-donate-note]");
    if (note) note.textContent = "Every donation goes to the time it takes to keep OmanAI working and free.";
  }

  // The latest version, asked from GitHub once per visit. Without an answer the links stay on the releases page.
  function showRelease(release) {
    if (!release || !release.version) return;
    const megabytes = release.size ? ` · ${(release.size / 1048576).toFixed(1)} MB` : "";
    for (const link of all("[data-download]")) if (release.url) link.href = release.url;
    for (const label of all("[data-version]")) label.textContent = `Version ${release.version}${megabytes} · macOS 14 or later`;
    for (const label of all("[data-version-short]")) label.textContent = `${release.version}${megabytes}`;
    for (const label of all("[data-version-pill]")) label.textContent = `OmanAI ${release.version} is out`;
  }
  (async () => {
    try {
      const kept = sessionStorage.getItem("oman-release");
      if (kept) { showRelease(JSON.parse(kept)); return; }
    } catch (error) { /* No storage: ask again. */ }
    try {
      const response = await fetch("https://api.github.com/repos/romanbitca/oman-ai/releases/latest", {
        headers: { Accept: "application/vnd.github+json" },
      });
      if (!response.ok) return;
      const data = await response.json();
      const zip = (data.assets || []).find((asset) => /\.zip$/.test(asset.name));
      const release = { version: String(data.tag_name || "").replace(/^v/, ""), url: zip?.browser_download_url, size: zip?.size };
      showRelease(release);
      try { sessionStorage.setItem("oman-release", JSON.stringify(release)); } catch (error) { /* Fine without it. */ }
    } catch (error) { /* Offline, or GitHub said no. The page works without the number. */ }
  })();
})();
