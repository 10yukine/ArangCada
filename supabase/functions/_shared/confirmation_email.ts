function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/// The "confirm your email" message. Same sender and look as the invite
/// emails (invite_email.ts).
export async function sendConfirmationEmail(
  email: string, link: string, apiKey: string,
): Promise<void> {
  const safeLink = escapeHtml(link);
  const html = `<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Confirm your email for ArangCada</title></head>
<body style="margin:0;padding:0;background:#eef3fa;font-family:Arial,Helvetica,sans-serif;color:#17305b;">
  <div style="display:none;font-size:1px;color:#eef3fa;line-height:1px;max-height:0;max-width:0;opacity:0;overflow:hidden;">Confirm the email address on your ArangCada account.</div>
  <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#eef3fa;"><tr><td align="center" style="padding:32px 16px;">
    <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="max-width:560px;">
      <tr><td style="padding:0 0 22px;text-align:center;">
        <img src="https://arangcada.app/apple-touch-icon.png" width="64" height="64" alt="ArangCada logo" style="display:inline-block;width:64px;height:64px;border-radius:16px;vertical-align:middle;">
        <span style="display:inline-block;padding-left:9px;color:#17305b;font-size:22px;font-weight:700;letter-spacing:-.5px;vertical-align:middle;">ArangCada</span>
      </td></tr>
      <tr><td style="background:#fff;border:1px solid #d8e3f0;border-radius:18px;padding:40px 36px;">
        <p style="margin:0 0 14px;color:#1262d0;font-size:12px;font-weight:700;letter-spacing:1.5px;text-transform:uppercase;">Your account</p>
        <h1 style="margin:0 0 20px;color:#17305b;font-size:30px;line-height:1.2;">Confirm your email</h1>
        <p style="margin:0;color:#40546f;font-size:16px;line-height:1.65;">This address was given for an ArangCada account. Confirm it so we can reach you about your account.</p>
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr><td align="center" style="padding:32px 0;">
        <table role="presentation" align="center" cellpadding="0" cellspacing="0" border="0" style="margin:0 auto;"><tr><td bgcolor="#1262d0" style="border-radius:999px;"><a href="${safeLink}" style="display:inline-block;padding:15px 30px;color:#fff;font-size:16px;font-weight:700;text-decoration:none;">Confirm my email</a></td></tr></table>
        <p style="margin:12px 0 0;color:#63758f;font-size:12px;line-height:1.6;text-align:center;">Single-use link &middot; Expires in 24 hours</p>
        </td></tr></table>
        <p style="margin:0;padding-top:22px;border-top:1px solid #e3ebf4;color:#63758f;font-size:12px;line-height:1.6;">Not your account? Ignore this email and nothing happens. The address stays unconfirmed.</p>
      </td></tr>
      <tr><td style="padding:22px 12px 0;text-align:center;color:#71819a;font-size:12px;line-height:1.6;">ArangCada · Calamba City<br>If the button does not work, open this link: ${safeLink}</td></tr>
    </table>
  </td></tr></table>
</body></html>`;
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
      subject: "Confirm your email for ArangCada",
      html,
      text: `Confirm your email\n\nThis address was given for an ArangCada account. Confirm it so we can reach you about your account.\n\nConfirm my email: ${link}\n\nSingle-use link · Expires in 24 hours\n\nNot your account? Ignore this email and nothing happens.`,
    }),
  });

  if (!response.ok) {
    const detail = await response.text();
    console.error(`send-email-confirmation: Resend rejected the send (HTTP ${response.status})`, detail);
    throw new Error(`Resend HTTP ${response.status}`);
  }
}
