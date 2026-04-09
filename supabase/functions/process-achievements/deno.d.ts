/**
 * Minimal `Deno` typing for the VS Code TypeScript server (runtime is Deno on deploy).
 */

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
