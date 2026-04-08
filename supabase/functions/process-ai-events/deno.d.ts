/**
 * Minimal `Deno` typing for the VS Code TypeScript server (runtime is Deno on deploy).
 * The real types come from `jsr:@supabase/functions-js/edge-runtime.d.ts` at build time.
 */
declare const Deno: {
  env: {
    get(key: string): string | undefined;
  };
  serve(
    handler: (req: Request) => Response | Promise<Response>,
  ): void;
};
