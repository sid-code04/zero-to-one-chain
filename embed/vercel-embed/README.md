# Zero to One Chain: public embed (Vercel)

A static page plus one serverless function. The function signs a short-lived key-pair JWT as the Snowflake
service user `Z21_EMBED_SVC`, asks Snowflake for a single-use embed URL of the read-only viewer app, and the
page shows it in an iframe. Visitors need no Snowflake login.

## Deploy (about 5 minutes)

1. **Put this folder in Vercel.** Easiest: install the Vercel CLI and run `vercel` inside this folder
   (or push the folder to GitHub and import the repo in the Vercel dashboard).
   Vercel gives you a URL like `https://zero-to-one-chain.vercel.app`.

2. **Add 5 environment variables** (Vercel > Project > Settings > Environment Variables, Production):

   | Name | Value |
   |---|---|
   | `SNOWFLAKE_ACCOUNT` | `SSTQVVW-SA22980` |
   | `SNOWFLAKE_USER` | `Z21_EMBED_SVC` |
   | `SNOWFLAKE_ROLE` | `Z21_EMBED_MINTER` |
   | `STREAMLIT_APP` | `ZERO_TO_ONE_CHAIN.L9_EXPERIENCE.ZERO_TO_ONE_CHAIN_APP` |
   | `PARENT_ORIGIN` | your exact Vercel URL, e.g. `https://zero-to-one-chain.vercel.app` (https, no trailing slash, no path) |
   | `SNOWFLAKE_PRIVATE_KEY` | the full contents of `secrets/rsa_key.p8`, including the BEGIN/END lines |

   Mark `SNOWFLAKE_PRIVATE_KEY` as Sensitive. Redeploy after adding variables.

3. **Tell Snowflake your domain** (run in Snowsight as ACCOUNTADMIN; this REPLACES the list, so keep both lines):

   ```sql
   ALTER ACCOUNT SET STREAMLIT_EMBEDDING_CONTROLS = $$
   allowed_embedding_domains:
     - https://zero-to-one-chain.vercel.app
     - http://localhost:3000
   $$;
   ```

4. **Open your Vercel URL.** The first load can take up to a minute while the app container starts.

## Troubleshooting

| Symptom | Cause |
|---|---|
| Page says `Snowflake returned 400` or origin error | `PARENT_ORIGIN` differs from the page URL, or the domain is not in step 3 |
| `Snowflake returned 401/403` | Private key does not match the registered key, or an extra role is being requested |
| Blank frame | Container still starting; wait a minute and reload |

## Security notes

- The private key lives only in Vercel's environment and in `secrets/`. Delete `secrets/` from the workspace once it is in Vercel.
- The service user can only mint URLs for this one app. The viewer app is read-only and runs as a role with no write access.
- Anyone who opens the Vercel page sees the project data, and every visitor uses your warehouse credits.
- **Turn it off instantly:** `REVOKE EMBED ON STREAMLIT ZERO_TO_ONE_CHAIN.L9_EXPERIENCE.ZERO_TO_ONE_CHAIN_APP FROM ROLE Z21_EMBED_MINTER;`
- **Rotate the key:** generate a new pair, `ALTER USER Z21_EMBED_SVC SET RSA_PUBLIC_KEY = '...'`, update the Vercel variable.
