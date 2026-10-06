// Mints a short-lived, single-use Snowflake embed URL for the viewer app.
// Authenticates as a service user with a key-pair JWT; the private key never reaches the browser.
const crypto = require("crypto");

const {
  SNOWFLAKE_ACCOUNT,      // e.g. SSTQVVW-SA22980 (org-account identifier, uppercase)
  SNOWFLAKE_USER,         // Z21_EMBED_SVC
  SNOWFLAKE_PRIVATE_KEY,  // PKCS8 PEM; "\n" sequences are accepted
  SNOWFLAKE_ROLE,         // Z21_EMBED_MINTER
  STREAMLIT_APP,          // ZERO_TO_ONE_CHAIN.L9_EXPERIENCE.ZERO_TO_ONE_CHAIN_APP
  PARENT_ORIGIN,          // https://<your-project>.vercel.app  (must be registered in Snowflake)
  SNOWFLAKE_HOST = "va61145.ap-south-1.aws.snowflakecomputing.com", // account host (verified)
} = process.env;

const b64url = (b) => Buffer.from(b).toString("base64").replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");

function keyPairJwt() {
  const privateKey = crypto.createPrivateKey(SNOWFLAKE_PRIVATE_KEY.replace(/\\n/g, "\n"));
  const der = crypto.createPublicKey(privateKey).export({ type: "spki", format: "der" });
  const fingerprint = "SHA256:" + crypto.createHash("sha256").update(der).digest("base64");
  const qualified = `${SNOWFLAKE_ACCOUNT.toUpperCase()}.${SNOWFLAKE_USER.toUpperCase()}`;
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({ iss: `${qualified}.${fingerprint}`, sub: qualified, iat: now, exp: now + 300 }));
  const signature = crypto.sign("RSA-SHA256", Buffer.from(`${header}.${claims}`), privateKey);
  return `${header}.${claims}.${b64url(signature)}`;
}

module.exports = async (req, res) => {
  res.setHeader("Cache-Control", "no-store"); // the URL is single-use: never cache it
  try {
    const [db, schema, name] = STREAMLIT_APP.split(".").map(encodeURIComponent);
    const r = await fetch(`https://${SNOWFLAKE_HOST}/api/v2/databases/${db}/schemas/${schema}/streamlits/${name}:generate-embed-url`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${keyPairJwt()}`,
        "X-Snowflake-Authorization-Token-Type": "KEYPAIR_JWT",
        "X-Snowflake-Role": SNOWFLAKE_ROLE,
      },
      body: JSON.stringify({ parent_origin: PARENT_ORIGIN }),
    });
    const text = await r.text();
    if (!r.ok) return res.status(502).json({ error: `Snowflake returned ${r.status}`, detail: text.slice(0, 300) });
    return res.status(200).json({ embedUrl: JSON.parse(text).embed_url });
  } catch (e) {
    return res.status(500).json({ error: String(e.message || e) });
  }
};

module.exports.keyPairJwt = keyPairJwt;
