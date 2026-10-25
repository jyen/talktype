# talktype

Wispr-Flow-style dictation on your own Cloudflare account. Hold a key, talk, release → cleaned text pastes at your cursor. Self-hosted, no subscription, and **you bring your own account** — speech-to-text and cleanup run on Cloudflare Workers AI, billed to *your* free tier, with no API keys to manage.

- **Speech → text:** `@cf/openai/whisper-large-v3-turbo`
- **Cleanup (filler removal, self-corrections, formatting, your custom vocab):** `@cf/openai/gpt-oss-120b`
- **Feedback loop:** teach it your names/jargon at runtime (by API or by voice) — stored in your own D1 database, no redeploy.

Both models run through the Workers AI binding, which is keyless: it uses whatever Cloudflare account the worker is deployed to. Free tier is 10,000 neurons/day (~hundreds of dictations).

## What's here

- `worker/` — the Cloudflare Worker. `POST /api/dictate` (Bearer token, raw audio) → text.
- `mac/` — a tiny menu-bar app (Swift, no Xcode). Hold right-option to talk.
- `ios/` — a generator for an iPhone Shortcut (record → paste).

## Deploy your own (5 min)

Prereqs: a Cloudflare account and [`wrangler`](https://developers.cloudflare.com/workers/wrangler/) (`npm i -g wrangler`), then `wrangler login`.

```bash
cd worker
./setup.sh          # creates the D1 db, writes wrangler.toml, sets your token, deploys
```

`setup.sh` will:
1. `wrangler d1 create talktype` and drop the database id into `wrangler.toml`
2. apply `schema.sql`
3. prompt for a token (any random string) and store it as the `FLOW_TOKEN` secret
4. `wrangler deploy`

Prefer manual? Copy `wrangler.toml.example` → `wrangler.toml`, fill in `account_id` + `database_id`, then run the four commands above yourself.

Your worker lands at `https://talktype.<you>.workers.dev` (or set a custom domain in `wrangler.toml`).

## Clients

**Mac menu-bar app:**
```bash
cd mac
FLOW_TOKEN=<your-token> FLOW_ENDPOINT=https://talktype.<you>.workers.dev/api/dictate ./build.sh
open build/"TalkType.app"
```
Hold **right-option** to talk, release to paste. Double-tap for hands-free.

**iPhone Shortcut:**
```bash
cd ios
python3 make_shortcut.py <your-token> https://talktype.<you>.workers.dev/api/dictate
# sign it: shortcuts sign --mode anyone -i unsigned.shortcut -o TalkType.shortcut
```
Add it to the Action Button or share sheet.

## Teaching it your vocabulary

Two ways to fix words it mishears — both write to your D1 database and apply on the next dictation, no redeploy:

**By API:**
```bash
# add a term it should know
curl -X POST https://talktype.<you>.workers.dev/api/correct \
  -H "Authorization: Bearer <token>" -H "content-type: application/json" \
  -d '{"kind":"vocab","right":"Servbank"}'

# a hard wrong->right swap (optionally scoped to an app)
curl -X POST .../api/correct -H "Authorization: Bearer <token>" -H "content-type: application/json" \
  -d '{"kind":"replace","wrong":"click fuse","right":"ClickFuze"}'

curl .../api/corrections -H "Authorization: Bearer <token>"   # list them
```

**By voice (hands-free):** start a dictation with *"flow correction, ..."*:
- *"flow correction, add the word Servbank"*
- *"flow correction, change click fuse to ClickFuze"*

It saves the correction and replies `✓ correction saved` instead of pasting.

Edit the starter `VOCAB` list in `worker/src/index.js` for terms you want baked in from day one.

## Privacy

`LOG_DICTATIONS` in `wrangler.toml` controls whether raw/cleaned transcripts are stored in your D1 db (useful for reviewing what it fumbles). Defaults to `"0"` (off) — corrections still work. Set to `"1"` to keep a history. Either way the data lives only in your own Cloudflare account.

## License

MIT — see `LICENSE`.
