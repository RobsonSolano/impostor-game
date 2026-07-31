import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  // Override default ignores of eslint-config-next.
  globalIgnores([
    // Default ignores of eslint-config-next:
    ".next/**",
    "out/**",
    "build/**",
    "next-env.d.ts",
    // Artefatos de runtime do Supabase CLI (código minificado do edge runtime).
    "supabase/.temp/**",
    // Gerado por `supabase gen types` — não editar, não lintar.
    "src/lib/supabase/database.types.ts",
  ]),
]);

export default eslintConfig;
