function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

export async function sendInviteEmail(
  kind: "admin" | "driver", email: string, link: string, apiKey: string,
): Promise<void> {
  const response = await fetch("https://api.resend.com/emails", {
    signal: AbortSignal.timeout(10_000),
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: "ArangCada <services@info.arangcada.app>",
      to: [email],
      subject: kind === "admin"
        ? "You're invited to the ArangCada admin console"
        : "You're invited to drive for ArangCada",
      html:
        `<p>You've been invited to create an ArangCada ${kind === "admin" ? "LGU/TODA administrator" : "driver"} account.</p>` +
        `<p><a href="${escapeHtml(link)}">Accept the invite and create your account</a></p>` +
        `<p>This link is for one-time use and expires in 7 days. If you were not expecting ` +
        `this invite, you can ignore this email.</p>`,
    }),
  });

  if (!response.ok) {
    const detail = await response.text();
    console.error(`send-${kind}-invite: Resend rejected the send (HTTP ${response.status})`, detail);
    throw new Error(`Resend HTTP ${response.status}`);
  }
}
