# 20 — Environment Variables

**Sin valores reales en este documento ni en el repositorio.** Los valores viven en el
gestor de secretos de cada entorno. El repo incluye `.env.example` con las claves vacías.

Leyenda de ámbito:

- **C** — cliente (app móvil). Va embebido en el binario: **asumir que es público**.
- **B** — backend / Edge Functions (secreto de Supabase).
- **E** — solo Edge Functions.
- **CI** — pipeline de integración y despliegue.

---

## 1. Tabla de variables

| Variable | Ámbito | Obligatoria | Descripción |
| --- | --- | --- | --- |
| `SUPABASE_URL` | C, B, E, CI | sí | URL del proyecto Supabase del entorno |
| `SUPABASE_ANON_KEY` | C, CI | sí | Clave pública. Segura en el cliente **solo porque RLS está activo en todas las tablas** |
| `SUPABASE_SERVICE_ROLE_KEY` | B, E, CI | sí | Omnipotente: ignora RLS. **Nunca** en el cliente, nunca en un log, nunca en el repo |
| `GEMINI_API_KEY` | E | sí | Análisis de foto. Solo la Edge Function `analyze-meal-photo` |
| `GEMINI_MODEL` | E | no | Default `gemini-3.6-flash` |
| `GEMINI_THINKING_LEVEL` | E | no | Default `low`. Uno de `minimal`, `low`, `medium`, `high`, o `default` para no mandar el campo. Los Gemini 3 razonan de fábrica en `medium` y eso se paga y se espera; un `gemini-2.5-*` no entiende el campo y rechaza el pedido entero, así que con uno de esos va en `default` |
| `GEMINI_PROMPT_VERSION` | E | no | Default `v3`; se persiste en `ai_analyses` |
| `USDA_API_KEY` | E | sí | FoodData Central |
| `OPEN_FOOD_FACTS_USER_AGENT` | E | sí | `Ceres/1.0 (contacto@ceres.app)` — exigido por su política |
| `RESEND_API_KEY` | E | sí | Correos de exportación y de borrado de cuenta |
| `SENTRY_DSN` | C, CI | sí | DSN del cliente (un DSN es público por diseño) |
| `SENTRY_DSN_FUNCTIONS` | E | sí | DSN del servidor |
| `SENTRY_AUTH_TOKEN` | CI | sí | Subida de símbolos y source maps |
| `POSTHOG_API_KEY` | C, CI | no | Clave pública de analítica |
| `POSTHOG_HOST` | C | no | Default `https://eu.posthog.com` |
| `APP_ENVIRONMENT` | C, B, E, CI | sí | `mock \| dev \| staging \| prod` |
| `API_BASE_URL` | C | sí | Base de las Edge Functions (`${SUPABASE_URL}/functions/v1`) |
| `AI_DAILY_QUOTA` | E | no | Default 20 |
| `HEALTH_SYNC_MIN_INTERVAL_MINUTES` | C | no | Default 30 |
| `FEATURE_BARCODE_SCANNER` | C | no | Flag; default `false` en el MVP |
| `FEATURE_STRENGTH_DETAIL` | C | no | Flag de la fase 2; default `false` |
| `IOS_BUNDLE_ID` / `ANDROID_APPLICATION_ID` | CI | sí | Por flavor |
| `APPLE_TEAM_ID`, `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_PRIVATE_KEY` | CI | sí | Publicación en TestFlight / App Store |
| `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | CI | sí | Firma de Android |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | CI | sí | Publicación en Play |
| `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF` | CI | sí | Migraciones y despliegue de funciones |

## 2. Qué va en el cliente y qué no

**Puede ir en el cliente** (público por diseño): `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
`SENTRY_DSN`, `POSTHOG_API_KEY`, `APP_ENVIRONMENT`, `API_BASE_URL`, los flags.

**Nunca en el cliente:** `SUPABASE_SERVICE_ROLE_KEY`, `GEMINI_API_KEY`, `USDA_API_KEY`,
`RESEND_API_KEY`, `SENTRY_AUTH_TOKEN`, cualquier credencial de firma o de tienda.

> El motivo por el que la `ANON_KEY` puede viajar en el binario es que **RLS está activo en
> todas las tablas**. Si alguna tabla quedara sin RLS, esa clave se convierte en acceso
> abierto a los datos de todos los usuarios. Por eso el test que enumera las tablas sin RLS
> es bloqueante (fase 13).

## 3. Dónde se configura cada ámbito

| Ámbito | Mecanismo |
| --- | --- |
| Cliente | `--dart-define-from-file=env/{flavor}.json` (Flutter) o `app.config.ts` + `expo-constants` (RN). Nunca un `.env` empaquetado como asset |
| Edge Functions | `supabase secrets set --project-ref <ref> KEY=value` |
| Postgres | `alter database … set app.<key>` solo para parámetros no sensibles |
| CI | Secretos de GitHub Actions, por entorno (`dev`, `staging`, `prod`) con revisión obligatoria para `prod` |

## 4. `.env.example` (versionado, sin valores)

```dotenv
# ── Cliente ────────────────────────────────────────────
SUPABASE_URL=
SUPABASE_ANON_KEY=
API_BASE_URL=
APP_ENVIRONMENT=dev
SENTRY_DSN=
POSTHOG_API_KEY=
POSTHOG_HOST=https://eu.posthog.com
FEATURE_BARCODE_SCANNER=false
FEATURE_STRENGTH_DETAIL=false
HEALTH_SYNC_MIN_INTERVAL_MINUTES=30

# ── Edge Functions (supabase secrets set) ──────────────
SUPABASE_SERVICE_ROLE_KEY=
GEMINI_API_KEY=
GEMINI_MODEL=gemini-3.6-flash
GEMINI_THINKING_LEVEL=low
GEMINI_PROMPT_VERSION=v3
USDA_API_KEY=
OPEN_FOOD_FACTS_USER_AGENT=Ceres/1.0 (contacto@ceres.app)
RESEND_API_KEY=
SENTRY_DSN_FUNCTIONS=
AI_DAILY_QUOTA=20

# ── CI/CD (secretos del pipeline) ──────────────────────
SUPABASE_ACCESS_TOKEN=
SUPABASE_PROJECT_REF=
SENTRY_AUTH_TOKEN=
APPLE_TEAM_ID=
APP_STORE_CONNECT_KEY_ID=
APP_STORE_CONNECT_ISSUER_ID=
APP_STORE_CONNECT_PRIVATE_KEY=
ANDROID_KEYSTORE_BASE64=
ANDROID_KEYSTORE_PASSWORD=
ANDROID_KEY_ALIAS=
ANDROID_KEY_PASSWORD=
GOOGLE_PLAY_SERVICE_ACCOUNT_JSON=
```

## 5. Higiene de secretos

- `.env`, `env/*.json`, keystores y claves `.p8` en `.gitignore`.
- **Gitleaks** en el pre-commit y en el CI; un hallazgo bloquea el merge.
- Rotación: claves de proveedores externos cada 12 meses o de inmediato ante sospecha de
  filtración; la `service_role` cada 6 meses.
- Ninguna variable sensible se imprime en logs: el logger tiene una lista de claves
  redactadas (`*KEY*`, `*TOKEN*`, `*SECRET*`, `authorization`).
- El modo `mock` no requiere **ninguna** variable: la app corre completa sin configurar nada,
  lo que permite que alguien clone el repo y la levante en un minuto.
