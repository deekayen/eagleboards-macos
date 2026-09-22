// ------------------------------------------------------------------------
// checkin.js -- what the sign-in pages ask the Eagle Boards app.
//
//   GET  /api/checked-in       -> { refreshSeconds, youth: [...], adults: [...] }
//                                 names and units only, for the lists at the door
//   POST /api/youth-lookup     email=... -> the pre-registration it matches, or {}
//   POST /api/adult-lookup     email=... -> the adult history it matches, or {}
//   POST /register-youth       form fields -> "OK." (200) or the reason (400)
//   POST /register-adult       form fields -> "OK." (200) or the reason (400)
//
// Nothing else is served. The scheduler, the records and the settings are
// windows in the Mac app, not pages, so nobody at the door can reach them.
// ------------------------------------------------------------------------

function ebFormBody(fields) {
   var parts = [];
   for (var name in fields) {
      if (Object.prototype.hasOwnProperty.call(fields, name) && fields[name] != null) {
         parts.push(encodeURIComponent(name) + "=" + encodeURIComponent(fields[name]));
      }
   }
   return parts.join("&");
}

// POST a form. Resolves { ok, text }.
function ebPostForm(path, fields) {
   return fetch(path, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: ebFormBody(fields)
   }).then(function (response) {
      return response.text().then(function (text) {
         return { ok: response.status === 200, text: text };
      });
   });
}

// The record an email matches, or null. Sent as a POST so the address never
// lands in a URL on a shared tablet.
function ebLookup(path, email) {
   return fetch(path, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: ebFormBody({ email: email })
   }).then(function (response) {
      return response.ok ? response.json() : {};
   }).then(function (record) {
      return record && Object.keys(record).length > 0 ? record : null;
   }).catch(function () {
      return null;
   });
}

function ebCheckedIn() {
   return fetch("/api/checked-in", { cache: "no-store" }).then(function (response) {
      if (!response.ok) {
         throw new Error("HTTP " + response.status);
      }
      return response.json();
   });
}

// Prefill a sign-in form from whatever the typed email matches. `fields` are
// the form controls to fill. Runs on change, and on a pause in typing, but
// not on every keystroke.
function ebWireEmailPrefill(form, lookupPath, fields) {
   var emailInput = form.elements["Email"];
   var lastLookedUp = "";
   var pauseTimer = null;

   function lookUp() {
      var email = emailInput.value.trim();
      if (!email || email === lastLookedUp || email.toLowerCase() === "none") {
         return;
      }
      lastLookedUp = email;
      form.elements["ID"].value = "";
      ebLookup(lookupPath, email).then(function (record) {
         if (!record || emailInput.value.trim() !== email) {
            return;
         }
         fields.forEach(function (name) {
            if (record[name] != null && form.elements[name]) {
               form.elements[name].value = record[name];
               form.elements[name].dispatchEvent(new Event("change"));
            }
         });
      });
   }

   emailInput.addEventListener("change", lookUp);
   emailInput.addEventListener("input", function () {
      clearTimeout(pauseTimer);
      pauseTimer = setTimeout(lookUp, 500);
   });
}

// Submit a sign-in form, then return to the welcome page.
function ebWireRegistration(form, registerPath, fields) {
   var statusMsg = document.getElementById("statusMsg");
   var registerButton = document.getElementById("registerBtn");

   function setStatus(text, className) {
      statusMsg.textContent = text;
      statusMsg.className = className;
   }

   form.addEventListener("submit", function (event) {
      event.preventDefault();
      var values = {};
      fields.forEach(function (name) {
         values[name] = form.elements[name].value;
      });
      registerButton.disabled = true;
      setStatus("Registering...", "");
      ebPostForm(registerPath, values).then(function (result) {
         if (result.ok) {
            setStatus("Registration complete. Thank you!", "ok");
            setTimeout(function () { window.location.href = "/"; }, 1200);
         } else {
            registerButton.disabled = false;
            setStatus(result.text || "Registration failed. Please try again.", "err");
         }
      }).catch(function () {
         registerButton.disabled = false;
         setStatus("Registration failed. Please try again.", "err");
      });
   });

   document.getElementById("cancelBtn").addEventListener("click", function () {
      if (window.confirm("Are you sure you want to cancel?")) {
         window.location.href = "/";
      }
   });
}
