// Passkeys: the device's own lock (fingerprint, face, PIN) instead of a
// code. Buttons carry data-passkey="sign-in" | "register" | "admin"; the
// server gives options (a challenge, used once), the browser signs, the
// server checks and answers the page to open next. WebAuthn speaks bytes,
// the server base64url. Buttons stay hidden where passkeys do not work.

import {toast} from "./toasts"

const ENDPOINTS = {
  "sign-in": ["/account/passkey/options", "/account/passkey"],
  register: ["/account/passkeys/options", "/account/passkeys"],
  admin: ["/account/admin-proof/options", "/account/admin-proof"],
}

const bytes = (value) => {
  const base64 = (value + "=".repeat((4 - (value.length % 4)) % 4)).replace(/-/g, "+").replace(/_/g, "/")
  return Uint8Array.from(atob(base64), (c) => c.charCodeAt(0)).buffer
}

const text = (buffer) =>
  btoa(String.fromCharCode(...new Uint8Array(buffer))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")

const csrf = () => document.querySelector("meta[name='csrf-token']")?.content || ""

async function post(url, body) {
  const response = await fetch(url, {
    method: "POST",
    credentials: "same-origin",
    headers: {"content-type": "application/json", accept: "application/json", "x-csrf-token": csrf()},
    body: JSON.stringify(body || {}),
  })
  if (!response.ok) throw new Error("refused")
  return response.json()
}

async function ceremony(action, name) {
  const [optionsUrl, url] = ENDPOINTS[action]
  const options = await post(optionsUrl)
  const publicKey = options.public_key

  if (action === "register") {
    const credential = await navigator.credentials.create({
      publicKey: {
        ...publicKey,
        challenge: bytes(publicKey.challenge),
        user: {...publicKey.user, id: bytes(publicKey.user.id)},
        excludeCredentials: (publicKey.excludeCredentials || []).map((c) => ({type: c.type, id: bytes(c.id)})),
      },
    })
    return post(url, {
      challenge_id: options.challenge_id,
      attestation_object: text(credential.response.attestationObject),
      client_data_json: text(credential.response.clientDataJSON),
      name,
    })
  }

  const credential = await navigator.credentials.get({
    publicKey: {
      ...publicKey,
      challenge: bytes(publicKey.challenge),
      allowCredentials: (publicKey.allowCredentials || []).map((c) => ({type: c.type, id: bytes(c.id)})),
    },
  })
  return post(url, {
    challenge_id: options.challenge_id,
    credential_id: text(credential.rawId),
    authenticator_data: text(credential.response.authenticatorData),
    client_data_json: text(credential.response.clientDataJSON),
    signature: text(credential.response.signature),
  })
}

// The person closed the system dialog: nothing to report.
const cancelled = (e) => e instanceof DOMException && (e.name === "NotAllowedError" || e.name === "AbortError")

export function initPasskeys() {
  const buttons = document.querySelectorAll("[data-passkey]")
  if (!buttons.length) return
  const supported = "PublicKeyCredential" in window && !!navigator.credentials

  document.querySelectorAll(".passkey-unsupported").forEach((el) => (el.hidden = supported))
  if (!supported) return
  document.querySelectorAll(".passkey-hint").forEach((el) => (el.hidden = false))

  buttons.forEach((button) => {
    button.hidden = false
    button.addEventListener("click", async () => {
      if (button.getAttribute("aria-busy") === "true") return
      button.setAttribute("aria-busy", "true")
      const nameField = button.dataset.passkeyName && document.getElementById(button.dataset.passkeyName)
      try {
        const answer = await ceremony(button.dataset.passkey, nameField?.value || defaultName())
        window.location.assign(answer.redirect)
      } catch (e) {
        if (!cancelled(e)) {
          toast({id: "passkey", kind: "warning", message: button.dataset.error})
        }
      } finally {
        button.removeAttribute("aria-busy")
      }
    })
  })
}

// "iPhone", "Mac"…: a name to recognise the passkey in « Security ».
function defaultName() {
  const ua = navigator.userAgent
  if (/iPhone/.test(ua)) return "iPhone"
  if (/iPad/.test(ua)) return "iPad"
  if (/Android/.test(ua)) return "Android"
  if (/Mac OS X/.test(ua)) return "Mac"
  if (/Windows/.test(ua)) return "Windows"
  return "Passkey"
}
