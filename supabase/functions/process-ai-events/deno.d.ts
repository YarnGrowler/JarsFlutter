/**
 * Minimal `Deno` typing for the VS Code TypeScript server (runtime is Deno on deploy).
 * The real types come from `jsr:@supabase/functions-js/edge-runtime.d.ts` at build time.
 */

/** VS Code tsserver cannot resolve `npm:` specifiers; Deno does at bundle/deploy time. */
declare module "npm:@supabase/supabase-js@2" {
  export function createClient(
    supabaseUrl: string,
    supabaseKey: string,
    options?: Record<string, unknown>,
  ): // deno-lint-ignore no-explicit-any
  any;
}

declare const Deno: {
  env: {
    get(key: string): string | undefined;
  };
  serve(
    handler: (req: Request) => Response | Promise<Response>,
  ): void;
};
